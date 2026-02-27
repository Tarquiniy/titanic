// lib/screens/collect_debt_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectDebtScreen extends StatefulWidget {
  final String usurerId; // ID мафиози-ростовщика
  final Future<void> Function()? onSuccess;

  const CollectDebtScreen({
    Key? key,
    required this.usurerId,
    this.onSuccess,
  }) : super(key: key);

  @override
  State<CollectDebtScreen> createState() => _CollectDebtScreenState();
}

class _CollectDebtScreenState extends State<CollectDebtScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _players = [];
  String? _selectedPlayerId;
  bool _loading = false;
  bool _loadingPlayers = true;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    setState(() {
      _loadingPlayers = true;
    });
    try {
      // Загружаем всех игроков, кроме банка и самого ростовщика
      final res = await supabase
          .from('user_credentials')
          .select('id, first_name, last_name, telegram_username, role')
          .order('first_name');

      if (res is List) {
        final List<Map<String, dynamic>> list = [];
        for (final e in res) {
          final row = Map<String, dynamic>.from(e as Map);
          final role = (row['role'] ?? '').toString().toLowerCase();
          final id = row['id']?.toString();
          
          // Исключаем банк и самого ростовщика
          if (role.contains('банк') || role.contains('bank') || id == widget.usurerId) {
            continue;
          }
          
          list.add(row);
        }
        setState(() {
          _players = list;
        });
      }
    } catch (e) {
      debugPrint('CollectDebtScreen._loadPlayers error: $e');
      setState(() {
        _players = [];
      });
    } finally {
      if (mounted) setState(() => _loadingPlayers = false);
    }
  }

  String _getPlayerName(Map<String, dynamic> player) {
    final first = player['first_name'] ?? '';
    final last = player['last_name'] ?? '';
    final un = player['telegram_username'] ?? '';

    if (first.toString().trim().isEmpty && last.toString().trim().isEmpty) {
      return un.isNotEmpty ? un : player['id']?.toString() ?? '—';
    }
    return '${first} ${last}'.trim();
  }

  Future<void> _collectDebt() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPlayerId == null) {
      _showSnack('Выберите игрока для сбора долга');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // 1. Получаем балансы должника
      final debtorRow = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance, first_name, last_name')
          .eq('id', _selectedPlayerId as Object)
          .maybeSingle();

      if (debtorRow is! Map<String, dynamic>) {
        _showSnack('Игрок не найден');
        setState(() => _loading = false);
        return;
      }

      final vBalRaw = debtorRow['v_balance'];
      final mBalRaw = debtorRow['m_balance'];

      final double debtorV = (vBalRaw is num) ? vBalRaw.toDouble() :
                          (vBalRaw is String) ? double.tryParse(vBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;
      final double debtorM = (mBalRaw is num) ? mBalRaw.toDouble() :
                          (mBalRaw is String) ? double.tryParse(mBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;

      // 2. Вычисляем половину (округление вниз)
      final double halfV = (debtorV / 2).floorToDouble();
      final double halfM = (debtorM / 2).floorToDouble();

      if (halfV <= 0 && halfM <= 0) {
        _showSnack('У выбранного игрока нет средств для сбора');
        setState(() => _loading = false);
        return;
      }

      // 3. Получаем текущие балансы ростовщика
      final usurerRow = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance, first_name, last_name')
          .eq('id', widget.usurerId)
          .maybeSingle();

      if (usurerRow is! Map<String, dynamic>) {
        _showSnack('Ростовщик не найден');
        setState(() => _loading = false);
        return;
      }

      final usurerVBalRaw = usurerRow['v_balance'];
      final usurerMBalRaw = usurerRow['m_balance'];

      final double usurerCurrentV = (usurerVBalRaw is num) ? usurerVBalRaw.toDouble() :
                                  (usurerVBalRaw is String) ? double.tryParse(usurerVBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;
      final double usurerCurrentM = (usurerMBalRaw is num) ? usurerMBalRaw.toDouble() :
                                  (usurerMBalRaw is String) ? double.tryParse(usurerMBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;

      // 4. Выполняем перевод в транзакции
      // 4.1. Списываем у должника
      await supabase
          .from('user_credentials')
          .update({
            'v_balance': debtorV - halfV,
            'm_balance': debtorM - halfM,
          })
          .eq('id', _selectedPlayerId as Object);

      // 4.2. Добавляем ростовщику
      await supabase
          .from('user_credentials')
          .update({
            'v_balance': usurerCurrentV + halfV,
            'm_balance': usurerCurrentM + halfM,
          })
          .eq('id', widget.usurerId);

      // 5. Сбрасываем флаг ростовщика после использования
      await supabase
          .from('user_credentials')
          .update({
            'usurer': false,
          })
          .eq('id', widget.usurerId);

      // 6. Записываем в историю
      await supabase.from('debt_collection_history').insert({
        'usurer_id': widget.usurerId,
        'debtor_id': _selectedPlayerId,
        'collected_v': halfV,
        'collected_m': halfM,
        'debtor_v_before': debtorV,
        'debtor_m_before': debtorM,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 7. Добавляем запись в журнал
      final debtorName = '${debtorRow['first_name'] ?? ''} ${debtorRow['last_name'] ?? ''}'.trim();
      final debtorNameDisplay = debtorName.isEmpty ? 'Игрок ID: $_selectedPlayerId' : debtorName;
      
      final usurerName = '${usurerRow['first_name'] ?? ''} ${usurerRow['last_name'] ?? ''}'.trim();
      final usurerNameDisplay = usurerName.isEmpty ? 'Игрок ID: ${widget.usurerId}' : usurerName;

      await supabase.from('user_journal').insert({
        'user_id': widget.usurerId,
        'visible_role': 'all',
        'actor_id': widget.usurerId,
        'title': 'Сбор долга',
        'message': '$usurerNameDisplay собрал долг с $debtorNameDisplay: ${halfV.toStringAsFixed(0)} V и ${halfM.toStringAsFixed(0)} M. ',
        'metadata': {
          'debtor_id': _selectedPlayerId,
          'collected_v': halfV,
          'collected_m': halfM,
          'type': 'debt_collection',
          'usurer_reset': true
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showSnack('Успешно собрано: ${halfV.toStringAsFixed(0)} V и ${halfM.toStringAsFixed(0)} M.');

      if (widget.onSuccess != null) {
        await widget.onSuccess!();
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('CollectDebtScreen._collectDebt error: $e');
      _showSnack('Ошибка при сборе долга: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Забрать долг'),
      ),
      body: _loadingPlayers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Вы заберёте половину войсов и майндов',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 24),

                    // Выбор игрока
                    DropdownButtonFormField<String>(
                      value: _selectedPlayerId,
                      items: _players.map((player) {
                        return DropdownMenuItem(
                          value: player['id']?.toString(),
                          child: Text(_getPlayerName(player)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedPlayerId = value),
                      decoration: const InputDecoration(
                        labelText: 'Выберите игрока',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null ? 'Выберите игрока' : null,
                    ),

                    const SizedBox(height: 32),

                    // Кнопка сбора долга
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_loading || _selectedPlayerId == null)
                            ? null
                            : _collectDebt,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'ВЗЫСКАТЬ ДОЛГ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
