// lib/blocks/generic_blocks.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EconomistBlock extends StatelessWidget {
  final VoidCallback? onAnalytics;
  const EconomistBlock({super.key, this.onAnalytics});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onAnalytics, child: const Text('Аналитика / Ставки'));
}

class HollywoodBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const HollywoodBlock({super.key, this.onOpen});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onOpen, child: const Text('Контент / Ставки'));
}

class MafiaBlock extends StatelessWidget {
  final VoidCallback? onManage;
  const MafiaBlock({super.key, this.onManage});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onManage, child: const Text('Управление предприятиями'));
}

class PublicFigureBlock extends StatelessWidget {
  final VoidCallback? onOpen;
  const PublicFigureBlock({super.key, this.onOpen});
  @override
  Widget build(BuildContext context) => ElevatedButton(onPressed: onOpen, child: const Text('События / Прослушал'));
}

class AdminBlock extends StatelessWidget {
  final Future<void> Function()? onRefresh;
  final void Function(String label)? onAction;
  const AdminBlock({super.key, this.onRefresh, this.onAction});

  void _call(String label) {
    if (onAction != null) onAction!(label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ElevatedButton(onPressed: () => _call('Админ-панель'), style: ElevatedButton.styleFrom(backgroundColor: Colors.black87), child: const Text('Админ-панель')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Пополнить V/M'), child: const Text('Пополнить V/M')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Создать опрос'), child: const Text('Создать опрос')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Создать аукцион'), child: const Text('Создать аукцион')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => _call('Статистика цветов'), child: const Text('Статистика цветов')),
    ]);
  }
}

/// Виджет: кнопка «Я посмотрел фильм и изменился»
///
/// - Доступна для каждого пользователя ровно один раз (флаг в БД: used_watched_movie).
/// - Показывает диалог: «Сменить цвет?»
///   - Если "Нет": закрывает диалог и возвращает на главный экран (popUntil(isFirst)).
///   - Если "Да": показывает выбор цвета (красный, зелёный, жёлтый, синий, малиновый) + подтверждение.
///     После подтверждения обновляет поле `color` у пользователя и устанавливает `used_watched_movie = true`.
///
/// Примечания по совместимости:
/// - Предполагается таблица `user_credentials` с колонками `id`, `color` и `used_watched_movie` (boolean/text).
/// - Значение `color` записывается как метка цвета ('красный', 'зелёный', ...), чтобы соответствовать остальной логике приложения.
class WatchedMovieBlock extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onChanged; // callback после успешного изменения (опционально)

  const WatchedMovieBlock({super.key, required this.currentUserId, this.onChanged});

  @override
  State<WatchedMovieBlock> createState() => _WatchedMovieBlockState();
}

class _WatchedMovieBlockState extends State<WatchedMovieBlock> {
  final supabase = Supabase.instance.client;
  bool _loading = false;
  bool _usedAlready = false;
  String? _currentColor;

  static const List<String> _colorLabels = [
    'красный',
    'зелёный',
    'жёлтый',
    'синий',
    'малиновый',
  ];

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    if (widget.currentUserId.isEmpty) {
      setState(() {
        _usedAlready = true;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final row = await supabase
          .from('user_credentials')
          .select('color, used_watched_movie')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      if (row is Map<String, dynamic>) {
        final usedFlag = row['used_watched_movie'];
        final bool used = (usedFlag == true) || (usedFlag?.toString().toLowerCase() == 'true');
        final color = row['color']?.toString();
        setState(() {
          _usedAlready = used;
          _currentColor = color;
        });
      } else {
        // no row -> disable button to be safe
        setState(() {
          _usedAlready = true;
          _currentColor = null;
        });
      }
    } catch (e) {
      // on error, disable button to avoid accidental repeats
      debugPrint('WatchedMovieBlock._loadState error: $e');
      setState(() {
        _usedAlready = true;
        _currentColor = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPressed() async {
    if (_usedAlready || _loading) return;

    final change = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сменить цвет?'),
        content: const Text('Вы действительно хотите сменить цвет профиля после просмотра фильма?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Нет')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Да')),
        ],
      ),
    );

    if (change != true) {
      // Пользователь выбрал "Нет" — закрываем диалог и возвращаемся на главный экран (попUntil первый маршрут)
      try {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (_) {}
      return;
    }

    // Пользователь выбрал "Да" — показываем выбор цвета
    final selected = await _showColorPickerDialog();
    if (selected == null) return;

    // Подтверждение
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердите смену цвета'),
        content: Text('Вы выбрали: $selected\nЭто действие однократно и не может быть отменено.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Подтвердить')),
        ],
      ),
    );

    if (confirmed != true) return;

    // Выполняем обновление в БД
    setState(() => _loading = true);
    try {
      final upd = await supabase.from('user_credentials').update({
        'color': selected,
        'used_watched_movie': true,
      }).eq('id', widget.currentUserId).select().maybeSingle();

      // Успех — обновляем локальный стейт и вызываем callback
      setState(() {
        _usedAlready = true;
        _currentColor = selected;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Цвет профиля обновлён: $selected')));
      }

      if (widget.onChanged != null) {
        try {
          await widget.onChanged!();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('WatchedMovieBlock: error updating user color: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при сохранении: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showColorPickerDialog() async {
    String? selected = _colorLabels.first;
    return await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          return AlertDialog(
            title: const Text('Выберите цвет'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _colorLabels.map((lbl) {
                  return RadioListTile<String>(
                    title: Text(lbl),
                    value: lbl,
                    groupValue: selected,
                    onChanged: (v) => setStateDialog(() => selected = v),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(selected), child: const Text('Выбрать')),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_loading || _usedAlready) ? null : _onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: _usedAlready ? Colors.grey : Colors.teal),
        child: _loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_usedAlready ? 'Я посмотрел фильм — уже использовано' : 'Я посмотрел фильм и изменился'),
      ),
    );
  }
}
