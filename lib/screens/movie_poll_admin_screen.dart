// lib/screens/movie_poll_admin_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MoviePollAdminScreen extends StatefulWidget {
  const MoviePollAdminScreen({Key? key}) : super(key: key);

  @override
  State<MoviePollAdminScreen> createState() => _MoviePollAdminScreenState();
}

class _MoviePollAdminScreenState extends State<MoviePollAdminScreen> {
  final supabase = Supabase.instance.client;

  // form
  final TextEditingController _titleCtrl = TextEditingController(text: 'Голосование за фильм');
  final List<TextEditingController> _optionCtrls = [];
  bool _creating = false;
  bool _closing = false;
  Map<String, dynamic>? _activePoll;
  List<Map<String, dynamic>> _options = [];
  Map<int, int> _optionTotals = {}; // option_id -> total votes
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _optionCtrls.addAll(List.generate(3, (_) => TextEditingController()));
    _loadActivePoll();
  }

  @override
  void dispose() {
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
        // load options
        final opts = await supabase.from('movie_poll_options').select().eq('poll_id', pollId).order('position');
        if (opts is List) {
          _options = opts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        // aggregate totals per option (client-side)
        for (final opt in _options) {
          final oid = (opt['id'] is int) ? opt['id'] as int : int.parse(opt['id'].toString());
          final votes = await supabase.from('movie_poll_votes').select('votes').eq('option_id', oid);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
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
    final options = _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавьте хотя бы один фильм (вариант)')));
      return;
    }
    if (options.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Максимум 5 вариантов')));
      return;
    }

    setState(() => _creating = true);
    try {
      // ensure no active poll
      final existing = await supabase.from('movie_polls').select('id').eq('is_closed', false).limit(1).maybeSingle();
      if (existing != null) {
        throw Exception('Уже есть активное голосование. Закройте его перед созданием нового.');
      }

      final pollRow = {
        'title': title.isEmpty ? 'Голосование за фильм' : title,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };

      final insertRes = await supabase.from('movie_polls').insert(pollRow).select().maybeSingle();
      if (insertRes == null || insertRes['id'] == null) throw Exception('Не удалось создать запись голосования');

      final int pollId = (insertRes['id'] is int) ? insertRes['id'] as int : int.parse(insertRes['id'].toString());

      // insert options with positions
      final List<Map<String, dynamic>> optRows = [];
      for (var i = 0; i < options.length; i++) {
        optRows.add({'poll_id': pollId, 'label': options[i], 'position': i});
      }
      await supabase.from('movie_poll_options').insert(optRows);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Голосование создано')));
      // clear fields
      _titleCtrl.text = 'Голосование за фильм';
      for (final c in _optionCtrls) c.clear();
      while (_optionCtrls.length > 3) {
        _optionCtrls.removeLast().dispose();
      }
      await _loadActivePoll();
    } catch (e) {
      final msg = e is Exception ? e.toString() : 'Ошибка: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _closePoll() async {
    if (_closing) return;
    if (_activePoll == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет активного голосования')));
      return;
    }
    setState(() => _closing = true);
    try {
      final pollId = (_activePoll!['id'] is int) ? _activePoll!['id'] as int : int.parse(_activePoll!['id'].toString());
      await supabase.from('movie_polls').update({'is_closed': true, 'closed_at': DateTime.now().toUtc().toIso8601String()}).eq('id', pollId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Голосование закрыто')));
      await _loadActivePoll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при закрытии: $e')));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Widget _buildCreateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Создать голосование за фильм', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок (опционально)')),
          const SizedBox(height: 12),
          const Text('Варианты (максимум 5):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._optionCtrls.asMap().entries.map((e) {
            final idx = e.key;
            final ctrl = e.value;
            return Row(children: [
              Expanded(child: TextField(controller: ctrl, decoration: InputDecoration(labelText: 'Фильм #${idx + 1}'))),
              if (idx >= 0 && _optionCtrls.length > 1)
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _removeOptionField(idx)),
            ]);
          }).toList(),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: _optionCtrls.length >= 5 ? null : _addOptionField, child: const Text('Добавить вариант')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton(onPressed: _creating ? null : _createPoll, child: _creating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать голосование')),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: (_activePoll != null && !_closing) ? _closePoll : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: _closing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Закрыть активное'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildActiveCard() {
    if (_activePoll == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Текущее состояние', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('Нет активного голосования'),
          ]),
        ),
      );
    }

    final title = _activePoll?['title'] ?? '—';
    final created = _activePoll?['created_at'] ?? '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Активное голосование: $title', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Создано: $created'),
          const SizedBox(height: 12),
          const Text('Результаты (сумма голосов по вариантам):', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_options.isEmpty)
            const Text('Варианты не найдены')
          else
            ..._options.map((opt) {
              final oid = (opt['id'] is int) ? opt['id'] as int : int.parse(opt['id'].toString());
              final label = opt['label'] ?? '';
              final total = _optionTotals[oid] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text(label.toString())),
                  Text(total.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              );
            }).toList(),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Голосование за фильм'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loadActivePoll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildCreateCard(),
                const SizedBox(height: 12),
                _buildActiveCard(),
              ]),
            ),
    );
  }
}
