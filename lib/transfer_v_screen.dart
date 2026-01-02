// lib/transfer_v_screen.dart
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

  // Список получателей (весь список, затем клиентская фильтрация)
  List<Map<String, dynamic>> _allRecipients = [];
  List<Map<String, dynamic>> _visibleRecipients = [];
  bool _recipientsLoading = false;
  String _recipientsError = '';

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    setState(() {
      _recipientsLoading = true;
      _recipientsError = '';
    });

    try {
      // Запрашиваем всех пользователей, кроме текущего отправителя
      final dynamic res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name, role')
          .neq('id', widget.user.id)
          .order('telegram_username');

      List<Map<String, dynamic>> list = [];

      if (res is List) {
        list = res
            .where((e) => e != null)
            .map<Map<String, dynamic>>((e) {
              if (e is Map) return Map<String, dynamic>.from(e);
              return <String, dynamic>{};
            })
            .where((m) => m.isNotEmpty)
            .toList();
      } else {
        list = [];
      }

      // Клиентская фильтрация: если отправитель — politician, то исключаем политиков
      List<Map<String, dynamic>> visible;
      if (widget.user.role == 'politician') {
        visible = list.where((r) => (r['role']?.toString() ?? '') != 'politician').toList();
      } else {
        visible = list;
      }

      setState(() {
        _allRecipients = list;
        _visibleRecipients = visible;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _recipientsError = 'Ошибка при загрузке получателей: ${e.message}';
        _allRecipients = [];
        _visibleRecipients = [];
      });
    } catch (e) {
      setState(() {
        _recipientsError = 'Ошибка при загрузке получателей: ${e.toString()}';
        _allRecipients = [];
        _visibleRecipients = [];
      });
    } finally {
      setState(() {
        _recipientsLoading = false;
      });
    }
  }

  // Показываем modal sheet со списком и поиском
  Future<void> _openRecipientPicker() async {
    if (_recipientsLoading) return;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return RecipientPickerSheet(
          recipients: _visibleRecipients,
        );
      },
    );

    if (selected != null && selected.containsKey('telegram_username')) {
      _toCtrl.text = selected['telegram_username'] as String;
    }
  }

  // Обновлённый _transfer: вызываем RPC, парсим ответ и обновляем локальный баланс.
  Future<void> _transfer() async {
    setState(() => _error = null);

    if (!_formKey.currentState!.validate()) return;

    final toUsername = _toCtrl.text.trim();
    final amountValue = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (amountValue == null) {
      setState(() => _error = 'Неверный формат суммы');
      return;
    }
    final amount = amountValue;

    if (amount <= 0) {
      setState(() => _error = 'Сумма должна быть больше нуля');
      return;
    }

    if (amount > widget.user.vBalance) {
      setState(() => _error = 'Недостаточно средств');
      return;
    }

    setState(() => _loading = true);
    try {
      final dynamic rpcRes = await supabase.rpc('transfer_v_points', params: {
        'from_user': widget.user.id,
        'to_username': toUsername,
        'amount': amount,
      });

      // Попробуем извлечь from_balance из ответа RPC
      Map<String, dynamic>? parsed;
      if (rpcRes is Map<String, dynamic>) {
        parsed = rpcRes;
      } else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
        parsed = Map<String, dynamic>.from(rpcRes[0] as Map);
      } else {
        parsed = null;
      }

      if (parsed != null && parsed.containsKey('from_balance')) {
        final fb = parsed['from_balance'];
        if (fb is num) {
          widget.user.vBalance = (fb as num).toDouble();
        }
      } else {
        // Если RPC не вернул балансы — ре-fetchим профиль отправителя
        final profile = await supabase
            .from('user_credentials')
            .select('v_balance, m_balance')
            .eq('id', widget.user.id)
            .maybeSingle();

        if (profile is Map<String, dynamic>) {
          final v = profile['v_balance'];
          final m = profile['m_balance'];
          if (v is num) widget.user.vBalance = (v as num).toDouble();
          if (m is num) widget.user.mBalance = (m as num).toDouble();
        }
      }

      // Успех — закрываем экран и передаём true
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.message ?? e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String? _validateRecipient(String? v) {
    if (v == null || v.trim().isEmpty) return 'Выберите получателя';
    if (v.contains('@')) return 'Укажите username без @';
    return null;
  }

  String? _validateAmount(String? v) {
    if (v == null || v.isEmpty) return 'Введите сумму';
    final n = double.tryParse(v.replaceAll(',', '.'));
    if (n == null || n <= 0) return 'Некорректная сумма';
    if (n > widget.user.vBalance) return 'Сумма превышает ваш баланс';
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
            GestureDetector(
              onTap: _openRecipientPicker,
              child: AbsorbPointer(
                child: TextFormField(
                  controller: _toCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Получатель (telegram username)',
                    suffixIcon: Icon(Icons.expand_more),
                  ),
                  validator: _validateRecipient,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Количество V'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: _validateAmount,
            ),
            const SizedBox(height: 12),
            if (_recipientsLoading) const LinearProgressIndicator(),
            if (_recipientsError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_recipientsError, style: const TextStyle(color: Colors.red)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _transfer,
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Перевести'),
              ),
            ),
          ]),
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
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(widget.recipients);
      } else {
        _filtered = widget.recipients.where((row) {
          final username = (row['telegram_username'] ?? '').toString().toLowerCase();
          final first = (row['first_name'] ?? '').toString().toLowerCase();
          final last = (row['last_name'] ?? '').toString().toLowerCase();
          return username.contains(q) || first.contains(q) || last.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Поиск по username, имени или фамилии',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      FocusScope.of(context).unfocus();
                    },
                    child: const Text('Очистить'),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(child: Text('Ничего не найдено', style: theme.textTheme.bodyLarge))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final row = _filtered[index];
                        final username = row['telegram_username'] ?? '';
                        final first = row['first_name'] ?? '';
                        final last = row['last_name'] ?? '';
                        return ListTile(
                          title: Text('$first $last'.trim().isEmpty ? '@$username' : '$first $last'),
                          subtitle: Text('@$username'),
                          onTap: () {
                            Navigator.of(context).pop(row);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
