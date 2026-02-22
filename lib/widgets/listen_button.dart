// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/services/enterprise_service.dart';

// ✅ чтобы выглядело как остальные кнопки на HomeScreen
import 'package:titanic/widgets/art_deco_button.dart';

typedef ListenCompleteCallback = Future<void> Function(
  Map<String, dynamic>? rpcResult,
);

class ListenButton extends StatefulWidget {
  final String userId;
  final int? activeSpeechId;
  final String? speechActorId;
  final bool speechActive;
  final bool alreadyListened;
  final ListenCompleteCallback? onListenComplete;

  const ListenButton({
    Key? key,
    required this.userId,
    required this.activeSpeechId,
    this.speechActorId,
    required this.speechActive,
    this.alreadyListened = false,
    this.onListenComplete,
  }) : super(key: key);

  @override
  State<ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<ListenButton> {
  final GameService _svc = GameService();
  bool _sessionListened = false;
  bool _loading = false;

  // ✅ серверная истина: есть ли запись в life_speech_listeners
  bool _serverListened = false;
  int? _lastCheckedSpeechId;

  // n по ТЗ (фиксированное)
  static const int _fixedN = 100;

  bool get _isEnabled {
    if (_loading) return false;
    if (_sessionListened) return false;
    if (_serverListened) return false;
    if (widget.alreadyListened) return false;

    // если есть активная речь — кнопку можно нажать (если не слушал)
    if (widget.activeSpeechId != null) return true;
    if (widget.speechActive) return true;
    return false;
  }

  void _dbg(String s) => debugPrint('ListenButton: $s');

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _bootstrapServerListened();
  }

  @override
  void didUpdateWidget(covariant ListenButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // если сменилась активная речь (id) или изменился пользователь — перепроверяем
    final oldSid = oldWidget.activeSpeechId;
    final newSid = widget.activeSpeechId;

    final shouldRecheck = oldWidget.userId != widget.userId ||
        oldSid != newSid ||
        oldWidget.speechActive != widget.speechActive;

    if (shouldRecheck) {
      _bootstrapServerListened(force: true);
    }
  }

  Future<int?> _ensureSpeechId() async {
    if (widget.activeSpeechId != null) {
      _dbg('using provided activeSpeechId=${widget.activeSpeechId}');
      return widget.activeSpeechId;
    }

    _dbg('no activeSpeechId provided, trying to fetch active life_speeches row');
    try {
      final life = await _svc.getActiveLifeSpeech();
      _dbg('getActiveLifeSpeech -> $life');
      if (life is Map<String, dynamic>) {
        final idRaw = life['id'];
        final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
        _dbg('fetched active life_speeches id=$id');
        return id;
      }
    } catch (e, st) {
      _dbg('error fetching active life speech: $e\n$st');
    }

    return null;
  }

  Future<void> _bootstrapServerListened({bool force = false}) async {
    // Если HomeScreen уже говорит "уже слушал", сразу фиксируем
    if (widget.alreadyListened) {
      if (mounted) setState(() => _serverListened = true);
      return;
    }

    // Нам нужен speechId, чтобы проверить life_speech_listeners
    final sid = await _ensureSpeechId();
    if (sid == null) return;

    if (!force && _lastCheckedSpeechId == sid) return;
    _lastCheckedSpeechId = sid;

    try {
      final res = await _supabase
          .from('life_speech_listeners')
          .select('id')
          .eq('speech_id', sid)
          .eq('user_id', widget.userId)
          .limit(1)
          .maybeSingle();

      final listened = res != null;

      if (mounted) {
        setState(() {
          _serverListened = listened;
          // если на сервере уже есть — то и локально считаем, что слушал
          if (listened) _sessionListened = true;
        });
      }
    } catch (e, st) {
      _dbg('bootstrapServerListened failed: $e\n$st');
      // ошибки молча: кнопка останется активной, но это лучше чем блок навсегда
    }
  }

  Future<void> _handlePress() async {
    if (!_isEnabled) {
      _dbg('pressed but not enabled');
      return;
    }

    setState(() => _loading = true);
    _dbg('button pressed; ensuring speech id...');

    final int? sid = await _ensureSpeechId();
    if (sid == null) {
      _dbg('no speech id available');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет активной речи (id). Попробуйте чуть позже.'),
          ),
        );
      }
      return;
    }

    // ✅ перед нажатием ещё раз проверим сервер (на случай релогина/ре-рендера)
    await _bootstrapServerListened(force: true);
    if (_serverListened || widget.alreadyListened) {
      if (mounted) {
        setState(() {
          _sessionListened = true;
          _loading = false;
        });
      }
      return;
    }

    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Прослушал речь жизни'),
        content: const Text(
          'Вы прослушали речь жизни и она произвела на вас впечатление?\n\nЕсли Да — учтите, ваш цвет изменится!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Нет'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Да'),
          ),
        ],
      ),
    );

    if (agree == null) {
      _dbg('dialog returned null (should not occur)');
      if (mounted) setState(() => _loading = false);
      return;
    }

    _dbg(
      'calling rpcListenSpeech with sid=$sid user=${widget.userId} agree=$agree n=$_fixedN',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отправка запроса...')),
      );
    }

    try {
      final parsed = await _svc.rpcListenSpeech(
        speechId: sid,
        userId: widget.userId,
        agree: agree,
        n: _fixedN,
      );

      _dbg('rpcListenSpeech parsed -> $parsed');

      final status = parsed['status']?.toString() ?? '';

      // ---- ЕСЛИ ЦВЕТ БЫЛ ИЗМЕНЁН И ПОЛЬЗОВАТЕЛЬ - ЭКОНОМИСТ - ОБНОВЛЯЕМ ПРЕДПРИЯТИЯ ----
      if (agree && status == 'changed_color') {
        final newColor =
            parsed['new_color']?.toString() ?? widget.speechActorId ?? '';
        if (newColor.isNotEmpty) {
          try {
            final userRes = await _supabase
                .from('user_credentials')
                .select('role')
                .eq('id', widget.userId)
                .maybeSingle();

            final role = (userRes?['role'] ?? '').toString().toLowerCase();
            final isEconomist = role == 'economist' || role == 'экономист';

            if (isEconomist) {
              final enterpriseService = EnterpriseService(_supabase);
              await enterpriseService.updateEnterprisesColorForEconomist(
                economistId: widget.userId,
                newColor: newColor,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Цвет ваших предприятий обновлён')),
                );
              }
            }
          } catch (e) {
            debugPrint(
              'ListenButton: ошибка обновления предприятий экономиста: $e',
            );
          }
        }
      }
      // ------------------------------------------------------------------------------------

      if (agree && status == 'changed_color') {
        final newColor = parsed['new_color']?.toString() ??
            widget.speechActorId ??
            '(новый цвет)';
        final addedM = parsed['added_m'] ?? (2 * _fixedN);

        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Цвет изменён'),
            content: Text(
              'Ваш цвет изменён на $newColor.\nВ банк цвета добавлено ${addedM.toString()} майндов.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ОК'),
              ),
            ],
          ),
        );
      } else if (!agree && status == 'kept_color') {
        // ✅ НЕ ДОБАВЛЯЕМ КЛИЕНТОМ — доверяем RPC
        final addedV = parsed['added_v'] ?? _fixedN;

        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Спасибо'),
            content: Text(
              'Спасибо, вы остались верны своему цвету.\nНа ваш счёт добавлено ${addedV.toString()} войсов.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ОК'),
              ),
            ],
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Результат'),
            content: Text(parsed.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ОК'),
              ),
            ],
          ),
        );
      }

      // ✅ фиксируем локально и серверно-логически
      if (mounted) {
        setState(() {
          _sessionListened = true;
          _serverListened = true;
        });
      }

      // callback
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (e, st) {
          _dbg('onListenComplete error: $e\n$st');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Прослушивание зафиксировано.')),
          );
        }
      }
    } catch (e, st) {
      _dbg('rpcListenSpeech failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool listened = _sessionListened || _serverListened || widget.alreadyListened;

    final String text = _loading
        ? 'Отправка...'
        : (listened ? 'Уже прослушал' : 'Прослушал речь жизни');

    final bool enabled = _isEnabled;

    return AbsorbPointer(
      absorbing: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: ArtDecoButton(
          text: text,
          icon: Icons.headset_mic,
          onPressed: enabled ? _handlePress : () {},
          primary: enabled,
          expanded: true,
        ),
      ),
    );
  }
}
