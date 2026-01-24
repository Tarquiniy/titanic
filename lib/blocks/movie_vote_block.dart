// lib/blocks/movie_vote_block.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Кнопка «Я посмотрел фильм и хочу голосовать»
/// - Показывается всем пользователям, кроме тех, у кого роль содержит 'голливуд' (case-insensitive)
/// - Проверяет наличие активного голосования (movie_polls where is_closed = false)
/// - Проверяет, голосовал ли пользователь в этом голосовании (movie_poll_votes where poll_id = active.id and user_id = currentUserId)
/// - При нажатии показывает форму: чекбоксы + поля ввода количества голосов напротив отмеченных вариантов
/// - При подтверждении: суммарное количество введённых голосов списывается с v_balance (войсов) пользователя.
///   Перед списанием проверяется, что v_balance >= сумме голосов; операция отклоняется, если денег не хватает.
/// - Баланс войсов не может уйти ниже 0.
class MovieVoteBlock extends StatefulWidget {
  final String currentUserId;
  final String? currentUserRole;
  final Future<void> Function()? onVoted; // optional callback for parent to refresh

  const MovieVoteBlock({
    Key? key,
    required this.currentUserId,
    this.currentUserRole,
    this.onVoted,
  }) : super(key: key);

  @override
  State<MovieVoteBlock> createState() => _MovieVoteBlockState();
}

class _MovieVoteBlockState extends State<MovieVoteBlock> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _disabled = true; // final visual disabled
  Map<String, dynamic>? _activePoll;
  List<Map<String, dynamic>> _options = [];

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() {
      _loading = true;
      _disabled = true;
      _activePoll = null;
      _options = [];
    });

    // role block: any role that contains "голливуд" or "hollywood" (case-insensitive) is excluded
    final roleRaw = widget.currentUserRole ?? '';
    final roleStr = roleRaw.toString().toLowerCase().trim();
    if (roleStr.contains('голливуд') || roleStr.contains('hollywood')) {
      setState(() {
        _disabled = true;
        _loading = false;
      });
      return;
    }

    if (widget.currentUserId.isEmpty) {
      setState(() {
        _disabled = true;
        _loading = false;
      });
      return;
    }

    try {
      // load active poll
      final poll = await supabase
          .from('movie_polls')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (poll is Map<String, dynamic>) {
        _activePoll = Map<String, dynamic>.from(poll);
        final pollId = (_activePoll!['id'] is int) ? _activePoll!['id'] as int : int.parse(_activePoll!['id'].toString());

        // load options
        final opts = await supabase.from('movie_poll_options').select().eq('poll_id', pollId).order('position');
        if (opts is List) {
          _options = opts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }

        // check if user already voted for this poll
        final voted = await supabase
            .from('movie_poll_votes')
            .select('id')
            .eq('poll_id', pollId)
            .eq('user_id', widget.currentUserId)
            .limit(1)
            .maybeSingle();

        if (voted != null) {
          setState(() {
            _disabled = true;
            _loading = false;
          });
          return;
        } else {
          setState(() {
            _disabled = false;
            _loading = false;
          });
          return;
        }
      } else {
        // no active poll
        setState(() {
          _activePoll = null;
          _options = [];
          _disabled = true;
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('MovieVoteBlock._loadState error: $e');
      setState(() {
        _activePoll = null;
        _options = [];
        _disabled = true;
        _loading = false;
      });
      return;
    }
  }

  Future<void> _onPressed() async {
    if (_disabled || _loading || _activePoll == null || _options.isEmpty) return;

    final result = await _showVoteDialogGetData();
    if (result == null || result.isEmpty) return;

    final int pollId = (_activePoll!['id'] is int) ? _activePoll!['id'] as int : int.parse(_activePoll!['id'].toString());

    // Build inserts and compute totalV (total войсов to deduct)
    final List<Map<String, dynamic>> inserts = [];
    int totalV = 0;
    for (final entry in result.entries) {
      final idx = int.tryParse(entry.key);
      if (idx == null) continue;
      final data = entry.value as Map<String, dynamic>;
      final sel = data['selected'] as bool;
      final votes = data['votes'] as int;
      if (!sel || votes <= 0) continue;
      final opt = _options[idx];
      final optId = (opt['id'] is int) ? opt['id'] as int : int.parse(opt['id'].toString());
      inserts.add({
        'poll_id': pollId,
        'option_id': optId,
        'user_id': widget.currentUserId,
        'votes': votes,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      totalV += votes;
    }

    if (inserts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет выбранных вариантов')));
      return;
    }

    setState(() => _loading = true);

    try {
      // fetch current v_balance
      double currentV = 0.0;
      try {
        final row = await supabase.from('user_credentials').select('v_balance').eq('id', widget.currentUserId).maybeSingle();
        if (row is Map<String, dynamic> && row.containsKey('v_balance')) {
          final vb = row['v_balance'];
          if (vb is num) currentV = vb.toDouble();
          else if (vb is String) currentV = double.tryParse(vb.replaceAll(',', '.')) ?? 0.0;
        }
      } catch (e) {
        debugPrint('MovieVoteBlock: failed to fetch v_balance: $e');
      }

      if (currentV < totalV) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Недостаточно войсов: требуется $totalV, у вас ${currentV.toStringAsFixed(0)}')));
        setState(() => _loading = false);
        return;
      }

      final int needed = totalV;
      final double newV = (currentV - needed).clamp(0, double.infinity);

      // Try atomic-ish update: ensure we only update if v_balance >= needed (race protection)
      final updateRes = await supabase
          .from('user_credentials')
          .update({'v_balance': newV})
          .eq('id', widget.currentUserId)
          .gte('v_balance', needed)
          .select()
          .maybeSingle();

      if (updateRes == null) {
        // race or insufficient funds
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось списать войсы — возможно, недостаточно средств. Попробуйте снова.')));
        setState(() => _loading = false);
        return;
      }

      // Insert votes
      await supabase.from('movie_poll_votes').insert(inserts);

      // feedback
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Спасибо'),
          content: Text('Спасибо за участие в голосовании. Списано войсов: $needed'),
          actions: [
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );

      // navigate back to root (optional, keep as previous behavior)
      if (mounted) {
        try {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } catch (_) {}
      }

      // notify parent
      if (widget.onVoted != null) {
        try {
          await widget.onVoted!();
        } catch (_) {}
      }

      // refresh local state (button becomes disabled for this user)
      await _loadState();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при отправке голосов: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shows dialog and returns map: indexString -> {'selected': bool, 'votes': int}
  Future<Map<String, Map<String, dynamic>>?> _showVoteDialogGetData() async {
    final List<bool> selected = List<bool>.filled(_options.length, false);
    final List<TextEditingController> countCtrls = List.generate(_options.length, (_) => TextEditingController(text: '1'));

    final res = await showDialog<Map<String, Map<String, dynamic>>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          return AlertDialog(
            title: Text(_activePoll?['title']?.toString() ?? 'Голосование за фильм'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Выберите варианты и укажите количество голосов рядом с отмеченными вариантами.'),
                const SizedBox(height: 8),
                ..._options.asMap().entries.map((e) {
                  final idx = e.key;
                  final opt = e.value;
                  final label = (opt['label'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            value: selected[idx],
                            title: Text(label),
                            onChanged: (v) => setStateDialog(() => selected[idx] = v ?? false),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: countCtrls[idx],
                            keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                            decoration: const InputDecoration(labelText: 'Голоса'),
                            enabled: selected[idx],
                            onChanged: (s) {
                              // allow only digits
                              final ns = s.replaceAll(RegExp(r'[^0-9]'), '');
                              if (ns != s) {
                                countCtrls[idx].text = ns;
                                countCtrls[idx].selection = TextSelection.fromPosition(TextPosition(offset: ns.length));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(null), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  final any = selected.any((v) => v);
                  if (!any) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Отметьте хотя бы один вариант')));
                    return;
                  }
                  final Map<String, Map<String, dynamic>> out = {};
                  for (var i = 0; i < selected.length; i++) {
                    final sel = selected[i];
                    final txt = countCtrls[i].text.trim();
                    final parsed = int.tryParse(txt) ?? 0;
                    if (sel && parsed <= 0) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Введите корректное количество голосов (целое > 0)')));
                      return;
                    }
                    out[i.toString()] = {'selected': sel, 'votes': parsed};
                  }
                  Navigator.of(ctx2).pop(out);
                },
                child: const Text('Проголосовать'),
              ),
            ],
          );
        });
      },
    );

    // dispose controllers
    for (final c in countCtrls) {
      try {
        c.dispose();
      } catch (_) {}
    }

    return res;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_loading || _disabled) ? null : _onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: _disabled ? Colors.grey : Colors.teal),
        child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Я посмотрел фильм и хочу голосовать'),
      ),
    );
  }
}
