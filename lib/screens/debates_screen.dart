// lib/screens/debates_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/game_service.dart';

class DebatesScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserRole;
  const DebatesScreen({required this.currentUserId, required this.currentUserRole, Key? key}) : super(key: key);

  @override
  State<DebatesScreen> createState() => _DebatesScreenState();
}

class _DebatesScreenState extends State<DebatesScreen> {
  final GameService _service = GameService();
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
    // пока заглушка — можно вызвать загрузку из _service
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

  bool _loading = false;
  Map<String, dynamic>? _activeDebate;
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    try {
      _activeDebate = await _service.getActiveDebate();
      final ures = await supabase.from('user_credentials').select('id, first_name, last_name, telegram_username, role');
      if (ures is List) _users = ures.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      // ignore
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _closeDebate() async {
    if (_activeDebate == null) return;
    final id = _activeDebate!['id'] as int?;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _service.rpcCloseDebate(debateId: id);
      await _loadState();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты закрыты')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  // UI — простая панель
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Дебаты (админ)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_activeDebate == null)
            Column(children: [
              const Text('Активные дебаты отсутствуют'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _loadState, child: const Text('Обновить')),
            ])
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Дебаты: ${_activeDebate!['title'] ?? '-'}'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _closeDebate, child: const Text('Завершить дебаты')),
            ]),
        ]),
      ),
    );
  }
}

/// User panel — голосование
class DebateUserPanel extends StatefulWidget {
  final String currentUserId;
  const DebateUserPanel({required this.currentUserId, Key? key}) : super(key: key);
  @override
  State<DebateUserPanel> createState() => _DebateUserPanelState();
}

class _DebateUserPanelState extends State<DebateUserPanel> {
  final supabase = Supabase.instance.client;
  final GameService _service = GameService();

  bool _loading = false;
  Map<String, dynamic>? _activeDebate;
  List<Map<String, dynamic>> _options = [];
  bool _alreadyVoted = false;
  int? _selectedOptionId;
  final TextEditingController _voicesCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    try {
      _activeDebate = await _service.getActiveDebate();
      if (_activeDebate != null) {
        final debateId = _activeDebate!['id'] as int?;
        if (debateId != null) {
          final ores = await supabase.from('debate_options').select('*').eq('debate_id', debateId).order('id');
          if (ores is List) _options = ores.map((e) => Map<String, dynamic>.from(e as Map)).toList();

          final voted = await supabase.from('debate_votes').select('id').eq('debate_id', debateId).eq('user_id', widget.currentUserId).limit(1).maybeSingle();
          _alreadyVoted = voted != null;
        }
      } else {
        _options = [];
        _alreadyVoted = false;
      }
    } catch (e) {
      debugPrint('DebateUserPanel load error: $e');
      _activeDebate = null;
      _options = [];
      _alreadyVoted = false;
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _vote() async {
    if (_activeDebate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Активные дебаты отсутствуют')));
      return;
    }
    if (_alreadyVoted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже голосовали')));
      return;
    }
    final voices = int.tryParse(_voicesCtrl.text.trim()) ?? 0;
    if (voices <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректное количество войсов')));
      return;
    }
    if (_selectedOptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите вариант')));
      return;
    }

    try {
      final debateId = _activeDebate!['id'] as int;
      await _service.rpcVoteInDebate(debateId: debateId, userId: widget.currentUserId, optionId: _selectedOptionId!, voices: voices);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие в дебатах'),
          content: const Text('Ваш голос принят'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК')),
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
    if (_activeDebate == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const Text('Дебаты (пользователь)'),
            const SizedBox(height: 8),
            const Text('В данный момент активные дебаты отсутствуют'),
            ElevatedButton(onPressed: _loadState, child: const Text('Обновить')),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Дебаты: ${_activeDebate!['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Выберите цвет (вариант):'),
          ..._options.map((o) {
            final id = o['id'] as int;
            final color = (o['color'] ?? '').toString();
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
        ]),
      ),
    );
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
