// lib/screens/political_decisions_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';

class PoliticalDecisionsScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserRole;
  const PoliticalDecisionsScreen({required this.currentUserId, required this.currentUserRole, Key? key}) : super(key: key);

  @override
  State<PoliticalDecisionsScreen> createState() => _PoliticalDecisionsScreenState();
}

class _PoliticalDecisionsScreenState extends State<PoliticalDecisionsScreen> {
  final supabase = Supabase.instance.client;
  final _service = GameService();
  List<Map<String, dynamic>> _decisions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDecisions();
  }

  Future<void> _loadDecisions() async {
    setState(() => _loading = true);
    try {
      final res = await supabase.from('political_decisions').select('id, title, description, color, is_active, created_at').order('created_at', ascending: false);
      if (res is List) _decisions = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      _decisions = [];
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _closeDecision(int id) async {
    try {
      await _service.rpcCloseDebate(debateId: id); // reuse close RPC if logic similar; if different replace with rpcClosePoliticalDecision
      // if your DB uses close_political_decision RPC, call supabase.rpc('close_political_decision', params:{'p_decision_id': id})
      await supabase.rpc('close_political_decision', params: {'p_decision_id': id});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Политрешение закрыто')));
      await _loadDecisions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _openPlaceBid(Map<String, dynamic> decision) async {
    final controller = TextEditingController();
    final amount = await showDialog<num?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Сделать ставку'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Сумма M')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final val = num.tryParse(controller.text.trim());
              Navigator.of(context).pop(val);
            },
            child: const Text('Ставка'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    try {
      await _service.rpcPlacePoliticalBid(decisionId: decision['id'] as int, politicianId: widget.currentUserId, amount: amount);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ставка принята')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Политрешения')),
      body: RefreshIndicator(
        onRefresh: _loadDecisions,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (widget.currentUserRole == 'admin') _AdminCreateDecision(onCreated: _loadDecisions),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          ..._decisions.map((d) => Card(
            child: ListTile(
              title: Text(d['title'] ?? ''),
              subtitle: Text('active: ${d['is_active'] ?? true}'),
              trailing: widget.currentUserRole == 'admin'
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.flag), onPressed: d['is_active'] == true ? () => _closeDecision(d['id']) : null),
                    ])
                  : null,
              onTap: widget.currentUserRole == 'politician' ? () => _openPlaceBid(d) : null,
            ),
          )).toList(),
        ]),
      ),
    );
  }
}

class _AdminCreateDecision extends StatefulWidget {
  final VoidCallback onCreated;
  const _AdminCreateDecision({required this.onCreated, Key? key}) : super(key: key);
  @override
  State<_AdminCreateDecision> createState() => _AdminCreateDecisionState();
}

class _AdminCreateDecisionState extends State<_AdminCreateDecision> {
  final supabase = Supabase.instance.client;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _color = TextEditingController(text: '#AAAAAA');
  bool _creating = false;

  Future<void> _create() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите заголовок')));
      return;
    }
    setState(() => _creating = true);
    try {
      await supabase.from('political_decisions').insert({
        'title': t,
        'description': _desc.text.trim(),
        'color': _color.text.trim(),
        'is_active': true,
      });
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Политрешение создано')));
      _title.clear();
      _desc.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Создать политрешение', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      TextField(controller: _title, decoration: const InputDecoration(labelText: 'Заголовок')),
      const SizedBox(height: 8),
      TextField(controller: _desc, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Описание')),
      const SizedBox(height: 8),
      TextField(controller: _color, decoration: const InputDecoration(labelText: 'Цвет (hex)')),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _creating ? null : _create, child: _creating ? const CircularProgressIndicator() : const Text('Создать')),
    ])));
  }
}
