// lib/blocks/watched_movie_block.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class WatchedMovieBlock extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onChanged;

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
        setState(() {
          _usedAlready = true;
          _currentColor = null;
        });
      }
    } catch (e) {
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
      try {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (_) {}
      return;
    }

    final selected = await _showColorPickerDialog();
    if (selected == null) return;

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

    setState(() => _loading = true);
    try {
      final upd = await supabase.from('user_credentials').update({
        'color': selected,
        'used_watched_movie': true,
      }).eq('id', widget.currentUserId).select().maybeSingle();

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
      child: ArtDecoButton(
        text: _loading ? 'Загрузка...' : (_usedAlready ? 'Я посмотрел фильм — уже использовано' : 'Я посмотрел фильм и изменился'),
        onPressed: (_loading || _usedAlready) ? null : _onPressed,
        loading: _loading,
        primary: !_usedAlready,
      ),
    );
  }
}