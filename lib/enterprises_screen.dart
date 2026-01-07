
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';

class EnterprisesScreen extends StatefulWidget {
  final AppUser user;
  const EnterprisesScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<EnterprisesScreen> createState() => _EnterprisesScreenState();
}

class _EnterprisesScreenState extends State<EnterprisesScreen> {
  final supabase = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  Map<String, int> _enterprises = {}; 

  @override
  void initState() {
    super.initState();
    _loadEnterprises();
  }

  Future<void> _loadEnterprises() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dynamic res = await supabase
          .from('user_credentials')
          .select('enterprises')
          .eq('id', widget.user.id)
          .maybeSingle();

      dynamic inv;
      if (res == null) {
        inv = null;
      } else if (res is Map<String, dynamic>) {
        inv = res['enterprises'];
      } else {
        // неожиданный формат результата — безопасно игнорируем
        inv = null;
      }

      final parsed = _parseEnterprises(inv);
      setState(() {
        _enterprises = parsed;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Ошибка загрузки предприятий: ${e.message}';
        _enterprises = {};
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки предприятий: ${e.toString()}';
        _enterprises = {};
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Map<String, int> _parseEnterprises(dynamic inv) {
    final Map<String, int> out = {};
    if (inv == null) return out;

    dynamic decoded = inv;

    // Если inv — строка, пытаемся распарсить JSON
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        // невалидный JSON — возвращаем пустой
        return out;
      }
    }

    // Если это объект/Map: ключи — имена предприятий, значения — числа
    if (decoded is Map) {
      decoded.forEach((key, value) {
        try {
          final name = key?.toString() ?? '';
          if (name.isEmpty) return;
          final count = _toInt(value) ?? 0;
          out[name] = (out[name] ?? 0) + count;
        } catch (_) {}
      });
      return out;
    }

    // Если это список — ожидаем элементы с полями name и count
    if (decoded is List) {
      for (final el in decoded) {
        if (el is Map) {
          final name = (el['name'] ?? el['enterprises'] ?? el['title'] ?? '').toString();
          if (name.isEmpty) continue;
          final count = _toInt(el['count'] ?? el['qty'] ?? el['value']) ?? 0;
          out[name] = (out[name] ?? 0) + count;
        } else if (el is List && el.length >= 2) {
          // опционально: массив пар [name, count]
          try {
            final name = el[0].toString();
            final count = _toInt(el[1]) ?? 0;
            if (name.isNotEmpty) {
              out[name] = (out[name] ?? 0) + count;
            }
          } catch (_) {}
        }
      }
      return out;
    }

    // Неизвестный формат
    return out;
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    final s = v.toString();
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    final parsedDouble = double.tryParse(s);
    if (parsedDouble != null) return parsedDouble.toInt();
    return null;
  }

  int get _total {
    int sum = 0;
    _enterprises.forEach((_, v) => sum += v);
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Предприятия'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadEnterprises,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEnterprises,
        child: _loading
            ? ListView(
                // чтобы RefreshIndicator работал корректно при загрузке, показываем пустой список с прогрессом
                children: const [
                  SizedBox(height: 24),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      );
    }

    final entries = _enterprises.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length + 1, // +1 для строки "Итого"
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Expanded(child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w600))),
                Text('+ $_total войсов', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }

        final entry = entries[index - 1];
        final name = entry.key;
        final count = entry.value;

        return Column(
          children: [
            ListTile(
              title: Text(name),
              trailing: Text('+ $count войсов', style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            const Divider(height: 0),
          ],
        );
      },
    );
  }
}
