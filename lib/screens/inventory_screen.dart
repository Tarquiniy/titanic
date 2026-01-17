// lib/screens/inventory_screen.dart
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
import '../services/game_service.dart';

class InventoryScreen extends StatefulWidget {
  final AppUser user;
  const InventoryScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final supabase = Supabase.instance.client;
  final GameService _svc = GameService();

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
    if (inv is String) {
      try {
        decoded = jsonDecode(inv);
      } catch (_) {
        decoded = null;
      }
    }

    if (decoded == null) return out;

    if (decoded is Map) {
      decoded.forEach((k, v) {
        final cnt = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
        out.add({k.toString(): cnt});
      });
      return out;
    }

    if (decoded is List) {
      for (final el in decoded) {
        if (el is Map) {
          // object with name/count or single-key map
          if (el.containsKey('name') && el.containsKey('count')) {
            final name = el['name']?.toString() ?? 'item';
            final cnt = (el['count'] is num) ? (el['count'] as num).toInt() : int.tryParse(el['count']?.toString() ?? '0') ?? 0;
            out.add({name: cnt});
          } else if (el.keys.length == 1) {
            final k = el.keys.first;
            final v = el[k];
            final cnt = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
            out.add({k.toString(): cnt});
          } else {
            // fallback: stringify whole map
            try {
              final nm = jsonEncode(el);
              out.add({nm: 1});
            } catch (_) {}
          }
        } else if (el is List && el.length >= 2) {
          final k = el[0]?.toString() ?? 'item';
          final v = el[1];
          final cnt = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
          out.add({k: cnt});
        } else {
          out.add({el.toString(): 1});
        }
      }
      return out;
    }

    // unknown format
    return out;
  }

  int _totalItemsCount() {
    int s = 0;
    for (final it in _itemsList) {
      final v = it.values.first;
      s += v;
    }
    return s;
  }

  Future<void> _openSellToPlayer(String itemName, int availableCount) async {
    // 1) load candidate buyers
    List<Map<String, dynamic>> players = [];
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name')
          .neq('id', widget.user.id)
          .order('first_name');
      if (res is List) players = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось загрузить список игроков: $e')));
      return;
    }

    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет доступных покупателей')));
      return;
    }

    // 2) pick buyer
    final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String q = '';
        List<Map<String, dynamic>> filtered = List.from(players);
        return StatefulBuilder(builder: (ctx2, setStateSheet) {
          void doFilter(String s) {
            q = s.trim().toLowerCase();
            if (q.isEmpty) {
              filtered = List.from(players);
            } else {
              filtered = players.where((p) {
                final fn = (p['first_name'] ?? '').toString().toLowerCase();
                final ln = (p['last_name'] ?? '').toString().toLowerCase();
                final un = (p['telegram_username'] ?? '').toString().toLowerCase();
                return fn.contains(q) || ln.contains(q) || un.contains(q);
              }).toList();
            }
            setStateSheet(() {});
          }

          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Поиск покупателя', prefixIcon: Icon(Icons.search)),
                      onChanged: doFilter,
                    ),
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Не найдено'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 0),
                            itemBuilder: (context, i) {
                              final p = filtered[i];
                              final first = (p['first_name'] ?? '').toString();
                              final last = (p['last_name'] ?? '').toString();
                              final displayName = ('$first $last').trim().isEmpty ? (p['telegram_username'] ?? 'Без имени') : '$first $last';
                              return ListTile(
                                title: Text(displayName),
                                subtitle: Text(p['telegram_username']?.toString() ?? ''),
                                onTap: () => Navigator.of(context).pop(p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (chosen == null) return;

    // 3) ask quantity and price
    final qtyCtrl = TextEditingController(text: availableCount > 0 ? '1' : '1');
    final priceCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Продать "$itemName" игроку'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (availableCount > 0) Text('Доступно: $availableCount'),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Количество'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена за единицу (V)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Продать')),
            ],
          );
        });

    try {
      qtyCtrl.dispose();
      // don't dispose priceCtrl yet in case needed below
    } catch (_) {}

    if (confirmed != true) {
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    final qtyRaw = qtyCtrl.text.trim();
    final priceRaw = priceCtrl.text.trim().replaceAll(',', '.');

    final qty = int.tryParse(qtyRaw) ?? 0;
    final price = double.tryParse(priceRaw) ?? 0.0;

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректное количество')));
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }
    if (availableCount > 0 && qty > availableCount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Количество больше доступного')));
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную цену')));
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    // 4) perform RPC call
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final rpcRes = await _svc.rpcSellItemToUser(
        fromUserId: widget.user.id,
        toUserId: chosen['id'].toString(),
        itemName: itemName,
        quantity: qty,
        price: price,
      );

      // try to update local balances if RPC returned them
      try {
        Map<String, dynamic>? parsed;
        if (rpcRes is Map<String, dynamic>) parsed = rpcRes;
        else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) parsed = Map<String, dynamic>.from(rpcRes[0] as Map);

        if (parsed != null && parsed.containsKey('from_balance')) {
          final fb = parsed['from_balance'];
          if (fb is num) widget.user.vBalance = (fb).toDouble();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(); // close progress

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Продажа завершена')));
      await _loadInventory();
      // optionally refresh profile to reflect balance changes
      final profile = await _svc.fetchUserProfile(widget.user.id);
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        if (v is num) widget.user.vBalance = (v).toDouble();
        if (m is num) widget.user.mBalance = (m).toDouble();
        setState(() {});
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при продаже: $msg')));
    } finally {
      try {
        priceCtrl.dispose();
      } catch (_) {}
    }
  }

  Future<void> _openSellToBank(String itemName, int availableCount) async {
    final qtyCtrl = TextEditingController(text: availableCount > 0 ? '1' : '1');
    final priceCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Продать "$itemName" в Банк'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (availableCount > 0) Text('Доступно: $availableCount'),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Количество'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена за единицу (M)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Продать')),
            ],
          );
        });

    if (confirmed != true) {
      try {
        qtyCtrl.dispose();
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректное количество')));
      return;
    }
    if (availableCount > 0 && qty > availableCount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Количество больше доступного')));
      return;
    }
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную цену')));
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final rpcRes = await _svc.rpcSellItemToBank(
        userId: widget.user.id,
        itemName: itemName,
        quantity: qty,
        price: price,
      );

      // update balances if RPC returned them
      try {
        Map<String, dynamic>? parsed;
        if (rpcRes is Map<String, dynamic>) parsed = rpcRes;
        else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) parsed = Map<String, dynamic>.from(rpcRes[0] as Map);

        if (parsed != null && parsed.containsKey('user_balance')) {
          final ub = parsed['user_balance'];
          if (ub is num) widget.user.mBalance = (ub).toDouble();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop(); // close progress
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предмет продан в банк')));
      await _loadInventory();

      final profile = await _svc.fetchUserProfile(widget.user.id);
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        if (v is num) widget.user.vBalance = (v).toDouble();
        if (m is num) widget.user.mBalance = (m).toDouble();
        setState(() {});
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при продаже в банк: $msg')));
    }
  }

  Widget _buildItemRow(Map<String, int> itemMap) {
    final name = itemMap.keys.first;
    final count = itemMap.values.first;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(name),
        subtitle: Text('Количество: $count'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'sell_player') {
              await _openSellToPlayer(name, count);
            } else if (v == 'sell_bank') {
              await _openSellToBank(name, count);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'sell_player', child: Text('Продать игроку')),
            const PopupMenuItem(value: 'sell_bank', child: Text('Продать в Банк')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвентарь'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInventory),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInventory,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : _itemsList.isEmpty
                      ? const Center(child: Text('Инвентарь пуст'))
                      : Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                itemCount: _itemsList.length,
                                separatorBuilder: (_, __) => const Divider(height: 0),
                                itemBuilder: (context, i) => _buildItemRow(_itemsList[i]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Итого', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text('${_totalItemsCount()}'),
                                ],
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }
}
