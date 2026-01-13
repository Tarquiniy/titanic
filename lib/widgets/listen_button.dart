// lib/widgets/listen_button.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

/// ListenButton — отдельный виджет для "Прослушал речь жизни".
/// - activeSpeechId: id записи из life_speeches (int?)
/// - speechActorId: id политика (String?) — используется для подсказок/логики
/// - speechActive: булев флаг, активна ли речь сейчас (из home_screen)
/// - alreadyListened: server-side flag, true если сервер говорит, что пользователь уже слушал
/// - onListenComplete: callback(Map<String,dynamic>? rpcResult) вызывается при успешном завершении RPC
class ListenButton extends StatefulWidget {
  final String userId;
  final int? activeSpeechId;
  final String? speechActorId;
  final bool speechActive;
  final bool alreadyListened;
  final Future<void> Function(Map<String, dynamic>? rpcResult)? onListenComplete;

  const ListenButton({
    Key? key,
    required this.userId,
    required this.activeSpeechId,
    required this.speechActorId,
    required this.speechActive,
    this.alreadyListened = false,
    this.onListenComplete,
  }) : super(key: key);

  @override
  State<ListenButton> createState() => _ListenButtonState();
}

class _ListenButtonState extends State<ListenButton> {
  final GameService _svc = GameService();

  bool _sessionListened = false; // пометка в рамках сессии
  bool _loading = false;

  static const int _fixedN = 100; // фиксированное n по ТЗ

  bool get _isEnabled {
  // Кнопка активна, если есть активная речь (life_speeches)
  if (widget.activeSpeechId == null) return false;

  if (_loading) return false;
  if (_sessionListened) return false;
  if (widget.alreadyListened) return false;

  return true;
}

  Future<void> _onPressed() async {
    if (!_isEnabled) return;
    final sid = widget.activeSpeechId!;
    // Показываем запрос с формулировкой по ТЗ
    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Прослушал речь жизни'),
          content: const Text(
              'Вы прослушали речь жизни и она произвела на вас впечатление? Если Да, учтите, ваш цвет изменится!'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Нет')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Да')),
          ],
        );
      },
    );

    if (agree == null) return; // закрыли диалог

    setState(() => _loading = true);

    Map<String, dynamic>? parsed;
    try {
      final res = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);

      // normalize response
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

      // Разобрать результат и показать пользователю соответствующий попап
      if (parsed != null) {
        final status = parsed['status']?.toString() ?? '';
        if (agree && status == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? widget.speechActorId ?? '(неизвестно)';
          final addedM = parsed['added_m'];
          final addedMStr = addedM != null ? addedM.toString() : (2 * _fixedN).toString();
          // Отобразим диалог об изменении цвета
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Цвет изменён'),
              content: Text('Ваш цвет изменён на $newColor. Ваш новый цвет получил майнды: $addedMStr.'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        } else if (!agree && status == 'kept_color') {
          final addedV = parsed['added_v'];
          final addedVStr = addedV != null ? addedV.toString() : _fixedN.toString();
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Спасибо'),
              content: Text('Вы остались верны себе, это достойно!\nВам начислено $addedVStr войсов.'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        } else {
          // Неожиданный, но показываем полный ответ
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Результат'),
              content: Text('Ответ сервера: ${parsed.toString()}'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
            ),
          );
        }
      } else {
        // RPC вернул небинарный ответ — показать уведомление
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Действие выполнено. Пожалуйста, обновите профиль.')));
      }

      // Помечаем клик в сессии только если RPC успешно завершился
      setState(() {
        _sessionListened = true;
      });

      // Вызываем callback родительского экрана для применения изменений в UI и синхронизации
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (_) {
          // игнорируем ошибки callback
        }
      }
    } catch (e) {
      // Ошибка RPC — показываем snackbar; не помечаем как прослушанное
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
        child: _loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      ),
    );
  }
}
