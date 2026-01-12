// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

/// ListenButton — отдельный виджет для "Прослушал речь жизни".
/// onListenComplete: получает парсенный ответ от RPC (Map<String,dynamic>?) сразу после успешного выполнения.
///   Позволяет родительскому экрану применить изменения локально и/или перезагрузить профиль.
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

  bool _sessionListened = false; // one per app session
  bool _loading = false;

  static const int _fixedN = 100; // fixed n per spec
  static const int _mindForYes = 2 * _fixedN; // 200
  static const int _vForNo = _fixedN; // 100

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
    // Confirm Yes/No
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
      final dynamic rpcRes = await _svc.rpcListenSpeech(
        speechId: sid,
        userId: widget.userId,
        agree: agree,
        n: _fixedN,
      );

      // Debug print (useful while testing)
      // print('listen_speech rpcRes: $rpcRes');

      if (rpcRes is Map<String, dynamic>) {
        parsed = rpcRes;
      } else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
        parsed = Map<String, dynamic>.from(rpcRes[0] as Map);
      } else if (rpcRes is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(rpcRes) as Map);
        } catch (_) {
          parsed = null;
        }
      } else {
        parsed = null;
      }

      String message;
      if (parsed != null) {
        final status = parsed['status']?.toString() ?? '';
        if (agree && status == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? widget.speechActorId ?? '(неизвестно)';
          final addedM = parsed['added_m']?.toString() ?? _mindForYes.toString();
          message = 'Ваш цвет изменён на $newColor. В банк цвета добавлено $addedM майндов.';
        } else if (!agree && status == 'kept_color') {
          final addedV = parsed['added_v']?.toString() ?? _vForNo.toString();
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено $addedV войсов.';
        } else {
          // RPC вернул что-то нестандартное — покажем весь ответ
          message = 'Ответ сервера: ${parsed.toString()}';
        }
      } else {
        // Если сервер вернул неструктурированный ответ
        if (agree) {
          message = 'Ваш цвет изменён. В банк цвета перечислено $_mindForYes майндов.';
        } else {
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено $_vForNo войсов.';
        }
      }

      // Пометить клик за сессию
      setState(() => _sessionListened = true);

      // Показываем подтверждение пользователю
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
        ),
      );

      // Вызов callback'а родительского экрана и передача parsed (может быть null)
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (e) {
          // ignore callback errors but notify in debug
          // print('onListenComplete error: $e');
        }
      }
    } catch (e) {
      // RPC error — не помечаем как прослушанное в сессии
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
        onPressed: _isEnabled ? _onPressed : null,
        style: ElevatedButton.styleFrom(backgroundColor: _isEnabled ? Colors.blueAccent : Colors.grey),
        child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    );
  }
}
