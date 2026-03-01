import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class MoviePollAdminScreen extends StatefulWidget {
  const MoviePollAdminScreen({Key? key}) : super(key: key);

  @override
  State<MoviePollAdminScreen> createState() => _MoviePollAdminScreenState();
}

class _MoviePollAdminScreenState extends State<MoviePollAdminScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController _titleCtrl = TextEditingController(
    text: 'Голосование за фильм',
  );
  final List<TextEditingController> _optionCtrls = [];
  bool _creating = false;
  bool _closing = false;
  Map<String, dynamic>? _activePoll;
  List<Map<String, dynamic>> _options = [];
  Map<int, int> _optionTotals = {};
  bool _loading = false;
  RealtimeChannel? _pollChannel;
  Timer? _pollReloadDebounce;

  @override
  void initState() {
    super.initState();
    _optionCtrls.addAll(List.generate(3, (_) => TextEditingController()));
    _loadActivePoll();
    _subscribeToPollRealtime();
  }

  @override
  void dispose() {
    _pollReloadDebounce?.cancel();
    final channel = _pollChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    _titleCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOptionField() {
    if (_optionCtrls.length >= 5) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOptionField(int idx) {
    if (idx < 0 || idx >= _optionCtrls.length) return;
    _optionCtrls[idx].dispose();
    setState(() => _optionCtrls.removeAt(idx));
  }

  void _schedulePollRefresh() {
    _pollReloadDebounce?.cancel();
    _pollReloadDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      await _loadActivePoll();
    });
  }

  void _subscribeToPollRealtime() {
    try {
      _pollChannel = supabase.channel('admin-movie-poll-live');
      _pollChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'movie_polls',
            callback: (_) => _schedulePollRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'movie_poll_options',
            callback: (_) => _schedulePollRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'movie_poll_votes',
            callback: (_) => _schedulePollRefresh(),
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _loadActivePoll() async {
    setState(() {
      _loading = true;
      _activePoll = null;
      _options = [];
      _optionTotals = {};
    });
    try {
      final pollRow = await supabase
          .from('movie_polls')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (pollRow is Map<String, dynamic>) {
        setState(() => _activePoll = Map<String, dynamic>.from(pollRow));
        final pollId = _activePoll!['id'];
        final opts = await supabase
            .from('movie_poll_options')
            .select()
            .eq('poll_id', pollId)
            .order('position');
        if (opts is List) {
          _options =
              opts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        for (final opt in _options) {
          final oid = (opt['id'] is int)
              ? opt['id'] as int
              : int.parse(opt['id'].toString());
          final votes =
              await supabase.from('movie_poll_votes').select('votes').eq('option_id', oid);
          int sum = 0;
          if (votes is List) {
            for (final r in votes) {
              final m = Map<String, dynamic>.from(r as Map);
              final v = m['votes'];
              if (v is int) sum += v;
              else if (v is String) sum += int.tryParse(v) ?? 0;
              else if (v is num) sum += v.toInt();
            }
          }
          _optionTotals[oid] = sum;
        }
      } else {
        setState(() {
          _activePoll = null;
          _options = [];
          _optionTotals = {};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
      setState(() {
        _activePoll = null;
        _options = [];
        _optionTotals = {};
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPoll() async {
    if (_creating) return;

    final title = _titleCtrl.text.trim();
    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы один фильм (вариант)')),
      );
      return;
    }
    if (options.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Максимум 5 вариантов')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final existing = await supabase
          .from('movie_polls')
          .select('id')
          .eq('is_closed', false)
          .limit(1)
          .maybeSingle();
      if (existing != null) {
        throw Exception(
            'Уже есть активное голосование. Закройте его перед созданием нового.');
      }

      final pollRow = {
        'title': title.isEmpty ? 'Голосование за фильм' : title,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };

      final insertRes = await supabase
          .from('movie_polls')
          .insert(pollRow)
          .select()
          .maybeSingle();
      if (insertRes == null || insertRes['id'] == null) {
        throw Exception('Не удалось создать запись голосования');
      }

      final int pollId = (insertRes['id'] is int)
          ? insertRes['id'] as int
          : int.parse(insertRes['id'].toString());

      final List<Map<String, dynamic>> optRows = [];
      for (var i = 0; i < options.length; i++) {
        optRows.add({
          'poll_id': pollId,
          'label': options[i],
          'position': i,
        });
      }
      await supabase.from('movie_poll_options').insert(optRows);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Голосование создано')),
        );
      }
      _titleCtrl.text = 'Голосование за фильм';
      for (final c in _optionCtrls) c.clear();
      while (_optionCtrls.length > 3) {
        _optionCtrls.removeLast().dispose();
      }
      await _loadActivePoll();
    } catch (e) {
      final msg = e is Exception ? e.toString() : 'Ошибка: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _closePoll() async {
    if (_closing) return;
    if (_activePoll == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет активного голосования')),
        );
      }
      return;
    }
    setState(() => _closing = true);
    try {
      final pollId = (_activePoll!['id'] is int)
          ? _activePoll!['id'] as int
          : int.parse(_activePoll!['id'].toString());
      await supabase.from('movie_polls').update({
        'is_closed': true,
        'closed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', pollId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Голосование закрыто')),
        );
      }
      await _loadActivePoll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при закрытии: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Widget _buildCreateCard() {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: TitanicTheme.raptureGold.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Создать голосование за фильм',
              style: TitanicTheme.titleLarge.copyWith(
                fontSize: isSmall ? 18 : 20,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'Заголовок (опционально)',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Варианты (максимум 5):',
              style: TitanicTheme.subtitle,
            ),
            const SizedBox(height: 12),
            ..._optionCtrls.asMap().entries.map((e) {
              final idx = e.key;
              final ctrl = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        decoration: TitanicTheme.inputDecoration.copyWith(
                          labelText: 'Фильм #${idx + 1}',
                        ),
                      ),
                    ),
                    if (_optionCtrls.length > 1)
                      IconButton(
                        onPressed: () => _removeOptionField(idx),
                        icon: const Icon(Icons.delete_outline),
                        color: TitanicTheme.copperDetail,
                        iconSize: isSmall ? 22 : 26,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ArtDecoButton(
                  text: 'Добавить вариант',
                  icon: Icons.add,
                  onPressed: _optionCtrls.length >= 5 ? null : _addOptionField,
                  primary: false,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ArtDecoButton(
                  text: 'Создать голосование',
                  onPressed: _creating ? null : _createPoll,
                  loading: _creating,
                  primary: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCard() {
    final isSmall = MediaQuery.of(context).size.width < 380;

    if (_activePoll == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isSmall ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Текущее состояние',
                style: TitanicTheme.titleLarge.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Нет активного голосования',
                style: TitanicTheme.body,
              ),
            ],
          ),
        ),
      );
    }

    final title = _activePoll?['title'] ?? '—';
    final created = _activePoll?['created_at'] ?? '—';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Активное голосование: $title',
              style: TitanicTheme.titleLarge.copyWith(
                fontSize: isSmall ? 16 : 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Создано: $created',
              style: TitanicTheme.body,
            ),
            const SizedBox(height: 12),
            Text(
              'Результаты (сумма голосов по вариантам):',
              style: TitanicTheme.subtitle,
            ),
            const SizedBox(height: 12),
            if (_options.isEmpty)
              Text(
                'Варианты не найдены',
                style: TitanicTheme.body,
              )
            else
              ..._options.map((opt) {
                final oid = (opt['id'] is int)
                    ? opt['id'] as int
                    : int.parse(opt['id'].toString());
                final label = opt['label'] ?? '';
                final total = _optionTotals[oid] ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          label.toString(),
                          style: TitanicTheme.body,
                        ),
                      ),
                      Text(
                        total.toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: TitanicTheme.raptureGold,
                          fontSize: isSmall ? 14 : 15,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Scaffold(
      backgroundColor: TitanicTheme.abyssalBlue,
      appBar: AppBar(
        title: Text(
          'Голосование за фильм',
          style: TitanicTheme.heading.copyWith(fontSize: isSmall ? 18 : 20),
        ),
        backgroundColor: TitanicTheme.abyssalBlue.withOpacity(0.95),
        elevation: 0,
        iconTheme: TitanicTheme.iconTheme,
        actions: [
          ArtDecoIconButton(
            icon: Icons.refresh,
            onPressed: _loadActivePoll,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmall ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCreateCard(),
                  const SizedBox(height: 16),
                  _buildActiveCard(),
                  ArtDecoButton(
                  text: 'Закрыть активное',
                  onPressed: (_activePoll != null && !_closing)
                      ? _closePoll
                      : null,
                  loading: _closing,
                  primary: false,
                  customColor: Colors.redAccent,
                ),
                ],
              ),
            ),
    );
  }
}
