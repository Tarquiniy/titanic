// lib/widgets/listen_button.dart
//
// Переписанный полностью автономный виджет кнопки "Прослушал речь жизни".
// Поведение:
//  - кнопка активна, если есть activeSpeechId ИЛИ speechActive == true (на случай, если id ещё не синхронизирован).
//  - при нажатии берёт реальный speechId (если нужно — достаёт его с сервера),
//    затем показывает диалог "Да / Нет" по ТЗ.
//  - при выборе "Да" вызывает RPC listen_speech(p_agree = true, p_n = 100).
//    при успешном результате показывает диалог об изменении цвета и начислении 2*100 майндов.
//  - при выборе "Нет" вызывает RPC listen_speech(p_agree = false, p_n = 100).
//    при успешном результате показывает диалог "Вы остались верны себе..." и начисление 100 V.
//  - помечает прослушивание в сессии только при успешном RPC.
//  - вызывает onListenComplete(parsedResult) для родителя, чтобы тот обновил профиль/UI.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

typedef ListenCompleteCallback = Future<void> Function(Map<String, dynamic>? rpcResult);

class ListenButton extends StatefulWidget {
  final String userId; // UUID string
  final int? activeSpeechId; // id из life_speeches (может быть null до синхронизации)
  final String? speechActorId; // id политика (опционально)
  final bool speechActive; // локальный флаг активности речи (может быть true до получения id)
  final bool alreadyListened; // серверный флаг: пользователь уже слушал текущую речь
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

  static const int _fixedN = 100;

  /// Кнопка активна если:
  ///  - виджет сообщает speechActive == true (речь начата) OR
  ///  - уже пришёл activeSpeechId (точный id)
  /// и пользователь ещё не слушал (ни серверно, ни в сессии), и не в загрузке.
  bool get _isEnabled {
    if (_loading) return false;
    if (_sessionListened) return false;
    if (widget.alreadyListened) return false;
    if (widget.activeSpeechId != null) return true;
    if (widget.speechActive) return true;
    return false;
  }

  int? _parseId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<int?> _ensureSpeechId() async {
    // Prefer explicit activeSpeechId if provided.
    if (widget.activeSpeechId != null) return widget.activeSpeechId;
    // If speechActive true but id missing, try to fetch the active life_speeches row.
    try {
      final life = await _svc.getActiveLifeSpeech();
      if (life is Map<String, dynamic>) {
        final id = _parseId(life['id']);
        return id;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _handlePress() async {
    if (!_isEnabled) return;

    // Ensure we have a real speech id before doing anything that would call RPC.
    setState(() => _loading = true);
    int? sid = await _ensureSpeechId();
    if (sid == null) {
      // fallback: no id available
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет активной речи (id). Попробуйте чуть позже.')));
      }
      return;
    }

    // show Yes/No dialog (text per TЗ)
    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Прослушал речь жизни'),
        content: const Text(
          'Вы прослушали речь жизни и она произвела на вас впечатление?\n\n'
          'Если Да — учтите, ваш цвет изменится!',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Нет')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Да')),
        ],
      ),
    );

    if (agree == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    Map<String, dynamic>? parsed;
    try {
      final res = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);

      // normalize
      if (res is Map<String, dynamic>) {
        parsed = res;
      } else if (res is List && res.isNotEmpty && res[0] is Map) {
        parsed = Map<String, dynamic>.from(res[0] as Map);
      } else if (res is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          parsed = null;
        }
      } else {
        parsed = null;
      }

      // Show results according to TЗ
      if (agree) {
        // expect changed_color
        if (parsed != null && parsed['status'] == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? widget.speechActorId ?? '(новый цвет)';
          final addedM = parsed['added_m'] ?? (2 * _fixedN);
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Цвет изменён'),
              content: Text('Ваш цвет изменён на $newColor.\nВ банк цвета добавлено ${addedM.toString()} майндов.'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        } else {
          // fallback: show raw or generic
          final text = parsed != null ? parsed.toString() : 'Действие выполнено. Пожалуйста, обновите профиль.';
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Результат'),
              content: Text(text),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        }
      } else {
        // expect kept_color
        if (parsed != null && parsed['status'] == 'kept_color') {
          final addedV = parsed['added_v'] ?? _fixedN;
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Спасибо'),
              content: Text('Вы остались верны себе, это достойно!\nВам начислено ${addedV.toString()} войсов.'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        } else {
          final text = parsed != null ? parsed.toString() : 'Действие выполнено. Пожалуйста, обновите профиль.';
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Результат'),
              content: Text(text),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        }
      }

      // mark session listened only after successful RPC
      setState(() => _sessionListened = true);

      // callback parent to update UI/profile
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (_) {
          // ignore
        }
      } else {
        // small indicator if no callback
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Прослушивание зафиксировано.')));
      }
    } catch (e) {
      // RPC failure - keep button enabled (not marked listened)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = (_sessionListened || widget.alreadyListened) ? 'Уже прослушал' : 'Прослушал речь жизни';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isEnabled ? _handlePress : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEnabled ? Colors.blueAccent : Colors.grey,
        ),
        child: _loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      ),
    );
  }
}
