// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

/// ListenButton — отдельный виджет для "Прослушал речь жизни".
/// Параметры:
/// - userId: id текущего пользователя (String)
/// - activeSpeechId: id текущей активной речи (int?)
/// - speechActorId: id политика, произносящего речь (String?) — нужен чтобы брать его цвет
/// - alreadyListened: true если сервер говорит, что пользователь уже слушал эту речь
/// - onListenComplete: callback, вызывается после успешного завершения (для refresh)
class ListenButton extends StatefulWidget {
  final String userId;
  final int? activeSpeechId;
  final String? speechActorId;
  final bool alreadyListened;
  final Future<void> Function()? onListenComplete;

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

  static const int _fixedN = 100; // fixed n per your spec
  static const int _mindForYes = 2 * _fixedN; // 2 * 100
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
    // Show confirm dialog with Yes/No
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

    // if user dismissed dialog => do nothing
    if (agree == null) return;

    setState(() {
      _loading = true;
    });

    try {
      final dynamic rpcRes = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);

      Map<String, dynamic>? parsed;
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

      String message = '';
      if (parsed != null) {
        final status = parsed['status']?.toString() ?? '';
        if (agree && status == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? widget.speechActorId ?? '';
          final addedM = parsed['added_m'] ?? _mindForYes;
          message = 'Ваш цвет изменён на $newColor. В банк цвета добавлено ${addedM.toString()}.';
        } else if (!agree && status == 'kept_color') {
          final addedV = parsed['added_v'] ?? _vForNo;
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено ${addedV.toString()} войсов.';
        } else {
          // RPC дал ответ, но не в ожидаемом формате
          message = parsed.toString();
        }
      } else {
        // Нет структурированного ответа — сформируем сообщение по локальной логике
        if (agree) {
          message = 'Ваш цвет изменён. В банк цвета перечислено $_mindForYes майндов.';
        } else {
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено $_vForNo войсов.';
        }
      }

      // mark session click and show result dialog
      setState(() {
        _sessionListened = true;
      });

      // Update the UI with a dialog
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
        ),
      );

      // call callback to refresh profile/speech-state on home screen
      if (widget.onListenComplete != null) {
        await widget.onListenComplete!();
      }
    } catch (e) {
      // RPC error — show error and do NOT mark session listened
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${e.toString()}')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
