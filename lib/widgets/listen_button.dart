// lib/widgets/listen_button.dart
//
// Виджет кнопки "Прослушал речь жизни" — полностью автономный.
// Условия активации:
//  - активна, если передан activeSpeechId (int) и пользователь ещё не слушал (по серверному флагу или в сессии).
// Поведение при нажатии:
//  - показавает диалог с вопросом и кнопками "Да"/"Нет" (формулировка по ТЗ).
//  - при "Да" вызывает RPC listen_speech(p_agree = true, p_n = 100) и показывает результат.
//    RPC должен менять color_banks и присваивать новый цвет пользователю на сервере.
//  - при "Нет" вызывает RPC listen_speech(p_agree = false, p_n = 100) и показывает результат.
//  - помечает как прослушанное в сессии только после успешного RPC.
//  - вызывает onListenComplete(parsedResult) для того, чтобы родитель обновил UI/профиль.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:titanic/services/game_service.dart';

typedef ListenCompleteCallback = Future<void> Function(Map<String, dynamic>? rpcResult);

class ListenButton extends StatefulWidget {
  /// UUID пользователя (строка)
  final String userId;

  /// id активной записи из life_speeches. Если null -> кнопка неактивна.
  final int? activeSpeechId;

  /// id пользователя-политика, произнесящего речь (опционально, используется для подсказок/логики).
  final String? speechActorId;

  /// Флаг: сервер говорит, что пользователь уже слушал эту речь.
  final bool alreadyListened;

  /// Callback, вызываемый после успешного выполнения RPC (передаётся распарсенный Map или null).
  final ListenCompleteCallback? onListenComplete;

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

  // Флаг, что пользователь уже нажимал в этой сессии (локально).
  bool _sessionListened = false;

  // Загрузка при выполнении RPC.
  bool _loading = false;

  // Жёстко зафиксированное n по ТЗ.
  static const int _fixedN = 100;

  bool get _isEnabled {
    // активна при наличии activeSpeechId и если ещё не слушал
    if (widget.activeSpeechId == null) return false;
    if (_loading) return false;
    if (_sessionListened) return false;
    if (widget.alreadyListened) return false;
    return true;
  }

  Future<void> _handlePress() async {
    if (!_isEnabled) return;
    final sid = widget.activeSpeechId!;
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

    if (agree == null) return; // закрыл диалог — ничего не делаем

    setState(() => _loading = true);

    Map<String, dynamic>? parsed;
    try {
      final res = await _svc.rpcListenSpeech(speechId: sid, userId: widget.userId, agree: agree, n: _fixedN);

      // Нормализуем ответ в Map, если возможно
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

      // Показываем пользователю результат в понятной форме
      if (agree) {
        // Да — ожидаем changed_color
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
          // Некорректный/неожиданный ответ — показать сырое сообщение
          final text = parsed != null ? parsed.toString() : 'Действие выполнено.';
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
        // Нет — ожидаем kept_color
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
          final text = parsed != null ? parsed.toString() : 'Действие выполнено.';
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

      // Отмечаем в сессии только при успешном выполнении
      setState(() => _sessionListened = true);

      // Сообщаем родителю распарсенный результат, чтобы он обновил профиль/цвет локально и синхронизировал
      if (widget.onListenComplete != null) {
        try {
          await widget.onListenComplete!(parsed);
        } catch (_) {
          // ignore callback errors
        }
      } else {
        // если callback не задан — краткое уведомление
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Прослушивание зафиксировано.')));
      }
    } catch (e) {
      // Ошибка выполнения RPC — показываем и не помечаем как прослушанное
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
