// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

/// ListenButton — отдельный виджет для "Прослушал речь жизни".
/// - userId: текущий user id (UUID string)
/// - activeSpeechId: текущий life_speeches.id
/// - speechActorId: id политика (опционально, для отображения)
/// - alreadyListened: server-side flag (user already listened to this speech)
/// - onListenComplete: callback(Map<String,dynamic>? rpcResult) после успешного выполнения RPC
class ListenButton extends StatefulWidget {
  final String userId;
  final int? activeSpeechId;
  final String? speechActorId;
  final bool alreadyListened;
  final Future<void> Function(Map<String, dynamic>? rpcResult)? onListenComplete;

  const ListenButton({
    Key? key,
    required this.userId,
    required this.activeSpeechId,
    this.speechActorId,
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
    if (widget.activeSpeechId == null) return false;
    return true;
  }

  Future<void> _onPressed() async {
    if (!_isEnabled) return;
    final sid = widget.activeSpeechId!;
    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Прослушал речь жизни'),
          content: const Text('Согласны поменять цвет на цвет политика, который произносит речь жизни?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Нет')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Да')),
          ],
        );
      },
    );

    if (agree == null) return;

    setState(() => _loading = true);

    Map<String, dynamic>? parsed;
    try {
      final rpcRes = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);

      // parse rpcRes to Map if possible
      if (rpcRes is Map<String, dynamic>) {
        parsed = rpcRes;
      } else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
        parsed = Map<String, dynamic>.from(rpcRes[0] as Map);
      } else if (rpcRes is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(rpcRes) as Map);
        } catch (_) {
          // leave parsed null and show raw
        }
      }

      // Show immediate result to user
      String message;
      if (parsed != null) {
        final status = parsed['status']?.toString() ?? '';
        if (status == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? '(неизвестно)';
          final addedM = parsed['added_m']?.toString() ?? '0';
          message = 'Ваш цвет изменён на $newColor. В банк цвета добавлено $addedM майндов.';
        } else if (status == 'kept_color') {
          final addedV = parsed['added_v']?.toString() ?? '0';
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено $addedV войсов.';
        } else {
          message = 'Ответ сервера: ${parsed.toString()}';
        }
      } else {
        // fallback if RPC returned non-map
        message = 'Действие выполнено. Пожалуйста, обновите профиль.';
      }

      // Mark session listened only on success
      setState(() {
        _sessionListened = true;
      });

      // Show confirmation dialog
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
        ),
      );

      // Call parent's callback with parsed map (may be null)
      if (widget.onListenComplete != null) {
        await widget.onListenComplete!(parsed);
      } else {
        // If no callback, show a short snackbar so user sees something changed
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Прослушивание зафиксировано.')));
      }
    } catch (e) {
      // Do not mark as listened if RPC failed
      final err = e?.toString() ?? 'Unknown error';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка RPC: $err')));
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
        onPressed: _isEnabled ? _onPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: _isEnabled ? Colors.blueAccent : Colors.grey),
        child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    );
  }
}
