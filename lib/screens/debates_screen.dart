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

  // ✅ стиль только для заголовка варианта (цвет/название опции)
  static const Color _gold = Color(0xFFD4AF37);

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

  String _formatPoliticianName(Map<String, dynamic>? uc, dynamic fallbackId) {
    if (uc == null) return fallbackId?.toString() ?? '—';

    final fn = (uc['first_name'] ?? '').toString().trim();
    final ln = (uc['last_name'] ?? '').toString().trim();
    final tgRaw = (uc['telegram_username'] ?? '').toString().trim();

    final full = ('$fn $ln').trim();
    if (full.isNotEmpty) return full;

    if (tgRaw.isNotEmpty) {
      final tg = tgRaw.startsWith('@') ? tgRaw : '@$tgRaw';
      return tg;
    }

    return fallbackId?.toString() ?? '—';
  }

  String _speakerLine({
    required String label,
    required Map<String, dynamic>? uc,
    required dynamic politicianId,
  }) {
    final name = _formatPoliticianName(uc, politicianId);
    final color = (uc?['color'] ?? '').toString().trim();
    final colorText = color.isEmpty ? 'цвет не указан' : color;
    return '$label: $name — $colorText';
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
      // 1) load active debates
      final debatesRaw = await _supabase
          .from('debates')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false);

      if (debatesRaw == null) throw 'Не удалось загрузить дебаты';

      final debatesList = (debatesRaw is List)
          ? debatesRaw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      // 2) collect debate ids
      final debateIds =
          debatesList.map((d) => d['id']).where((e) => e != null).toList();

      // 3) load options
      List<Map<String, dynamic>> options = [];
      String? inArg;
      if (debateIds.isNotEmpty) {
        inArg = '(${debateIds.join(',')})';
        final optsRaw = await _supabase
            .from('debate_options')
            .select()
            .filter('debate_id', 'in', inArg)
            .order('id', ascending: true);

        options = (optsRaw is List)
            ? optsRaw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
      }

      // 4) load speakers: option_id -> up to 2 speakers (ordered by debate_speakers.id)
      final Map<int, List<Map<String, dynamic>>> speakersByOptionId = {};

      if (debateIds.isNotEmpty && inArg != null) {
        final speakersRaw = await _supabase
            .from('debate_speakers')
            .select(
              'id, debate_id, option_id, politician_id, '
              'politician:user_credentials!debate_speakers_politician_id_fkey(first_name,last_name,telegram_username,color)',
            )
            .filter('debate_id', 'in', inArg)
            .order('id', ascending: true);

        final speakersList = (speakersRaw is List)
            ? speakersRaw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        for (final s in speakersList) {
          final optIdRaw = s['option_id'];
          final optId = (optIdRaw is int)
              ? optIdRaw
              : int.tryParse(optIdRaw?.toString() ?? '');
          if (optId == null) continue;

          final uc = (s['politician'] is Map)
              ? Map<String, dynamic>.from(s['politician'] as Map)
              : null;
          final politicianId = s['politician_id'];

          final list = speakersByOptionId.putIfAbsent(
            optId,
            () => <Map<String, dynamic>>[],
          );

          // максимум 2 спикера на опцию
          if (list.length >= 2) continue;

          // не добавляем дубликаты одного и того же политика
          if (politicianId != null &&
              list.any((e) =>
                  (e['_politician_id']?.toString() ?? '') ==
                  politicianId.toString())) {
            continue;
          }

          list.add({
            '_politician_id': politicianId,
            'uc': uc,
          });
        }
      }

      // 5) assemble debates with options (+ speaker_lines)
      final assembled = debatesList.map((d) {
        final dId = d['id'];

        final opts = options.where((o) => o['debate_id'] == dId).map((o) {
          final optIdRaw = o['id'];
          final optId = (optIdRaw is int)
              ? optIdRaw
              : int.tryParse(optIdRaw?.toString() ?? '');

          final speakers = (optId != null)
              ? (speakersByOptionId[optId] ?? <Map<String, dynamic>>[])
              : <Map<String, dynamic>>[];

          final List<String> speakerLines = [];

          // ✅ правило:
          // - 0: "Спикеры отсутствуют"
          // - 1: одна строка
          // - 2: две строки
          if (speakers.isEmpty) {
            // UI покажет "Спикеры отсутствуют"
          } else if (speakers.length == 1) {
            final sp = speakers[0];
            speakerLines.add(
              _speakerLine(
                label: 'Спикер',
                uc: sp['uc'] as Map<String, dynamic>?,
                politicianId: sp['_politician_id'],
              ),
            );
          } else {
            final spA = speakers[0];
            final spB = speakers[1];
            speakerLines.add(
              _speakerLine(
                label: 'Спикер A',
                uc: spA['uc'] as Map<String, dynamic>?,
                politicianId: spA['_politician_id'],
              ),
            );
            speakerLines.add(
              _speakerLine(
                label: 'Спикер B',
                uc: spB['uc'] as Map<String, dynamic>?,
                politicianId: spB['_politician_id'],
              ),
            );
          }

          return {
            ...o,
            'speaker_lines': speakerLines,
          };
        }).toList();

        return {
          ...d,
          'options': opts,
        };
      }).toList();

      // 6) already voted?
      if (debateIds.isNotEmpty) {
        final votesRaw = await _supabase
            .from('debate_votes')
            .select('debate_id')
            .eq('user_id', widget.currentUserId);

        final votesList = (votesRaw is List)
            ? votesRaw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        for (final d in assembled) {
          final id = d['id'] as int;
          _alreadyVotedForDebate[id] =
              votesList.any((v) => v['debate_id'] == id);
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
      final profileRaw = await _supabase
          .from('user_credentials')
          .select('role, v_balance')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      final profile = (profileRaw is Map<String, dynamic>) ? profileRaw : null;
      if (profile == null) throw 'Не удалось загрузить профиль';

      final role = (profile['role'] ?? '').toString();
      final vBalRaw = profile['v_balance'];
      final vBal = (vBalRaw is num)
          ? vBalRaw.toInt()
          : int.tryParse((vBalRaw ?? '0').toString()) ?? 0;

      if (role == 'politician') {
        _showSnack('Политики не могут голосовать в дебатах');
        return;
      }

      if (voices > vBal) {
        _showSnack('Недостаточно войсов на балансе (у вас $vBal)');
        return;
      }

      await widget.service.rpcVoteInDebate(
        debateId: debateId,
        userId: widget.currentUserId,
        optionId: _selectedOptionId!,
        voices: voices,
      );

      setState(() {
        _alreadyVotedForDebate[debateId] = true;
      });

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
                Expanded(
                  child: Text(
                    title.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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

                final speakerLines =
                    (opt['speaker_lines'] as List?)?.map((e) => e.toString()).toList() ??
                        <String>[];

                final speakersText = speakerLines.isEmpty
                    ? 'Спикеры отсутствуют'
                    : speakerLines.join('\n');

                return RadioListTile<int>(
                  value: optId,
                  groupValue:
                      (_selectedDebateIndex == index) ? _selectedOptionId : null,
                  onChanged: alreadyVoted
                      ? null
                      : (v) {
                          setState(() {
                            _selectedDebateIndex = index;
                            _selectedOptionId = v;
                          });
                        },

                  // ✅ ИЗМЕНЕНИЯ ТОЛЬКО ТУТ: заголовок опции (цвет) -> золотой + больше
                  title: Text(
                    optLabel.toString(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _gold,
                    ),
                  ),

                  // остальное НЕ трогаем
                  subtitle: Text(speakersText),
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
                    decoration: const InputDecoration(
                      labelText: 'Количество войсов',
                      border: OutlineInputBorder(),
                    ),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActiveDebates,
            tooltip: 'Обновить',
          )
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
                        itemBuilder: (context, i) =>
                            _buildDebateCard(_debates[i], i),
                      ),
                    ),
    );
  }
}
