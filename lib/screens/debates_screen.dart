import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/game_service.dart';

class DebatesScreen extends StatefulWidget {
  final String currentUserId;
  final GameService service;

  const DebatesScreen({
    Key? key,
    required this.currentUserId,
    required this.service,
  }) : super(key: key);

  @override
  State<DebatesScreen> createState() => _DebatesScreenState();
}

class _DebatesScreenState extends State<DebatesScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _debates = [];

  int? _selectedDebateIndex;
  int? _selectedOptionId;
  final TextEditingController _voicesCtrl = TextEditingController();
  final Map<int, bool> _alreadyVotedForDebate = {}; // debateId -> bool

  @override
  void initState() {
    super.initState();
    _loadActiveDebates();
  }

  @override
  void dispose() {
    _voicesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActiveDebates() async {
    setState(() {
      _loading = true;
      _error = null;
      _debates = [];
      _selectedDebateIndex = null;
      _selectedOptionId = null;
      _alreadyVotedForDebate.clear();
    });

    try {
      // 1) load active debates (returns List or throws)
      final debatesRaw = await _supabase
          .from('debates')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false);

      if (debatesRaw == null) {
        throw 'Не удалось загрузить дебаты';
      }

      final debatesList = (debatesRaw is List) ? debatesRaw.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];

      // 2) load options for these debates
      final debateIds = debatesList.map((d) => d['id']).where((e) => e != null).toList();

      List<Map<String, dynamic>> options = [];
      if (debateIds.isNotEmpty) {
        final inArg = '(${debateIds.join(',')})';
        final optsRaw = await _supabase
            .from('debate_options')
            .select()
            .filter('debate_id', 'in', inArg)
            .order('id', ascending: true);

        if (optsRaw != null && optsRaw is List) {
          options = optsRaw.cast<Map<String, dynamic>>();
        } else {
          options = <Map<String, dynamic>>[];
        }
      }

      // 3) assemble debates with options
      final assembled = debatesList.map((d) {
        final dId = d['id'];
        final opts = options.where((o) => o['debate_id'] == dId).toList();
        return {...d, 'options': opts};
      }).toList();

      // 4) check if current user already voted in these debates
      if (debateIds.isNotEmpty) {
        final votesRaw = await _supabase
            .from('debate_votes')
            .select('debate_id')
            .eq('user_id', widget.currentUserId);

        final votesList = (votesRaw is List) ? votesRaw.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];

        for (final d in assembled) {
          final id = d['id'] as int;
          _alreadyVotedForDebate[id] = votesList.any((v) => v['debate_id'] == id);
        }
      }

      setState(() {
        _debates = assembled.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _vote() async {
    if (_selectedDebateIndex == null) return;
    final debate = _debates[_selectedDebateIndex!];
    final debateId = debate['id'] as int;

    if (_alreadyVotedForDebate[debateId] == true) {
      _showSnack('Вы уже голосовали в этих дебатах');
      return;
    }

    final voices = int.tryParse(_voicesCtrl.text.trim());
    if (voices == null || voices <= 0) {
      _showSnack('Введите количество войсов > 0');
      return;
    }

    if (_selectedOptionId == null) {
      _showSnack('Выберите вариант');
      return;
    }

    try {
      // fetch fresh profile (role + v_balance)
      final profileRaw = await _supabase
          .from('user_credentials')
          .select('role, v_balance')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      final profile = (profileRaw is Map<String, dynamic>) ? profileRaw : null;
      if (profile == null) throw 'Не удалось загрузить профиль';

      final role = (profile['role'] ?? '').toString();
      final vBalRaw = profile['v_balance'];
      final vBal = (vBalRaw is num) ? vBalRaw.toInt() : int.tryParse((vBalRaw ?? '0').toString()) ?? 0;

      if (role == 'politician') {
        _showSnack('Политики не могут голосовать в дебатах');
        return;
      }

      if (voices > vBal) {
        _showSnack('Недостаточно войсов на балансе (у вас $vBal)');
        return;
      }

      // Call GameService RPC (should be implemented to call supabase RPC)
      await widget.service.rpcVoteInDebate(
        debateId: debateId,
        userId: widget.currentUserId,
        optionId: _selectedOptionId!,
        voices: voices,
      );

      // mark locally
      setState(() {
        _alreadyVotedForDebate[debateId] = true;
      });

      // thank you dialog
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие в дебатах'),
          content: const Text('Ваш голос принят'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
        ),
      );

      await _loadActiveDebates();
    } catch (e) {
      _showSnack('Ошибка: $e');
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildDebateCard(Map<String, dynamic> debate, int index) {
    final debId = debate['id'] as int;
    final title = debate['title'] ?? 'Дебаты #$debId';
    final description = debate['description'] ?? '';
    final options = (debate['options'] as List).cast<Map<String, dynamic>>();
    final alreadyVoted = _alreadyVotedForDebate[debId] ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                if (alreadyVoted) const Chip(label: Text('Вы голосовали'))
              ],
            ),
            if ((description as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description.toString()),
            ],
            const SizedBox(height: 12),
            Column(
              children: options.map((opt) {
                final optId = opt['id'] as int;
                final optLabel = opt['label'] ?? 'Вариант';
                final color = opt['color'] ?? 'unknown';
                return RadioListTile<int>(
                  value: optId,
                  groupValue: (_selectedDebateIndex == index) ? _selectedOptionId : null,
                  onChanged: alreadyVoted
                      ? null
                      : (v) {
                          setState(() {
                            _selectedDebateIndex = index;
                            _selectedOptionId = v;
                          });
                        },
                  title: Text(optLabel.toString()),
                  subtitle: Text('Цвет: $color'),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _voicesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Количество войсов', border: OutlineInputBorder()),
                    enabled: !alreadyVoted,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: alreadyVoted ? null : _vote,
                  child: const Text('Проголосовать'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дебаты'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadActiveDebates, tooltip: 'Обновить')
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : _debates.isEmpty
                  ? const Center(child: Text('Нет активных дебатов'))
                  : RefreshIndicator(
                      onRefresh: _loadActiveDebates,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24, top: 12),
                        itemCount: _debates.length,
                        itemBuilder: (context, i) => _buildDebateCard(_debates[i], i),
                      ),
                    ),
    );
  }
}
