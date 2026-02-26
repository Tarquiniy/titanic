import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class MovieVoteBlock extends StatefulWidget {
  final String currentUserId;
  final String? currentUserRole;
  final Future<void> Function()? onVoted;

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
  bool _disabled = true;
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
      final poll = await supabase
          .from('movie_polls')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (poll is Map<String, dynamic>) {
        _activePoll = Map<String, dynamic>.from(poll);
        final pollId = (_activePoll!['id'] is int) 
            ? _activePoll!['id'] as int 
            : int.parse(_activePoll!['id'].toString());

        final opts = await supabase
            .from('movie_poll_options')
            .select()
            .eq('poll_id', pollId)
            .order('position', ascending: true);
        
        if (opts is List) {
          _options = opts.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            ..sort((a, b) {
              final ap = int.tryParse((a['position'] ?? 0).toString()) ?? 0;
              final bp = int.tryParse((b['position'] ?? 0).toString()) ?? 0;
              return ap.compareTo(bp);
            });
        }

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

    final result = await _showVoteDialog();
    if (result == null || result.isEmpty) return;

    final int pollId = (_activePoll!['id'] is int) 
        ? _activePoll!['id'] as int 
        : int.parse(_activePoll!['id'].toString());

    final List<Map<String, dynamic>> inserts = [];
    final List<String> selectedMovieLabels = [];
    int totalV = 0;
    
    for (final entry in result.entries) {
      final idx = int.tryParse(entry.key);
      if (idx == null) continue;
      
      final data = entry.value as Map<String, dynamic>;
      final sel = data['selected'] as bool;
      final votes = data['votes'] as int;
      
      if (!sel || votes <= 0) continue;
      
      final opt = _options[idx];
      final optId = (opt['id'] is int) 
          ? opt['id'] as int 
          : int.parse(opt['id'].toString());
      final label = (opt['label'] ?? '').toString().trim();
      
      inserts.add({
        'poll_id': pollId,
        'option_id': optId,
        'user_id': widget.currentUserId,
        'votes': votes,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (label.isNotEmpty) {
        selectedMovieLabels.add(label);
      }
      totalV += votes;
    }

    if (inserts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет выбранных вариантов'))
        );
      }
      return;
    }

    setState(() => _loading = true);

    try {
      double currentV = 0.0;
      try {
        final row = await supabase
            .from('user_credentials')
            .select('v_balance')
            .eq('id', widget.currentUserId)
            .maybeSingle();
        
        if (row is Map<String, dynamic> && row.containsKey('v_balance')) {
          final vb = row['v_balance'];
          if (vb is num) currentV = vb.toDouble();
          else if (vb is String) {
            currentV = double.tryParse(vb.replaceAll(',', '.')) ?? 0.0;
          }
        }
      } catch (e) {
        debugPrint('MovieVoteBlock: failed to fetch v_balance: $e');
      }

      if (currentV < totalV) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Недостаточно войсов: требуется $totalV, у вас ${currentV.toStringAsFixed(0)}')
            )
          );
        }
        setState(() => _loading = false);
        return;
      }

      final int needed = totalV;
      final double newV = (currentV - needed).clamp(0, double.infinity);

      final updateRes = await supabase
          .from('user_credentials')
          .update({'v_balance': newV})
          .eq('id', widget.currentUserId)
          .gte('v_balance', needed)
          .select()
          .maybeSingle();

      if (updateRes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось списать войсы — возможно, недостаточно средств. Попробуйте снова.')
            )
          );
        }
        setState(() => _loading = false);
        return;
      }

      await supabase.from('movie_poll_votes').insert(inserts);

      if (mounted) {
        final moviesText = selectedMovieLabels.isEmpty
            ? 'фильм'
            : selectedMovieLabels.join(', ');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Вы успешно проголосовали!'),
            content: Text(
              'Вы проголосовали за: $moviesText.\nЭто стоило: $needed войсов.',
            ),
            actions: [
              ArtDecoButton(
                text: 'OK', 
                onPressed: () => Navigator.of(ctx).pop(),
                primary: true,
              ),
            ],
          ),
        );
      }

      if (mounted) {
        try {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } catch (_) {}
      }

      if (widget.onVoted != null) {
        try {
          await widget.onVoted!();
        } catch (_) {}
      }

      await _loadState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при отправке голосов: $e'))
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, Map<String, dynamic>>?> _showVoteDialog() async {
    final List<bool> selected = List<bool>.filled(_options.length, false);
    final List<TextEditingController> countCtrls = 
        List.generate(_options.length, (_) => TextEditingController(text: '1'));

    final result = await showDialog<Map<String, Map<String, dynamic>>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          return AlertDialog(
            title: Text(_activePoll?['title']?.toString() ?? 'Голосование за фильм'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                                final ns = s.replaceAll(RegExp(r'[^0-9]'), '');
                                if (ns != s) {
                                  countCtrls[idx].text = ns;
                                  countCtrls[idx].selection = 
                                      TextSelection.fromPosition(TextPosition(offset: ns.length));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx2).pop(null),
                child: const Text('Отмена'),
              ),
              ArtDecoButton(
                text: 'Проголосовать',
                onPressed: () {
                  final any = selected.any((v) => v);
                  if (!any) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      const SnackBar(content: Text('Отметьте хотя бы один вариант'))
                    );
                    return;
                  }
                  
                  final Map<String, Map<String, dynamic>> out = {};
                  for (var i = 0; i < selected.length; i++) {
                    final sel = selected[i];
                    final txt = countCtrls[i].text.trim();
                    final parsed = int.tryParse(txt) ?? 0;
                    
                    if (sel && parsed <= 0) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        const SnackBar(content: Text('Введите корректное количество голосов (целое > 0)'))
                      );
                      return;
                    }
                    out[i.toString()] = {'selected': sel, 'votes': parsed};
                  }
                  Navigator.of(ctx2).pop(out);
                },
                primary: true,
              ),
            ],
          );
        });
      },
    );

    for (final c in countCtrls) {
      try {
        c.dispose();
      } catch (_) {}
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _loading || _disabled;
    return SizedBox(
      width: double.infinity,
      child: ArtDecoButton(
        text: _loading ? 'Загрузка...' : 'Я посмотрел фильм и хочу голосовать',
        onPressed: disabled ? null : _onPressed,
        loading: _loading,
        primary: true,
      ),
    );
  }
}
