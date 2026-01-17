// lib/screens/inventory_screen.dart
//
// Экран "Инвентарь" — адаптирован под модель, где число рядом с предметом
// — это не количество предметов, а количество войсов (V), которое предмет даст
// пользователю.
//
// Убрано поле "Истекает". RPC-вызовы выполняются через named parameter `params:`.
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

  // Каждый элемент: {
  //   'label': String,
  //   'voices': int,
  //   'raw': dynamic,
  //   'id': String? 
  // }
  List<Map<String, dynamic>> _itemsList = [];

  // входящие офферы для текущего пользователя (buyer)
  List<Map<String, dynamic>> _incomingOffers = [];
  bool _loadingOffers = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _fetchIncomingOffers();
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

  // Парсер: нормализует разные форматы инвентаря в List<Map<String,dynamic>>
  List<Map<String, dynamic>> _parseInventoryToList(dynamic inv) {
    final List<Map<String, dynamic>> out = [];
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
        final voices = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
        out.add({'label': k.toString(), 'voices': voices, 'raw': {k: v}, 'id': null});
      });
      return out;
    }

    if (decoded is List) {
      for (final el in decoded) {
        if (el is Map) {
          final String? id = el.containsKey('id') ? (el['id']?.toString()) : null;
          final String name = el.containsKey('name')
              ? el['name']?.toString() ?? id ?? 'item'
              : (el.keys.length == 1 ? el.keys.first.toString() : jsonEncode(el));
          int voices = 0;
          if (el.containsKey('voices')) {
            final vv = el['voices'];
            voices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
          } else if (el.containsKey('v')) {
            final vv = el['v'];
            voices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
          } else if (el.containsKey('count')) {
            final vv = el['count'];
            voices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
          } else if (el.containsKey('amount')) {
            final vv = el['amount'];
            voices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
          } else {
            if (el.keys.length == 1) {
              final k = el.keys.first;
              final v = el[k];
              voices = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
            } else {
              voices = 0;
            }
          }
          out.add({'label': name, 'voices': voices, 'raw': el, 'id': id});
        } else if (el is List && el.length >= 2) {
          final name = el[0]?.toString() ?? 'item';
          final v = el[1];
          final voices = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
          out.add({'label': name, 'voices': voices, 'raw': el, 'id': null});
        } else {
          out.add({'label': el.toString(), 'voices': 1, 'raw': el, 'id': null});
        }
      }
      return out;
    }

    return out;
  }

  int _totalVoicesSum() {
    int s = 0;
    for (final it in _itemsList) {
      final v = (it['voices'] is num) ? (it['voices'] as num).toInt() : 0;
      s += v;
    }
    return s;
  }

  // ---------- SELL TO PLAYER (создание оффера) ----------
  Future<void> _openSellToPlayer(Map<String, dynamic> item) async {
    final itemLabel = item['label']?.toString() ?? 'item';
    final itemId = item['id']?.toString();
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

    final priceCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Создать оффер: "$itemLabel"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Войсы: ${item['voices'] ?? 0}'),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена (войсы, V)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отправить оффер')),
            ],
          );
        });

    if (confirmed != true) {
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную цену')));
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final params = {
        'p_from': widget.user.id,
        'p_to': chosen['id'].toString(),
        'p_item_id': itemId ?? itemLabel,
        'p_price': price
      };

      await supabase.rpc('create_item_offer', params: params);

      if (!mounted) return;
      Navigator.of(context).pop(); // close progress

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер отправлен покупателю')));

      await _loadInventory();
      await _fetchIncomingOffers();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при создании оффера: $msg')));
    } finally {
      try {
        priceCtrl.dispose();
      } catch (_) {}
    }
  }

  // ---------- SELL TO BANK ----------
  Future<void> _openSellToBank(Map<String, dynamic> item) async {
    final itemLabel = item['label']?.toString() ?? 'item';
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('Продать "$itemLabel" в Банк'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Войсы: ${item['voices'] ?? 0}'),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Количество (обычно 1)'),
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
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректную цену')));
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final rpcRes = await _svc.rpcSellItemToBank(
        userId: widget.user.id,
        itemName: item['label']?.toString() ?? '',
        quantity: qty,
        price: price,
      );

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
      Navigator.of(context).pop();
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

  // ---------- INCOMING OFFERS (buyer) ----------
  Future<void> _fetchIncomingOffers() async {
    setState(() {
      _loadingOffers = true;
    });
    try {
      final res = await supabase
          .from('item_offers')
          .select('id, seller_id, buyer_id, item_json, price, created_at')
          .eq('status', 'pending')
          .eq('buyer_id', widget.user.id);
      final List<Map<String, dynamic>> offers = [];
      if (res is List) {
        for (final r in res) {
          offers.add(Map<String, dynamic>.from(r as Map));
        }
      }
      setState(() {
        _incomingOffers = offers;
      });
    } catch (e) {
      // ignore
    } finally {
      setState(() {
        _loadingOffers = false;
      });
    }
  }

  Future<void> _acceptOffer(int offerId) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await supabase.rpc('accept_item_offer', params: {'p_offer_id': offerId, 'p_buyer_id': widget.user.id});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер принят — предмет добавлен в инвентарь')));
      await _loadInventory();
      await _fetchIncomingOffers();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при принятии оффера: $msg')));
    }
  }

  Future<void> _rejectOffer(int offerId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Отклонить оффер'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Укажите причину (необязательно):'),
                TextField(controller: reasonCtrl),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отклонить')),
            ],
          );
        });

    if (confirmed != true) {
      try {
        reasonCtrl.dispose();
      } catch (_) {}
      return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      await supabase.rpc('reject_item_offer', params: {'p_offer_id': offerId, 'p_buyer_id': widget.user.id, 'p_reason': reasonCtrl.text});
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер отклонён — предмет возвращён продавцу')));
      await _loadInventory();
      await _fetchIncomingOffers();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при отклонении оффера: $msg')));
    } finally {
      try {
        reasonCtrl.dispose();
      } catch (_) {}
    }
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final name = item['label']?.toString() ?? 'item';
    final voices = (item['voices'] is num) ? (item['voices'] as num).toInt() : 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(name),
        subtitle: Text('Войсы: $voices'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'sell_player') {
              await _openSellToPlayer(item);
            } else if (v == 'sell_bank') {
              await _openSellToBank(item);
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

  Widget _buildOffersList() {
    if (_loadingOffers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_incomingOffers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Colors.yellow.shade50,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text('Входящие офферы (${_incomingOffers.length})'),
        children: _incomingOffers.map((o) {
          final offerId = (o['id'] is int) ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '') ?? 0;
          final seller = o['seller_id']?.toString() ?? '';
          final price = o['price']?.toString() ?? '';
          final itemJson = o['item_json'];
          String itemLabel = '';
          int itemVoices = 0;
          try {
            if (itemJson is Map) {
              itemLabel = (itemJson['name']?.toString() ?? itemJson['id']?.toString() ?? jsonEncode(itemJson));
              if (itemJson.containsKey('voices')) {
                final vv = itemJson['voices'];
                itemVoices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
              } else if (itemJson.containsKey('count')) {
                final vv = itemJson['count'];
                itemVoices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
              }
            } else {
              itemLabel = itemJson?.toString() ?? '';
            }
          } catch (_) {
            itemLabel = itemJson?.toString() ?? '';
          }

          return ListTile(
            title: Text(itemLabel),
            subtitle: Text('Войсы: $itemVoices · Цена: $price · От: $seller'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => _rejectOffer(offerId), child: const Text('Отклонить')),
                ElevatedButton(onPressed: () => _acceptOffer(offerId), child: const Text('Принять')),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инвентарь'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadInventory();
              await _fetchIncomingOffers();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadInventory();
          await _fetchIncomingOffers();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : _itemsList.isEmpty
                      ? Column(
                          children: [
                            _buildOffersList(),
                            const Expanded(child: Center(child: Text('Инвентарь пуст'))),
                          ],
                        )
                      : Column(
                          children: [
                            _buildOffersList(),
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
                                  const Text('Итого (сумма войсов)', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text('${_totalVoicesSum()}'),
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
