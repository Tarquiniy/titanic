// lib/transfer_v_screen.dart
//
// Экран для перевода V-поинтов между пользователями.
// ЛОГИКА:
// - politician НЕ ВИДИТ politician в списке
// - Hollywood видит всех и может переводить сам себе
// - politician -> politician запрещено (кроме Hollywood)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

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

  List<Map<String, dynamic>> _visibleRecipients = [];
  bool _recipientsLoading = false;
  String _recipientsError = '';

  Map<String, dynamic>? _selectedRecipient;

  // ✅ актуальный баланс войсов (чтобы показывать в поле и валидировать по свежему)
  double _currentVBalance = 0.0;
  bool _balanceLoading = false;

  bool get _isHollywoodSender {
    final role = widget.user.role.toString().toLowerCase();
    return role.contains('hollywood') || role.contains('голливуд');
  }

  bool get _isPoliticianSender {
    return widget.user.role.toString() == 'politician';
  }

  // ✅ кнопка активна только когда выбран получатель и введена сумма
  bool get _canSubmit {
    if (_loading) return false;
    if (_selectedRecipient == null) return false;

    final raw = _amountCtrl.text.trim();
    final amount = double.tryParse(raw.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return false;

    // учитываем свежий баланс (если не загрузился — fallback на модель)
    final bal = (_currentVBalance > 0) ? _currentVBalance : widget.user.vBalance;
    if (amount > bal) return false;

    return true;
  }

  @override
  void initState() {
    super.initState();
    _currentVBalance = widget.user.vBalance;
    _amountCtrl.addListener(_onAmountOrRecipientChanged);
    _toCtrl.addListener(_onAmountOrRecipientChanged);
    _loadRecipients();
    _loadCurrentBalance();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onAmountOrRecipientChanged() {
    if (!mounted) return;
    // ✅ перерисуем кнопку "Перевести" в зависимости от заполненности
    setState(() {});
  }

  Future<void> _loadCurrentBalance() async {
    setState(() => _balanceLoading = true);
    try {
      final row = await supabase
          .from('user_credentials')
          .select('v_balance')
          .eq('id', widget.user.id)
          .maybeSingle();

      final raw = row?['v_balance'];
      double parsed = widget.user.vBalance;
      if (raw is num) parsed = raw.toDouble();
      if (raw is String) parsed = double.tryParse(raw.replaceAll(',', '.')) ?? parsed;

      if (!mounted) return;
      setState(() => _currentVBalance = parsed);
    } catch (_) {
      // ignore, fallback already set
    } finally {
      if (!mounted) return;
      setState(() => _balanceLoading = false);
    }
  }

  Future<void> _loadRecipients() async {
    setState(() {
      _recipientsLoading = true;
      _recipientsError = '';
    });

    try {
      final dynamic res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name, role')
          .order('first_name');

      List<Map<String, dynamic>> list = [];

      if (res is List) {
        list = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }

      final List<Map<String, dynamic>> filtered = [];

      for (final user in list) {
        final userId = user['id'];
        final userRole = (user['role'] ?? '').toString();

        // ❌ Политик не видит других политиков
        if (_isPoliticianSender && userRole == 'politician') {
          continue;
        }

        // ❌ Никто кроме Hollywood не видит сам себя
        if (!_isHollywoodSender && userId == widget.user.id) {
          continue;
        }

        filtered.add(user);
      }

      setState(() {
        _visibleRecipients = filtered;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _recipientsError = 'Ошибка при загрузке получателей: ${e.message}';
        _visibleRecipients = [];
      });
    } catch (e) {
      setState(() {
        _recipientsError = 'Ошибка при загрузке получателей: $e';
        _visibleRecipients = [];
      });
    } finally {
      setState(() {
        _recipientsLoading = false;
      });
    }
  }

  Future<void> _openRecipientPicker() async {
    if (_recipientsLoading) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecipientPickerSheet(recipients: _visibleRecipients),
    );

    if (selected != null) {
      _selectedRecipient = selected;
      final first = (selected['first_name'] ?? '').toString();
      final last = (selected['last_name'] ?? '').toString();
      _toCtrl.text = ('$first $last').trim().isEmpty ? 'Без имени' : '$first $last';

      if (mounted) setState(() {});
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _transfer() async {
    // ✅ не прячем клавиатуру вообще (никаких FocusScope.unfocus())
    // ✅ ошибки показываем, но фокус не трогаем

    setState(() => _error = null);

    // дополнительная защита: если кнопка каким-то образом нажалась
    if (_selectedRecipient == null) {
      setState(() => _error = 'Выберите получателя');
      return;
    }

    // Валидируем, но не делаем autofocus/унфокус
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final senderRole = widget.user.role.toString();
    final recipientRole = (_selectedRecipient!['role'] ?? '').toString();

    if (senderRole == 'politician' &&
        recipientRole == 'politician' &&
        !_isHollywoodSender) {
      setState(() => _error =
          'Пользователям с ролью politician запрещено переводить другим пользователям с ролью politician');
      return;
    }

    final toUsername = (_selectedRecipient!['telegram_username'] ?? '').toString();
    if (toUsername.isEmpty) {
      setState(() => _error = 'У получателя не задан идентификатор');
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Некорректная сумма');
      return;
    }

    final bal = (_currentVBalance > 0) ? _currentVBalance : widget.user.vBalance;
    if (amount > bal) {
      setState(() => _error = 'Недостаточно средств');
      return;
    }

    setState(() => _loading = true);

    try {
      await supabase.rpc('transfer_v_points', params: {
        'from_user': widget.user.id,
        'to_username': toUsername,
        'amount': amount,
      });

      // ✅ всплывашка успеха "Вы перевели Пользователю Количество войсов"
      final first = (_selectedRecipient!['first_name'] ?? '').toString();
      final last = (_selectedRecipient!['last_name'] ?? '').toString();
      final displayName = ('$first $last').trim().isEmpty ? 'Без имени' : '$first $last';
      _showSnack('Вы перевели $displayName ${amount.toStringAsFixed(0)} войсов');

      // обновим баланс локально/сервера (best effort)
      try {
        await _loadCurrentBalance();
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String? _validateAmount(String? v) {
    if (v == null || v.isEmpty) return 'Введите сумму';
    final n = double.tryParse(v.replaceAll(',', '.'));
    if (n == null || n <= 0) return 'Некорректная сумма';

    final bal = (_currentVBalance > 0) ? _currentVBalance : widget.user.vBalance;
    if (n > bal) return 'Сумма превышает ваш баланс';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bal = (_currentVBalance > 0) ? _currentVBalance : widget.user.vBalance;

    return Scaffold(
      appBar: AppBar(title: const Text('Перевести Войсы')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction, // ✅ ошибки без “перефокуса”
          child: Column(
            children: [
              GestureDetector(
                onTap: _openRecipientPicker,
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _toCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Получатель',
                      suffixIcon: Icon(Icons.expand_more),
                    ),
                    validator: (_) => _selectedRecipient == null ? 'Выберите получателя' : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'Количество V (баланс: ${bal.toStringAsFixed(0)})',
                  suffixIcon: _balanceLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: _validateAmount,
                // ✅ не скрывать клавиатуру при ошибках:
                // мы не дергаем unfocus, а ввод продолжается
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              if (_recipientsLoading) const LinearProgressIndicator(),
              if (_recipientsError.isNotEmpty)
                Text(_recipientsError, style: const TextStyle(color: Colors.red)),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  // ✅ неактивна, пока не выбран получатель и не введено число
                  onPressed: _canSubmit ? _transfer : null,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Перевести'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: список и поиск получателей
class RecipientPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipients;
  const RecipientPickerSheet({Key? key, required this.recipients}) : super(key: key);

  @override
  State<RecipientPickerSheet> createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<RecipientPickerSheet> {
  late List<Map<String, dynamic>> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.recipients);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.recipients.where((row) {
        return (row['first_name'] ?? '').toString().toLowerCase().contains(q) ||
            (row['last_name'] ?? '').toString().toLowerCase().contains(q) ||
            (row['telegram_username'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Поиск',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final row = _filtered[i];
                final name = '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
                return ListTile(
                  title: Text(name.isEmpty ? 'Без имени' : name),
                  onTap: () => Navigator.pop(context, row),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
