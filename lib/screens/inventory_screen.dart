// lib/inventory_screen.dart
//
// Экран "Инвентарь" — показывает список предметов пользователя и их количества,
// а также строку "Итого" с суммой всех чисел предметов.
// Поддерживаются форматы:
//  - объект: { "sword": 3, "shield": 1 }  -> отображается как по одной строке на каждый ключ
//  - массив одноключевых объектов: [ { "Дополнительный ход": 0 }, { "Дополнительный ход": 0 } ]
//    -> каждый элемент массива отображается как отдельная строка (важно для множества "Дополнительный ход")
//  - массив объектов: [ { "name":"sword", "count":3 }, ... ] -> каждый такой элемент отдельная строка
//  - массив пар: [ ["sword",3], ... ] -> тоже поддерживается
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class InventoryScreen extends StatefulWidget {
  final AppUser user;
  const InventoryScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final supabase = Supabase.instance.client;

  bool _loading = false;
  String? _error;

  // Храним список элементов; каждый элемент — Map<String,int> с ровно одной парой {name: count}
  List<Map<String, int>> _itemsList = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dynamic res = await supabase
          .from('user_credentials')
          .select('inventory')
          .eq('id', widget.user.id)
          .maybeSingle();

      dynamic inv;
      if (res == null) {
        inv = null;
      } else if (res is Map<String, dynamic>) {
        inv = res['inventory'];
      } else {
        inv = null;
      }

      final parsed = _parseInventoryToList(inv);
      setState(() {
        _itemsList = parsed;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Ошибка загрузки инвентаря: ${e.message}';
        _itemsList = [];
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки инвентаря: ${e.toString()}';
        _itemsList = [];
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // Парсер: любой допустимый формат -> список одноэлементных maps [{name:count}, ...]
  List<Map<String, int>> _parseInventoryToList(dynamic inv) {
    final List<Map<String, int>> out = [];
    if (inv == null) return out;

    dynamic decoded = inv;

    // Если inv — строка, пытаемся распарсить JSON
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return out;
      }
    }

    // Если это объект/Map: превращаем каждый ключ в один элемент списка
    if (decoded is Map) {
      decoded.forEach((key, value) {
        try {
          final name = key?.toString() ?? '';
          if (name.isEmpty) return;
          final count = _toInt(value) ?? 0;
          out.add({name: count});
        } catch (_) {}
      });
      return out;
    }

    // Если это список — обрабатываем элементы по-элементно
    if (decoded is List) {
      for (final el in decoded) {
        try {
          if (el is Map) {
            // Вариант: { "name": "...", "count": N }
            if (el.containsKey('name')) {
              final name = (el['name'] ?? '').toString();
              if (name.isEmpty) continue;
              final count = _toInt(el['count'] ?? el['qty'] ?? el['value']) ?? 0;
              out.add({name: count});
              continue;
            }

            // Вариант: одноключевой объект { "Дополнительный ход": 0 }
            if (el.keys.isNotEmpty) {
              final firstKey = el.keys.first.toString();
              final firstVal = el[firstKey];
              final count = _toInt(firstVal) ?? 0;
              out.add({firstKey: count});
              continue;
            }

            // Пустой объект — пропускаем
            continue;
          } else if (el is List && el.length >= 2) {
            // Вариант: ["name", count]
            final name = el[0].toString();
            final count = _toInt(el[1]) ?? 0;
            if (name.isNotEmpty) {
              out.add({name: count});
            }
            continue;
          } else {
            // Нестандартный элемент — попробуем интерпретировать как строковое имя с count 0
            final s = el?.toString() ?? '';
            if (s.isNotEmpty) {
              out.add({s: 0});
            }
            continue;
          }
        } catch (_) {
          // malformed element — пропускаем
          continue;
        }
      }
      return out;
    }

    // Неизвестный формат — ничего не делаем
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

  // Итого — сумма всех count в списке
  int get _total {
    int sum = 0;
    for (final m in _itemsList) {
      if (m.isEmpty) continue;
      final val = m.values.first;
      sum += val;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвентарь'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadInventory,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInventory,
        child: _loading
            ? ListView(
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

    // Для красоты сортируем: сначала агрегированные (если есть), но сохраняем порядок появления.
    // Поскольку у нас список элементов, просто отображаем в порядке _itemsList.
    final items = _itemsList;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length + 1, // +1 для строки "Итого"
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

        final entry = items[index - 1];
        final name = entry.keys.first;
        final count = entry.values.first;

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
