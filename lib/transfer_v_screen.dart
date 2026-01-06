// lib/transfer_v_screen.dart
//
// Экран для перевода V-поинтов между пользователями.
// Изменения: убраны упоминания "username" в UI — вместо этого показываются
// имена пользователей; внутренняя логика по-прежнему хранит telegram_username
// в выбранном получателе и использует его при RPC-вызове.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'models/app_user.dart';

// Helpers: convert server timestamptz (ISO8601 or DateTime) to YEKT (Asia/Yekaterinburg) and format.
String formatToYekaterinburg(dynamic ts) {
  if (ts == null) return '';
  DateTime dt;
  if (ts is DateTime) {
    dt = ts.toUtc();
  } else {
    dt = DateTime.tryParse(ts.toString()) ?? DateTime.parse(ts.toString());
    dt = dt.toUtc();
  }
  final ye = dt.add(const Duration(hours: 5)); // YEKT = UTC+5
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(ye);
}

class TransferVScreen extends StatefulWidget {
  final AppUser user;
  const TransferVScreen({Key? key, required this.user}) : super(key: key);

  @override
  _TransferVScreenState createState() => _TransferVScreenState();
}

class _TransferVScreenState extends State<TransferVScreen> {
  final supabase = Supabase.instance.client;

  bool _loading = false;
  String _error = '';

  // recipients
  bool _recipientsLoading = false;
  String _recipientsError = '';
  List<Map<String, dynamic>> _allRecipients = [];
  List<Map<String, dynamic>> _visibleRecipients = [];
  Map<String, dynamic>? _selectedRecipient;

  // controller
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    setState(() {
      _recipientsLoading = true;
      _recipientsError = '';
    });

    try {
      // Запрашиваем всех пользователей, кроме текущего отправителя,
      // и всегда исключаем пользователей с ролью 'politician'
      final dynamic res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name, role')
          .neq('id', widget.user.id)
          .neq('role', 'politician')
          .order('first_name'); // сортируем по имени для удобства

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

      setState(() {
        _allRecipients = list;
        _visibleRecipients = List<Map<String, dynamic>>.from(list);
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

    final Map<String, dynamic>? selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return RecipientPickerSheet(recipients: _visibleRecipients);
      },
    );

    if (selected != null) {
      // Запоминаем выбранного получателя и показываем его display name в поле
      _selectedRecipient = selected;
      final first = (selected['first_name'] ?? '').toString();
      final last = (selected['last_name'] ?? '').toString();
      final display = (first + ' ' + last).trim();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _submitTransfer() async {
    final to = _selectedRecipient;
    if (to == null) {
      setState(() => _error = 'Выберите получателя');
      return;
    }

    final toUsername = (to['telegram_username'] ?? '').toString();
    final amountRaw = _amountController.text.trim();
    if (amountRaw.isEmpty) {
      setState(() => _error = 'Введите сумму');
      return;
    }

    final amountValue = double.tryParse(amountRaw.replaceAll(',', '.'));
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

      // Normalize created_at returned by RPC to YEKT formatted string (if present)
      if (parsed != null && parsed.containsKey('created_at')) {
        try {
          final createdRaw = parsed['created_at'];
          parsed['created_at_yekat'] = formatToYekaterinburg(createdRaw);
        } catch (_) {
          parsed['created_at_yekat'] = '';
        }
      }

      if (parsed != null && parsed.containsKey('from_balance')) {
        final fb = parsed['from_balance'];
        if (fb is num) widget.user.vBalance = (fb as num).toDouble();
      } else {
        // Если RPC не вернул балансы — ре-fetchим профиль отправителя
        final profile = await supabase
            .from('user_credentials')
            .select('v_balance')
            .eq('id', widget.user.id)
            .maybeSingle();
        if (profile is Map<String, dynamic>) {
          final vbal = profile['v_balance'];
          if (vbal is num) widget.user.vBalance = (vbal as num).toDouble();
        }
      }

      // Очистим форму и покажем успех
      _amountController.clear();
      _noteController.clear();
      _selectedRecipient = null;
      setState(() {
        _error = '';
      });

      // Показываем уведомление с локальным временем (если RPC вернул created_at_yekat)
      String message = 'Перевод выполнен';
      if (parsed != null && parsed.containsKey('created_at_yekat')) {
        final cat = parsed['created_at_yekat'] ?? '';
        if (cat is String && cat.isNotEmpty) {
          message = 'Перевод выполнен: $cat (YEKT)';
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Ошибка при переводе: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка при переводе: ${e.toString()}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.user.firstName;
    final last = widget.user.lastName;
    return Scaffold(
      appBar: AppBar(
        title: Text('Перевести V/M'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Пользователь: ${first} ${last}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Сумма'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Примечание (необязательно)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _openRecipientPicker,
              child: Text(_selectedRecipient == null
                  ? 'Выбрать получателя'
                  : '${(_selectedRecipient?['first_name'] ?? '')} ${(_selectedRecipient?['last_name'] ?? '')}'),
            ),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _submitTransfer,
              child: _loading ? const CircularProgressIndicator() : const Text('Отправить'),
            ),
          ],
        ),
      ),
    );
  }
}

class RecipientPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> recipients;
  const RecipientPickerSheet({Key? key, required this.recipients}) : super(key: key);

  @override
  _RecipientPickerSheetState createState() => _RecipientPickerSheetState();
}

class _RecipientPickerSheetState extends State<RecipientPickerSheet> {
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.recipients;
  }

  void _onSearchChanged() {
    final q = _q.text.toLowerCase();
    setState(() {
      _filtered = widget.recipients.where((r) {
        final fn = (r['first_name'] ?? '').toString().toLowerCase();
        final ln = (r['last_name'] ?? '').toString().toLowerCase();
        final un = (r['telegram_username'] ?? '').toString().toLowerCase();
        return fn.contains(q) || ln.contains(q) || un.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _q,
                onChanged: (_) => _onSearchChanged(),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (_, idx) {
                  final r = _filtered[idx];
                  final display = ('${r['first_name'] ?? ''} ${r['last_name'] ?? ''}').trim();
                  return ListTile(
                    title: Text(display.isEmpty ? (r['telegram_username'] ?? '') : display),
                    subtitle: Text(r['telegram_username'] ?? ''),
                    onTap: () => Navigator.of(context).pop(r),
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
