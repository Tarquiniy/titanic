import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MafiaProposalScreen extends StatefulWidget {
  final String mafiaUserId;
  final Future<void> Function()? onSuccess;

  const MafiaProposalScreen({
    Key? key,
    required this.mafiaUserId,
    this.onSuccess,
  }) : super(key: key);

  @override
  State<MafiaProposalScreen> createState() => _MafiaProposalScreenState();
}

class _MafiaProposalScreenState extends State<MafiaProposalScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _politicians = [];
  String? _selectedFromPoliticianId;
  String? _selectedToPoliticianId;
  bool _loading = false;
  bool _loadingPoliticians = true;

  @override
  void initState() {
    super.initState();
    _loadPoliticians();
  }

  Future<void> _loadPoliticians() async {
    setState(() {
      _loadingPoliticians = true;
    });
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, first_name, last_name, telegram_username')
          .eq('role', 'politician')
          .order('first_name');

      if (res is List) {
        setState(() {
          _politicians = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint('MafiaProposalScreen._loadPoliticians error: $e');
      setState(() {
        _politicians = [];
      });
    } finally {
      if (mounted) setState(() => _loadingPoliticians = false);
    }
  }

  String _getPoliticianName(Map<String, dynamic> pol) {
    final first = pol['first_name'] ?? '';
    final last = pol['last_name'] ?? '';
    final un = pol['telegram_username'] ?? '';

    if (first.toString().trim().isEmpty && last.toString().trim().isEmpty) {
      return un.isNotEmpty ? un : pol['id']?.toString() ?? '—';
    }
    return '${first} ${last}'.trim();
  }

  Future<void> _submitTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFromPoliticianId == null || _selectedToPoliticianId == null) {
      _showSnack('Выберите обоих политиков');
      return;
    }

    if (_selectedFromPoliticianId == _selectedToPoliticianId) {
      _showSnack('Нельзя выбрать одного и того же политика');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Проверяем, что мафиози еще не использовал предложение
      final mafiaRow = await supabase
          .from('user_credentials')
          .select('used_mafia_proposal')
          .eq('id', widget.mafiaUserId)
          .maybeSingle();

      if (mafiaRow is Map<String, dynamic>) {
        final usedFlag = mafiaRow['used_mafia_proposal'];
        final bool used = (usedFlag == true) || (usedFlag?.toString().toLowerCase() == 'true');

        if (used) {
          _showSnack('Вы уже использовали это предложение в этой игре');
          setState(() => _loading = false);
          return;
        }
      }

      // Получаем балансы политика-источника
      final fromPolitician = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance')
          .eq('id', _selectedFromPoliticianId as Object)
          .maybeSingle();

      if (fromPolitician is! Map<String, dynamic>) {
        _showSnack('Политик-источник не найден');
        setState(() => _loading = false);
        return;
      }

      final vBalRaw = fromPolitician['v_balance'];
      final mBalRaw = fromPolitician['m_balance'];

      final double fromV = (vBalRaw is num) ? vBalRaw.toDouble() :
                          (vBalRaw is String) ? double.tryParse(vBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;
      final double fromM = (mBalRaw is num) ? mBalRaw.toDouble() :
                          (mBalRaw is String) ? double.tryParse(mBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;

      // Проверяем, что у политика-источника есть средства
      if (fromV <= 0 && fromM <= 0) {
        _showSnack('У выбранного политика нет войсов и майндов для передачи');
        setState(() => _loading = false);
        return;
      }

      // Получаем текущие балансы политика-получателя
      final toPolitician = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance')
          .eq('id', _selectedToPoliticianId as Object)
          .maybeSingle();

      if (toPolitician is! Map<String, dynamic>) {
        _showSnack('Политик-получатель не найден');
        setState(() => _loading = false);
        return;
      }

      final toVBalRaw = toPolitician['v_balance'];
      final toMBalRaw = toPolitician['m_balance'];

      final double toCurrentV = (toVBalRaw is num) ? toVBalRaw.toDouble() :
                               (toVBalRaw is String) ? double.tryParse(toVBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;
      final double toCurrentM = (toMBalRaw is num) ? toMBalRaw.toDouble() :
                               (toMBalRaw is String) ? double.tryParse(toMBalRaw.replaceAll(',', '.')) ?? 0.0 : 0.0;

      // Выполняем перевод в транзакции
      // 1. Обнуляем баланс источника
      await supabase
          .from('user_credentials')
          .update({
            'v_balance': 0,
            'm_balance': 0,
          })
          .eq('id', _selectedFromPoliticianId as Object);

      // 2. Добавляем средства получателю
      await supabase
          .from('user_credentials')
          .update({
            'v_balance': toCurrentV + fromV,
            'm_balance': toCurrentM + fromM,
          })
          .eq('id', _selectedToPoliticianId as Object);

      // 3. Помечаем, что мафиози использовал предложение
      await supabase
          .from('user_credentials')
          .update({
            'used_mafia_proposal': true,
          })
          .eq('id', widget.mafiaUserId);

      // 4. Записываем в историю
      await supabase.from('mafia_proposal_history').insert({
        'mafia_id': widget.mafiaUserId,
        'from_politician_id': _selectedFromPoliticianId,
        'to_politician_id': _selectedToPoliticianId,
        'transferred_v': fromV,
        'transferred_m': fromM,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showSnack('Успешно! Все войсы и майнды переданы');

      if (widget.onSuccess != null) {
        await widget.onSuccess!();
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('MafiaProposalScreen._submitTransfer error: $e');
      _showSnack('Ошибка при передаче: $e');
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
        title: const Text('Предложение от которого нельзя отказаться'),
      ),
      body: _loadingPoliticians
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Это предложение можно использовать только один раз за игру.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Все войсы и майнды первого политика будут переданы второму.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    // Выбор политика-источника
                    const Text(
                      'КТО (отбираем войсы и майнды):',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedFromPoliticianId,
                      items: _politicians.map((pol) {
                        return DropdownMenuItem(
                          value: pol['id']?.toString(),
                          child: Text(_getPoliticianName(pol)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedFromPoliticianId = value),
                      decoration: const InputDecoration(
                        labelText: 'Выберите политика',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null ? 'Выберите политика' : null,
                    ),

                    const SizedBox(height: 24),

                    // Выбор политика-получателя
                    const Text(
                      'КОМУ (передаём войсы и майнды):',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedToPoliticianId,
                      items: _politicians.map((pol) {
                        return DropdownMenuItem(
                          value: pol['id']?.toString(),
                          child: Text(_getPoliticianName(pol)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedToPoliticianId = value),
                      decoration: const InputDecoration(
                        labelText: 'Выберите политика',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null ? 'Выберите политика' : null,
                    ),

                    const SizedBox(height: 32),

                    // Кнопка подтверждения
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submitTransfer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
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
                                'ПЕРЕДАТЬ',
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