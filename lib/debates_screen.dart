// lib/screens/debates_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/game_service.dart';

class DebatesScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserRole;
  const DebatesScreen({required this.currentUserId, required this.currentUserRole, Key? key}) : super(key: key);

  @override
  State<DebatesScreen> createState() => _DebatesScreenState();
}

class _DebatesScreenState extends State<DebatesScreen> {
  final _service = GameService();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Дебаты')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (widget.currentUserRole == 'admin') DebateAdminPanel(currentUserId: widget.currentUserId),
            const SizedBox(height: 12),
            DebateUserPanel(currentUserId: widget.currentUserId),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    setState(() => _loading = false);
  }
}

/// Admin: create debate, set speakers, close debate
class DebateAdminPanel extends StatefulWidget {
  final String currentUserId;
  const DebateAdminPanel({required this.currentUserId, Key? key}) : super(key: key);
  @override
  State<DebateAdminPanel> createState() => _DebateAdminPanelState();
}

class _DebateAdminPanelState extends State<DebateAdminPanel> {
  final supabase = Supabase.instance.client;
  final GameService _service = GameService();

  final _titleCtrl = TextEditingController(text: 'Дебаты');
  final List<String> _colors = ['#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF'];
  final Map<String, String?> _speakerA = {};
  final Map<String, String?> _speakerB = {};
  List<Map<String, dynamic>> _politicians = [];
  bool _creating = false;
  Map<String, dynamic>? _activeDebate;

  @override
  void initState() {
    super.initState();
    _loadPoliticians();
    _loadActiveDebate();
  }

  Future<void> _loadPoliticians() async {
    try {
      final res = await supabase.from('user_credentials').select('id, first_name, last_name').eq('role', 'politician').order('first_name');
      if (res is List) {
        _politicians = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    setState(() {});
  }

  Future<void> _loadActiveDebate() async {
    try {
      final d = await _service.getActiveDebate();
      setState(() {
        _activeDebate = d;
      });
    } catch (_) {}
  }

  Future<void> _createDebate() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите заголовок')));
      return;
    }
    setState(() => _creating = true);
    try {
      final debateRow = {
        'title': title,
        'created_by': widget.currentUserId,
        'is_active': true,
      };
      final created = await supabase.from('debates').insert(debateRow).select().maybeSingle();
      if (created == null) throw 'cannot create debate';
      final debateId = (created as Map)['id'];

      final opts = _colors.map((c) => {'debate_id': debateId, 'color': c}).toList();
      await supabase.from('debate_options').insert(opts);

      for (final c in _colors) {
        final sa = _speakerA[c];
        final sb = _speakerB[c];
        if (sa != null) {
          await supabase.from('debate_speakers').insert({'debate_id': debateId, 'color': c, 'politician_id': sa});
        }
        if (sb != null) {
          await supabase.from('debate_speakers').insert({'debate_id': debateId, 'color': c, 'politician_id': sb});
        }
      }

      await _loadActiveDebate();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты созданы')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания: $e')));
    } finally {
      setState(() => _creating = false);
    }
  }

  Future<void> _closeDebate() async {
    if (_activeDebate == null) return;
    final id = _activeDebate!['id'] as int;
    try {
      await _service.rpcCloseDebate(debateId: id);
      // Optionally refresh
      setState(() => _activeDebate = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты закрыты')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка закрытия: $e')));
    }
  }

  Widget _buildSpeakerPicker(String color, bool isFirst) {
    final mapRef = isFirst ? _speakerA : _speakerB;
    final value = mapRef[color];
    final items = <DropdownMenuItem<String?>>[];
    items.add(const DropdownMenuItem<String?>(value: null, child: Text('- нет -')));
    items.addAll(_politicians.map((p) {
      final name = ((p['first_name'] ?? '') as String).isEmpty ? (p['id']?.toString() ?? '') : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}';
      return DropdownMenuItem<String?>(value: p['id']?.toString(), child: Text(name));
    }).toList());
    return DropdownButton<String?>(
      value: value,
      hint: const Text('- нет -'),
      items: items,
      onChanged: (v) => setState(() => mapRef[color] = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Панель администратора: Дебаты', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок дебатов')),
        const SizedBox(height: 8),
        const Text('Цвета и спикеры (максимум 2 спикера на цвет):'),
        const SizedBox(height: 8),
        ..._colors.map((c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(width: 24, height: 24, decoration: BoxDecoration(color: _parseHexColor(c) ?? Colors.grey, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            Expanded(child: Text(c)),
            const SizedBox(width: 8),
            _buildSpeakerPicker(c, true),
            const SizedBox(width: 8),
            _buildSpeakerPicker(c, false),
          ]),
        )).toList(),
        const SizedBox(height: 12),
        Row(children: [
          ElevatedButton(onPressed: _creating ? null : _createDebate, child: _creating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать дебаты')),
          const SizedBox(width: 12),
          ElevatedButton(onPressed: _activeDebate == null ? null : _closeDebate, child: const Text('Закрыть текущие дебаты')),
        ]),
      ])),
    );
  }

  Color? _parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);
    if (hex.length == 6) hex = 'FF' + hex;
    if (hex.length != 8) return null;
    final intVal = int.tryParse(hex, radix: 16);
    if (intVal == null) return null;
    return Color(intVal);
  }
}

/// Player panel: show active debate and allow vote (everyone except politicians)
class DebateUserPanel extends StatefulWidget {
  final String currentUserId;
  const DebateUserPanel({required this.currentUserId, Key? key}) : super(key: key);
  @override
  State<DebateUserPanel> createState() => _DebateUserPanelState();
}

class _DebateUserPanelState extends State<DebateUserPanel> {
  final supabase = Supabase.instance.client;
  final GameService _service = GameService();

  Map<String, dynamic>? _activeDebate;
  List<Map<String, dynamic>> _options = [];
  bool _loading = false;
  int? _selectedOptionId;
  final _voicesCtrl = TextEditingController(text: '0');
  String? _role;
  bool _alreadyVoted = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    try {
      final prof = await supabase.from('user_credentials').select('role').eq('id', widget.currentUserId).maybeSingle();
      if (prof != null && prof is Map) _role = prof['role'] as String?;
      final d = await _service.getActiveDebate();
      _activeDebate = d;
      if (d != null) {
        _options = await _service.getDebateOptions(d['id'] as int);
        final votes = await supabase.from('debate_votes').select('id').eq('debate_id', d['id']).eq('user_id', widget.currentUserId);
        _alreadyVoted = (votes is List && votes.isNotEmpty);
      } else {
        _options = [];
        _alreadyVoted = false;
      }
    } catch (_) {
      // ignore
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _vote() async {
    if (_activeDebate == null) return;
    if (_role == 'politician') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Политики не могут голосовать в дебатах')));
      return;
    }
    if (_alreadyVoted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже голосовали в текущих дебатах')));
      return;
    }
    final voices = num.tryParse(_voicesCtrl.text.trim());
    if (voices == null || voices <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите количество войсов > 0')));
      return;
    }
    if (_selectedOptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите вариант')));
      return;
    }
    try {
      await _service.rpcVoteInDebate(debateId: _activeDebate!['id'] as int, userId: widget.currentUserId, optionId: _selectedOptionId!, voices: voices);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие в дебатах'),
          content: const Text('Ваш голос принят'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ОК'),
            )
          ],
        ),
      );
      setState(() => _alreadyVoted = true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_activeDebate == null) return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      const Text('Дебаты (пользователь)'), const SizedBox(height: 8), const Text('В данный момент активные дебаты отсутствуют'),
      ElevatedButton(onPressed: _loadState, child: const Text('Обновить')),
    ])));
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Дебаты: ${_activeDebate!['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Выберите цвет (вариант):'),
      ..._options.map((o) {
        final id = o['id'] as int;
        final color = o['color'] as String;
        return RadioListTile<int>(
          value: id,
          groupValue: _selectedOptionId,
          onChanged: _alreadyVoted ? null : (v) => setState(() => _selectedOptionId = v),
          title: Row(children: [
            Container(width: 20, height: 20, decoration: BoxDecoration(color: _parseHexColor(color) ?? Colors.grey, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            Text(color),
          ]),
        );
      }).toList(),
      const SizedBox(height: 8),
      TextField(controller: _voicesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Количество войсов (целое)')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _alreadyVoted ? null : _vote, child: const Text('Проголосовать')),
    ])));
  }

  Color? _parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);
    if (hex.length == 6) hex = 'FF' + hex;
    if (hex.length != 8) return null;
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return null;
    return Color(val);
  }
}
