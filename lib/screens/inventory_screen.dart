// lib/screens/inventory_screen.dart
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
  final GameService svc = GameService();

  bool loading = false;
  String? error;

  // items list: {label:String, voices:int, raw:any, id:String?}
  List<Map<String, dynamic>> itemsList = [];

  // incoming offers for buyer
  List<Map<String, dynamic>> incomingOffers = [];
  bool loadingOffers = false;

  @override
  void initState() {
    super.initState();
    loadInventory();
    fetchIncomingOffers();
  }

  Future<void> loadInventory() async {
    setState(() {
      loading = true;
      error = null;
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

      final parsed = parseInventoryToList(inv);
      setState(() => itemsList = parsed);
    } on PostgrestException catch (e) {
      setState(() {
        error = e.message;
        itemsList = [];
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        itemsList = [];
      });
    } finally {
      setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> parseInventoryToList(dynamic inv) {
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
          final String? id = el.containsKey('id') ? el['id']?.toString() : null;

          final String name = el.containsKey('name')
              ? (el['name']?.toString() ?? (id ?? 'item'))
              : (id ?? (el.keys.length == 1 ? el.keys.first.toString() : jsonEncode(el)));

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
          } else if (el.keys.length == 1) {
            final k = el.keys.first;
            final v = el[k];
            voices = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
          } else {
            voices = 0;
          }

          out.add({'label': name, 'voices': voices, 'raw': el, 'id': id});
        } else if (el is List && el.length == 2) {
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

  int totalVoicesSum() {
    int s = 0;
    for (final it in itemsList) {
      final v = (it['voices'] is num) ? (it['voices'] as num).toInt() : 0;
      s += v;
    }
    return s;
  }

  // ---------- SELL TO PLAYER ----------
  Future<void> openSellToPlayer(Map<String, dynamic> item) async {
    final itemLabel = item['label']?.toString() ?? 'item';
    final itemId = item['id']?.toString();

    List<Map<String, dynamic>> players = [];
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name')
          .neq('id', widget.user.id)
          .order('first_name');

      if (res is List) {
        players = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки игроков: $e')));
      return;
    }

    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет игроков для продажи')));
      return;
    }

    final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String q = '';
        List<Map<String, dynamic>> filtered = List.from(players);

        return StatefulBuilder(
          builder: (ctx2, setStateSheet) {
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
                        decoration: const InputDecoration(
                          hintText: 'Поиск игрока',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: doFilter,
                      ),
                    ),
                    const Divider(height: 0),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Ничего не найдено'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (context, i) {
                                final p = filtered[i];
                                final first = (p['first_name'] ?? '').toString();
                                final last = (p['last_name'] ?? '').toString();
                                final displayName = (first + ' ' + last).trim().isEmpty
                                    ? (p['telegram_username'] ?? '—').toString()
                                    : (first + ' ' + last).trim();

                                return ListTile(
                                  title: Text(displayName),
                                  subtitle: Text((p['telegram_username'] ?? '').toString()),
                                  onTap: () => Navigator.of(context).pop(p),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (chosen == null) return;

    final priceCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(itemLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Количество/вес: ${(item['voices'] ?? 0).toString()}'),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Цена (V)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Продать')),
        ],
      ),
    );

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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final params = {
        'p_from': widget.user.id,
        'p_to': chosen['id'].toString(),
        'p_item_id': itemId ?? itemLabel,
        'p_price': price,
      };

      await supabase.rpc('create_item_offer', params: params);

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер отправлен')));

      await loadInventory();
      await fetchIncomingOffers();

      final profile = await svc.fetchUserProfile(widget.user.id);
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        if (v is num) widget.user.vBalance = v.toDouble();
        if (m is num) widget.user.mBalance = m.toDouble();
        setState(() {});
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      try {
        priceCtrl.dispose();
      } catch (_) {}
    }
  }

  // ---------- SELL TO BANK ----------
  Future<void> openSellToBank(Map<String, dynamic> item) async {
    final itemLabel = item['label']?.toString() ?? 'item';
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(itemLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Количество/вес: ${(item['voices'] ?? 0).toString()}'),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Количество (>=1)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Цена (M)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Продать')),
        ],
      ),
    );

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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final rpcRes = await svc.rpcSellItemToBank(
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
          if (ub is num) widget.user.mBalance = ub.toDouble();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Продано в банк')));

      await loadInventory();

      final profile = await svc.fetchUserProfile(widget.user.id);
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        if (v is num) widget.user.vBalance = v.toDouble();
        if (m is num) widget.user.mBalance = m.toDouble();
        setState(() {});
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      try {
        qtyCtrl.dispose();
        priceCtrl.dispose();
      } catch (_) {}
    }
  }

  // ---------- INCOMING OFFERS (buyer) ----------
  Future<void> fetchIncomingOffers() async {
    setState(() => loadingOffers = true);
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
      setState(() => incomingOffers = offers);
    } catch (_) {
      // ignore
    } finally {
      setState(() => loadingOffers = false);
    }
  }

  Future<void> acceptOffer(int offerId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ВАЖНО: правильные имена параметров с подчёркиваниями
      await supabase.rpc('accept_item_offer', params: {
        'p_offer_id': offerId,
        'p_buyer_id': widget.user.id,
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер принят')));

      await loadInventory();
      await fetchIncomingOffers();

      final profile = await svc.fetchUserProfile(widget.user.id);
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        if (v is num) widget.user.vBalance = v.toDouble();
        if (m is num) widget.user.mBalance = m.toDouble();
        setState(() {});
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> rejectOffer(int offerId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отклонить оффер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Причина (необязательно):'),
            TextField(controller: reasonCtrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Отклонить')),
        ],
      ),
    );

    if (confirmed != true) {
      try {
        reasonCtrl.dispose();
      } catch (_) {}
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ВАЖНО: правильные имена параметров с подчёркиваниями
      await supabase.rpc('reject_item_offer', params: {
        'p_offer_id': offerId,
        'p_buyer_id': widget.user.id,
        'p_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оффер отклонён')));

      await loadInventory();
      await fetchIncomingOffers();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      try {
        reasonCtrl.dispose();
      } catch (_) {}
    }
  }

  Widget buildItemRow(Map<String, dynamic> item) {
    final name = item['label']?.toString() ?? 'item';
    final voices = (item['voices'] is num) ? (item['voices'] as num).toInt() : 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(name),
        subtitle: Text('V: $voices'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'sell_player') {
              await openSellToPlayer(item);
            } else if (v == 'sell_bank') {
              await openSellToBank(item);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'sell_player', child: Text('Продать игроку')),
            PopupMenuItem(value: 'sell_bank', child: Text('Продать в банк')),
          ],
        ),
      ),
    );
  }

  Widget buildOffersList() {
    if (loadingOffers) return const Center(child: CircularProgressIndicator());
    if (incomingOffers.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.yellow.shade50,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text('Входящие офферы: ${incomingOffers.length}'),
        children: incomingOffers.map((o) {
          final offerId = (o['id'] is int) ? (o['id'] as int) : int.tryParse(o['id']?.toString() ?? '') ?? 0;
          final seller = o['seller_id']?.toString() ?? '';
          final price = o['price']?.toString() ?? '';
          final itemJson = o['item_json'];

          String itemLabel;
          int itemVoices = 0;

          try {
            if (itemJson is Map) {
              itemLabel = itemJson['name']?.toString() ?? itemJson['id']?.toString() ?? jsonEncode(itemJson);
              if (itemJson.containsKey('voices')) {
                final vv = itemJson['voices'];
                itemVoices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
              } else if (itemJson.containsKey('count')) {
                final vv = itemJson['count'];
                itemVoices = (vv is num) ? vv.toInt() : int.tryParse(vv?.toString() ?? '0') ?? 0;
              } else {
                itemVoices = 0;
              }
            } else {
              itemLabel = itemJson?.toString() ?? '';
            }
          } catch (_) {
            itemLabel = itemJson?.toString() ?? '';
          }

          return ListTile(
            title: Text(itemLabel),
            subtitle: Text('V:$itemVoices  Цена:$price  От:$seller'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => rejectOffer(offerId), child: const Text('Отклонить')),
                ElevatedButton(onPressed: () => acceptOffer(offerId), child: const Text('Принять')),
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
              await loadInventory();
              await fetchIncomingOffers();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await loadInventory();
          await fetchIncomingOffers();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : (error != null)
                  ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
                  : itemsList.isEmpty
                      ? Column(
                          children: [
                            buildOffersList(),
                            const Expanded(child: Center(child: Text('Инвентарь пуст'))),
                          ],
                        )
                      : Column(
                          children: [
                            buildOffersList(),
                            Expanded(
                              child: ListView.separated(
                                itemCount: itemsList.length,
                                separatorBuilder: (_, __) => const Divider(height: 0),
                                itemBuilder: (context, i) => buildItemRow(itemsList[i]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Сумма V:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(totalVoicesSum().toString()),
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
