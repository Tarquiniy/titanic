import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class BloodPokerBlock extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function()? onBetPlaced;

  const BloodPokerBlock({
    Key? key,
    required this.currentUserId,
    this.onBetPlaced,
  }) : super(key: key);

  @override
  State<BloodPokerBlock> createState() => _BloodPokerBlockState();
}

class _BloodPokerBlockState extends State<BloodPokerBlock> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _activeStage;
  List<Map<String, dynamic>> _options = [];
  bool _alreadyBet = false;
  List<Map<String, dynamic>> _userBets = [];
  double _userBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() => _loading = true);
    
    try {
      final stageRes = await supabase
          .from('blood_poker_stages')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (stageRes is Map<String, dynamic>) {
        _activeStage = Map<String, dynamic>.from(stageRes);
        final stageId = _activeStage!['id'] is int 
            ? _activeStage!['id'] as int 
            : int.parse(_activeStage!['id'].toString());

        final optionsRes = await supabase
            .from('blood_poker_options')
            .select()
            .eq('stage_id', stageId)
            .order('id');

        if (optionsRes is List) {
          _options = optionsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }

        final betsRes = await supabase
            .from('blood_poker_bets')
            .select('amount, option_id')
            .eq('stage_id', stageId)
            .eq('user_id', widget.currentUserId);

        if (betsRes is List && betsRes.isNotEmpty) {
          _alreadyBet = true;
          _userBets = betsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          _alreadyBet = false;
          _userBets = [];
        }
      } else {
        _activeStage = null;
        _options = [];
        _alreadyBet = false;
        _userBets = [];
      }

      final balanceRes = await supabase
          .from('user_credentials')
          .select('m_balance')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      if (balanceRes is Map<String, dynamic>) {
        final mb = balanceRes['m_balance'];
        if (mb is num) {
          _userBalance = mb.toDouble();
        } else if (mb is String) {
          _userBalance = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
        }
      }
    } catch (e) {
      debugPrint('BloodPokerBlock._loadState error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _placeBet() async {
    if (_activeStage == null || _alreadyBet || _options.isEmpty) return;

    final List<bool> selected = List<bool>.filled(_options.length, false);
    final List<TextEditingController> amountCtrls = List.generate(
      _options.length,
      (_) => TextEditingController(text: '1'),
    );

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) {
            return AlertDialog(
              title: Text(_activeStage?['title']?.toString() ?? 'Покер на крови'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_activeStage?['description'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_activeStage!['description']!.toString()),
                      ),
                    const Text('Выберите варианты и укажите количество майндов для каждого:'),
                    const SizedBox(height: 8),
                    ..._options.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final option = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected[idx],
                              onChanged: (value) {
                                setStateDialog(() {
                                  selected[idx] = value ?? false;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option['label'] ?? '—',
                                style: TextStyle(
                                  color: selected[idx] ? Colors.black : Colors.grey,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: amountCtrls[idx],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Майнды',
                                  border: OutlineInputBorder(),
                                ),
                                enabled: selected[idx],
                                onChanged: (value) {
                                  final parsed = int.tryParse(value);
                                  if (parsed != null && parsed > _userBalance) {
                                    amountCtrls[idx].value = amountCtrls[idx].value.copyWith(
                                      text: _userBalance.floor().toString(),
                                      selection: TextSelection.collapsed(
                                        offset: _userBalance.floor().toString().length,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                    Text(
                      'Ваш баланс M: ${_userBalance.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(false),
                  child: const Text('Отмена'),
                ),
                ArtDecoButton(
                  text: 'Сделать ставку',
                  onPressed: () async {
                    final anySelected = selected.any((v) => v);
                    if (!anySelected) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        const SnackBar(content: Text('Выберите хотя бы один вариант')),
                      );
                      return;
                    }

                    final List<Map<String, dynamic>> selectedBets = [];
                    int totalAmount = 0;

                    for (var i = 0; i < selected.length; i++) {
                      if (selected[i]) {
                        final amountStr = amountCtrls[i].text.trim();
                        final amount = int.tryParse(amountStr);

                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(ctx2).showSnackBar(
                            const SnackBar(
                              content: Text('Введите корректное количество майндов для всех выбранных вариантов'),
                            ),
                          );
                          return;
                        }

                        final optionId = _options[i]['id'] is int 
                            ? _options[i]['id'] as int 
                            : int.parse(_options[i]['id'].toString());
                        
                        selectedBets.add({
                          'option_id': optionId,
                          'amount': amount,
                          'label': _options[i]['label'] ?? '—',
                        });
                        totalAmount += amount;
                      }
                    }

                    if (totalAmount > _userBalance) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Недостаточно майндов. У вас ${_userBalance.toStringAsFixed(0)}, требуется $totalAmount',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.of(ctx2).pop(true);
                  },
                  primary: true,
                ),
              ],
            );
          },
        );
      },
    );

    for (final ctrl in amountCtrls) {
      ctrl.dispose();
    }

    if (result != true) return;

    setState(() => _loading = true);
    
    try {
      final currentBalanceRes = await supabase
          .from('user_credentials')
          .select('m_balance')
          .eq('id', widget.currentUserId)
          .maybeSingle();

      double currentBalance = 0.0;
      if (currentBalanceRes is Map<String, dynamic>) {
        final mb = currentBalanceRes['m_balance'];
        if (mb is num) currentBalance = mb.toDouble();
        else if (mb is String) {
          currentBalance = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
        }
      }

      int totalAmount = 0;
      final List<Map<String, dynamic>> selectedBets = [];

      for (var i = 0; i < selected.length; i++) {
        if (selected[i]) {
          final amountStr = amountCtrls[i].text.trim();
          final amount = int.tryParse(amountStr) ?? 0;
          final optionId = _options[i]['id'] is int 
              ? _options[i]['id'] as int 
              : int.parse(_options[i]['id'].toString());

          selectedBets.add({
            'option_id': optionId,
            'amount': amount,
            'label': _options[i]['label'] ?? '—',
          });
          totalAmount += amount;
        }
      }

      if (totalAmount > currentBalance) {
        _showMessage('Недостаточно майндов. Текущий баланс: ${currentBalance.toStringAsFixed(0)}');
        setState(() => _loading = false);
        return;
      }

      final newBalance = currentBalance - totalAmount;
      await supabase
          .from('user_credentials')
          .update({'m_balance': newBalance})
          .eq('id', widget.currentUserId);

      final stageId = _activeStage!['id'] is int 
          ? _activeStage!['id'] as int 
          : int.parse(_activeStage!['id'].toString());
      
      final List<Map<String, dynamic>> betInserts = [];

      for (final bet in selectedBets) {
        betInserts.add({
          'stage_id': stageId,
          'option_id': bet['option_id'],
          'user_id': widget.currentUserId,
          'amount': bet['amount'],
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      await supabase.from('blood_poker_bets').insert(betInserts);

      final betDescriptions = selectedBets
          .map((bet) => '${bet['label']}: ${bet['amount']} M')
          .join(', ');

      await supabase.from('user_journal').insert({
        'user_id': widget.currentUserId,
        'visible_role': 'all',
        'actor_id': widget.currentUserId,
        'title': 'Ставка в покере на крови',
        'message': 'Сделаны ставки в покере на крови: $betDescriptions (всего: $totalAmount M)',
        'metadata': {
          'stage_id': stageId,
          'bets': selectedBets,
          'total_amount': totalAmount,
          'type': 'blood_poker_bet'
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showMessage('Ставки на общую сумму $totalAmount M приняты!');

      if (widget.onBetPlaced != null) {
        await widget.onBetPlaced!();
      }

      await _loadState();
    } catch (e) {
      _showMessage('Ошибка при создании ставки: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showMessage(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: double.infinity,
        child: ArtDecoButton(
          text: 'Загрузка...',
          onPressed: null,
          loading: true,
        ),
      );
    }

    if (_activeStage == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _activeStage!['title']?.toString() ?? 'Покер на крови',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(Icons.casino, color: Colors.red.shade700),
              ],
            ),
            if (_activeStage?['description'] != null) ...[
              const SizedBox(height: 8),
              Text(
                _activeStage!['description']!.toString(),
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 12),
            if (_alreadyBet)
              Column(
                children: [
                  const Text(
                    'Вы уже сделали ставки',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  ..._userBets.map((bet) {
                    final optionId = bet['option_id'];
                    final amount = bet['amount'] ?? 0;
                    final option = _options.firstWhere(
                      (opt) => (opt['id'] is int 
                          ? opt['id'] as int 
                          : int.parse(opt['id'].toString())) == optionId,
                      orElse: () => {},
                    );
                    final label = option.isNotEmpty ? option['label'] ?? '—' : '—';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• $label',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                            ),
                          ),
                          Text(
                            '$amount M',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  Text(
                    'Всего поставлено: ${_userBets.fold<int>(0, (sum, bet) => sum + (bet['amount'] is int ? bet['amount'] as int : int.tryParse(bet['amount'].toString()) ?? 0))} M',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Text(
                    'Ваш баланс: ${_userBalance.toStringAsFixed(0)} M',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ArtDecoButton(
                      text: 'СДЕЛАТЬ СТАВКУ',
                      onPressed: _placeBet,
                      primary: true,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}