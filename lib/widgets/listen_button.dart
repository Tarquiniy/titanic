// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:titanic/services/game_service.dart';

typedef ListenCompleteCallback = Future<void> Function(Map<String, dynamic>? rpcResult);

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
  static const int _fixedN = 100;

  bool get _isEnabled {
    if (_loading) return false;
    if (_sessionListened) return false;
    if (widget.alreadyListened) return false;
    if (widget.activeSpeechId != null) return true;
    if (widget.speechActive) return true;
    return false;
  }

  void _dbg(String s) => debugPrint('ListenButton: $s');

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

  Future<void> _handlePress() async {
    if (!_isEnabled) {
      _dbg('pressed but not enabled');
      return;
    }

    setState(() => _loading = true);
    _dbg('button pressed; ensuring speech id...');
    int? sid = await _ensureSpeechId();
    if (sid == null) {
      _dbg('no speech id available');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет активной речи (id). Попробуйте чуть позже.')));
      }
      return;
    }

    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Прослушал речь жизни'),
        content: const Text('Вы прослушали речь жизни и она произвела на вас впечатление?\n\nЕсли Да — учтите, ваш цвет изменится!'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Нет')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Да')),
        ],
      ),
    );

    if (agree == null) {
      _dbg('dialog returned null (should not occur)');
      setState(() => _loading = false);
      return;
    }

    _dbg('calling rpcListenSpeech with sid=$sid user=${widget.userId} agree=$agree n=$_fixedN');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка запроса...')));

    try {
      final parsed = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);
      _dbg('rpcListenSpeech parsed -> $parsed');

      final status = parsed['status']?.toString() ?? '';

      if (agree && status == 'changed_color') {
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
      } else if (!agree && status == 'kept_color') {
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
        // Unexpected but show raw
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Результат'),
            content: Text(parsed.toString()),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
          ),
        );
      }

      // success -> mark session listened and notify parent
      setState(() => _sessionListened = true);
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (e, st) {
          _dbg('onListenComplete error: $e\n$st');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Прослушивание зафиксировано.')));
      }
    } catch (e, st) {
      _dbg('rpcListenSpeech failed: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${e.toString()}')));
      // Do not mark as listened
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
        style: ElevatedButton.styleFrom(backgroundColor: _isEnabled ? Colors.blueAccent : Colors.grey),
        child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    );
  }
}
