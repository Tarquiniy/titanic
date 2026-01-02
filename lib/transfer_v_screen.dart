import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';

class TransferVScreen extends StatefulWidget {
  final AppUser user;
  const TransferVScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<TransferVScreen> createState() => _TransferVScreenState();
}

class _TransferVScreenState extends State<TransferVScreen> {
  final _formKey = GlobalKey<FormState>();
  final _toCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  final supabase = Supabase.instance.client;

  @override
  void dispose() {
    _toCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _transfer() async {
    setState(() => _error = null);

    if (!_formKey.currentState!.validate()) return;

    final toUsername = _toCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amount == null) {
      setState(() => _error = 'Неверный формат суммы');
      return;
    }

    // Клиентская проверка роли получателя — улучшение UX (сервер всё равно проверит)
    try {
      setState(() => _loading = true);

      final recipient = await supabase
          .from('user_credentials')
          .select('id, role')
          .eq('telegram_username', toUsername)
          .maybeSingle();

      if (recipient == null) {
        setState(() => _error = 'Получатель не найден');
        return;
      }

      final String toRole = (recipient as Map)['role']?.toString() ?? '';

      // Правило: если отправитель politician и получатель politician — запрещено
      if (widget.user.role == 'politician' && toRole == 'politician') {
        setState(() => _error = 'Политики не могут передавать V политикам');
        return;
      }

      // Дополнительно валидируем наличие баланса на клиенте
      if (amount > widget.user.vBalance) {
        setState(() => _error = 'Недостаточно средств');
        return;
      }

      // Вызов серверной rpc-функции (сервер также проверяет роли)
      await supabase.rpc('transfer_v_points', params: {
        'from_user': widget.user.id,
        'to_username': toUsername,
        'amount': amount,
      });

      // Обновляем локально баланс (для более корректного состояния рекомендуется ре-fetch с сервера)
      setState(() {
        widget.user.vBalance = widget.user.vBalance - amount;
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // Ошибка от PostgREST / RPC
      setState(() => _error = e.message ?? e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String? _validateRecipient(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите username получателя';
    if (v.contains('@')) return 'Укажите username без @';
    if (v.contains(' ')) return 'Username не должен содержать пробелов';
    return null;
  }

  String? _validateAmount(String? v) {
    if (v == null || v.isEmpty) return 'Введите сумму';
    final n = double.tryParse(v.replaceAll(',', '.'));
    if (n == null || n <= 0) return 'Некорректная сумма';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Перевод V')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(
              controller: _toCtrl,
              decoration: const InputDecoration(labelText: 'Получатель (telegram username)'),
              validator: _validateRecipient,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Количество V'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: _validateAmount,
            ),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _transfer,
                child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Перевести'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
