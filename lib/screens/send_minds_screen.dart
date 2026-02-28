// lib/screens/send_minds_screen.dart
// Экран: Потратить майнды на рецензию
// - Ввод суммы майндов (целое положительное число)
// - Выбор пользователя с ролью "Журналист" (journalist / журналист)
// - Подтверждение: перевод майндов с баланса отправителя (Hollywood) в m_balance получателя
// Поведение:
//  - Сначала пробуем вызвать RPC 'transfer_minds' (если она есть в Supabase).
//  - Если RPC отсутствует или выдаёт ошибку, выполняем fallback:
//      1) update sender: .update({'m_balance': new}).eq('id', sender).gte('m_balance', amount).maybeSingle()
//      2) if success -> update recipient: .update({'m_balance': increment}).eq('id', recipient)
//      3) if recipient update fails -> попытка отката: вернуть деньги отправителю
//  - Пользователь информируется о статусе; все ошибки логируются.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SendMindsScreen extends StatefulWidget {
  final String currentUserId;
  const SendMindsScreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<SendMindsScreen> createState() => _SendMindsScreenState();
}

class _SendMindsScreenState extends State<SendMindsScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountCtrl = TextEditingController();

  List<Map<String, dynamic>> _journalists = [];
  String? _selectedJournalistId;
  bool _loadingUsers = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadJournalists();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadJournalists() async {
    setState(() => _loadingUsers = true);
    try {
      final res = await supabase.from('user_credentials').select('id, telegram_username, first_name, last_name, role').order('first_name');
      final List<Map<String, dynamic>> list = [];
      if (res is List) {
        for (final e in res) {
          final row = Map<String, dynamic>.from(e as Map);
          final roleRaw = (row['role'] ?? '').toString().toLowerCase();
          if (roleRaw.contains('журналист') || roleRaw.contains('journalist')) {
            list.add(row);
          }
        }
      }
      setState(() => _journalists = list);
    } catch (e) {
      debugPrint('SendMindsScreen._loadJournalists error: $e');
      setState(() => _journalists = []);
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  String _displayName(Map<String, dynamic> u) {
    final fn = (u['first_name'] ?? '').toString();
    final ln = (u['last_name'] ?? '').toString();
    final un = (u['telegram_username'] ?? '').toString();
    if (fn.trim().isEmpty && ln.trim().isEmpty) return un.isNotEmpty ? un : (u['id']?.toString() ?? '—');
    return (fn + ' ' + ln).trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amountStr = _amountCtrl.text.trim();
    final int? amount = int.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showSnack('Введите корректное число майндов (> 0).');
      return;
    }
    if (_selectedJournalistId == null || _selectedJournalistId!.isEmpty) {
      _showSnack('Выберите получателя (журналиста).');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      // First try RPC 'transfer_minds' (optional server-side transaction)
      try {
        final rpcRes = await supabase.rpc('transfer_minds', params: {
          'sender_id': widget.currentUserId,
          'recipient_id': _selectedJournalistId,
          'amount': amount,
        }).maybeSingle();
        // If RPC succeeded (no exception), assume success.
        _showSnack('Успешно: переведено $amount майндов.');
        if (mounted) Navigator.of(context).pop(true);
        return;
      } catch (rpcErr) {
        // RPC not found or errored — fall back to client-side method
        debugPrint('transfer_minds RPC failed or not available -> $rpcErr');
      }

      // Fetch sender balance (fresh)
      final senderRow = await supabase.from('user_credentials').select('m_balance').eq('id', widget.currentUserId).maybeSingle();
      int senderBalance = 0;
      if (senderRow is Map<String, dynamic> && senderRow.containsKey('m_balance')) {
        final v = senderRow['m_balance'];
        if (v is int) senderBalance = v;
        else if (v is num) senderBalance = v.toInt();
        else if (v is String) senderBalance = int.tryParse(v) ?? 0;
      } else {
        _showSnack('Профиль отправителя не найден.');
        setState(() => _submitting = false);
        return;
      }

      if (senderBalance < amount) {
        _showSnack('Недостаточно майндов: у вас $senderBalance, требуется $amount.');
        setState(() => _submitting = false);
        return;
      }

      // 1) decrement sender with gte check
      final newSenderBalance = senderBalance - amount;
      final updSender = await supabase
          .from('user_credentials')
          .update({'m_balance': newSenderBalance})
          .eq('id', widget.currentUserId)
          .gte('m_balance', amount)
          .select()
          .maybeSingle();

      if (updSender == null) {
        // failed to update (race / insufficient funds)
        _showSnack('Не удалось списать майнды — попробуйте снова.');
        setState(() => _submitting = false);
        return;
      }

      // 2) increment recipient (use Postgres increment via fetching current and updating)
      // Try simple increment: fetch current recipient balance, then update
      final recipientRow = await supabase.from('user_credentials').select('m_balance').eq('id', _selectedJournalistId as Object).maybeSingle();
      int recipientBalance = 0;
      if (recipientRow is Map<String, dynamic> && recipientRow.containsKey('m_balance')) {
        final v = recipientRow['m_balance'];
        if (v is int) recipientBalance = v;
        else if (v is num) recipientBalance = v.toInt();
        else if (v is String) recipientBalance = int.tryParse(v) ?? 0;
      } else {
        // recipient not found — try to rollback sender
        debugPrint('Recipient not found after sender decrement. Attempting rollback.');
        await _attemptRollback(senderId: widget.currentUserId, amount: amount);
        _showSnack('Получатель не найден — перевод отменён.');
        setState(() => _submitting = false);
        return;
      }

      final newRecipientBalance = recipientBalance + amount;
      try {
        final updRecipient = await supabase
            .from('user_credentials')
            .update({'m_balance': newRecipientBalance})
            .eq('id', _selectedJournalistId as Object)
            .select()
            .maybeSingle();

        if (updRecipient == null) {
          // failed to update recipient — try rollback
          debugPrint('Failed to update recipient balance, attempting rollback.');
          final rolled = await _attemptRollback(senderId: widget.currentUserId, amount: amount);
          if (rolled) {
            _showSnack('Ошибка при переводе — средства возвращены.');
          } else {
            _showSnack('Критическая ошибка: перевод не завершён, но откат не удался. Обратитесь к администратору.');
          }
          setState(() => _submitting = false);
          return;
        }

        // success
        _showSnack('Успешно: переведено $amount майндов журналисту.');
        if (mounted) Navigator.of(context).pop(true);
        return;
      } catch (recErr) {
        debugPrint('Error updating recipient: $recErr');
        final rolled = await _attemptRollback(senderId: widget.currentUserId, amount: amount);
        if (rolled) {
          _showSnack('Ошибка при переводе — средства возвращены.');
        } else {
          _showSnack('Ошибка при переводе и откате. Обратитесь к администратору.');
        }
        setState(() => _submitting = false);
        return;
      }
    } catch (e) {
      debugPrint('SendMindsScreen._submit error: $e');
      _showSnack('Ошибка при переводе: $e');
      setState(() => _submitting = false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _attemptRollback({required String senderId, required int amount}) async {
    try {
      // try to increment sender balance by amount (best-effort)
      // fetch current
      final row = await supabase.from('user_credentials').select('m_balance').eq('id', senderId).maybeSingle();
      int curr = 0;
      if (row is Map<String, dynamic> && row.containsKey('m_balance')) {
        final v = row['m_balance'];
        if (v is int) curr = v;
        else if (v is num) curr = v.toInt();
        else if (v is String) curr = int.tryParse(v) ?? 0;
      }
      final back = curr + amount;
      await supabase.from('user_credentials').update({'m_balance': back}).eq('id', senderId);
      return true;
    } catch (e) {
      debugPrint('Rollback failed: $e');
      return false;
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
        title: const Text('Потратить майнды на рецензию'),
      ),
      body: _loadingUsers
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Количество майндов'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Введите количество майндов';
                        final parsed = int.tryParse(v.trim());
                        if (parsed == null || parsed <= 0) return 'Введите целое число больше 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedJournalistId,
                      items: _journalists
                          .map((u) => DropdownMenuItem(
                              value: u['id']?.toString(), child: Text(_displayName(u))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedJournalistId = v),
                      decoration: const InputDecoration(labelText: 'Получатель (журналист)'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Выберите получателя' : null,
                    ),
                    const SizedBox(height: 20),
                    _submitting
                        ? const CircularProgressIndicator()
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submit,
                              child: const Text('Подтвердить перевод'),
                            ),
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
