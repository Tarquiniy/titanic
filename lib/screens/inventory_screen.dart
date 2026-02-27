// lib/screens/inventory_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../services/game_service.dart';
import '../theme/app_theme.dart';

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

  List<Map<String, dynamic>> _itemsList = [];
  List<Map<String, dynamic>> _incomingOffers = [];
  List<Map<String, dynamic>> _outgoingOffers = [];
  List<Map<String, dynamic>> _tradeHistory = [];
  bool _loadingOffers = false;
  final Map<String, String> _playerNames = {};
  RealtimeChannel? _offersChannel;

  // ✅ NEW: enterprises from user_credentials.enterprises (json/jsonb)
  List<Map<String, dynamic>> _enterprises = [];

  // ✅ Цвета (СЛОВА) -> реальные цвета (для кружка)
  static const List<String> _allowedColorWords = [
    'красный',
    'жёлтый',
    'синий',
    'малиновый',
    'зелёный',
  ];

  static final Map<String, Color> _wordToColor = {
    'красный': Colors.red,
    'жёлтый': Colors.amber,
    'синий': Colors.blue,
    'малиновый': Colors.pink,
    'зелёный': Colors.green,
  };

  // ✅ Backward compatibility: hex -> слово (если старые предприятия сохранены hex’ом)
  static final Map<String, String> _hexToWord = {
    '#F44336': 'красный',
    '#FFC107': 'жёлтый',
    '#2196F3': 'синий',
    '#E91E63': 'малиновый',
    '#4CAF50': 'зелёный',
  };

  @override
  void initState() {
    super.initState();
    _loadInventory();
    _refreshTradingData();
    _subscribeToOfferChanges();
  }

  @override
  void dispose() {
    try {
      _offersChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ NEW: select enterprises too
      final dynamic res = await supabase
          .from('user_credentials')
          .select('inventory, enterprises')
          .eq('id', widget.user.id)
          .maybeSingle();

      dynamic inv;
      dynamic enterprises;

      if (res == null) {
        inv = null;
        enterprises = null;
      } else if (res is Map<String, dynamic>) {
        inv = res['inventory'];
        enterprises = res['enterprises'];
      } else {
        inv = null;
        enterprises = null;
      }

      final parsedInv = _parseInventoryToList(inv);
      final parsedEnt = _parseEnterprisesToList(enterprises);

      setState(() {
        _itemsList = parsedInv;
        _enterprises = parsedEnt;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = 'Ошибка загрузки инвентаря: ${e.message}';
        _itemsList = [];
        _enterprises = [];
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки инвентаря: ${e.toString()}';
        _itemsList = [];
        _enterprises = [];
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

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

  // ✅ NEW: enterprises parser (json/jsonb or string)
  List<Map<String, dynamic>> _parseEnterprisesToList(dynamic enterprises) {
    final List<Map<String, dynamic>> out = [];
    if (enterprises == null) return out;

    dynamic decoded = enterprises;
    if (enterprises is String) {
      try {
        decoded = jsonDecode(enterprises);
      } catch (_) {
        decoded = null;
      }
    }

    if (decoded == null) return out;

    if (decoded is List) {
      for (final el in decoded) {
        if (el is Map) out.add(Map<String, dynamic>.from(el as Map));
      }
      return out;
    }

    if (decoded is Map) {
      out.add(Map<String, dynamic>.from(decoded as Map));
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

  // ✅ Нормализуем цвет предприятия в "слово"
  String _normalizeEnterpriseColorWord(dynamic rawColor) {
    final c = (rawColor ?? '').toString().trim().toLowerCase();

    // Уже слово
    if (_allowedColorWords.contains(c)) return c;

    // Старый hex
    final hex = c.toUpperCase();
    if (_hexToWord.containsKey(hex)) return _hexToWord[hex]!;
    final hex2 = c.startsWith('#') ? c.toUpperCase() : '#${c.toUpperCase()}';
    if (_hexToWord.containsKey(hex2)) return _hexToWord[hex2]!;

    // fallback
    return '—';
  }

  Color? _colorFromWord(String word) {
    final w = word.trim().toLowerCase();
    return _wordToColor[w];
  }

  String _displayNameFromProfile(Map<String, dynamic> profile) {
    final first = (profile['first_name'] ?? '').toString().trim();
    final last = (profile['last_name'] ?? '').toString().trim();
    final username = (profile['telegram_username'] ?? '').toString().trim();
    final fullName = '$first $last'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return 'Игрок';
  }

  String _currentUserDisplayName() {
    final fullName = '${widget.user.firstName} ${widget.user.lastName}'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (widget.user.username.trim().isNotEmpty) return widget.user.username.trim();
    return 'Игрок';
  }

  String _resolvePlayerName(String? userId) {
    if (userId == null || userId.isEmpty) return 'Игрок';
    return _playerNames[userId] ?? userId;
  }

  String _extractItemLabel(dynamic itemJson) {
    try {
      if (itemJson is Map) {
        return (itemJson['name']?.toString() ?? itemJson['id']?.toString() ?? jsonEncode(itemJson));
      }
      return itemJson?.toString() ?? '';
    } catch (_) {
      return itemJson?.toString() ?? '';
    }
  }

  int _extractItemVoices(dynamic itemJson) {
    try {
      if (itemJson is! Map) return 0;
      for (final key in ['voices', 'count', 'amount', 'v']) {
        final value = itemJson[key];
        if (value != null) {
          return (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
        }
      }
    } catch (_) {}
    return 0;
  }

  String _formatPrice(dynamic price) {
    final parsed = (price is num) ? price.toDouble() : double.tryParse(price?.toString() ?? '');
    if (parsed == null) return price?.toString() ?? '-';
    final isInt = parsed == parsed.roundToDouble();
    return isInt ? parsed.toInt().toString() : parsed.toStringAsFixed(2);
  }

  Future<void> _sendUserEvent({
    required String userId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await supabase.from('user_events').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'actor_id': widget.user.id,
        'metadata': metadata,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _loadPlayerNames(Iterable<Map<String, dynamic>> offers) async {
    final ids = <String>{};
    for (final offer in offers) {
      final sellerId = offer['seller_id']?.toString();
      final buyerId = offer['buyer_id']?.toString();
      if (sellerId != null && sellerId.isNotEmpty && !_playerNames.containsKey(sellerId)) {
        ids.add(sellerId);
      }
      if (buyerId != null && buyerId.isNotEmpty && !_playerNames.containsKey(buyerId)) {
        ids.add(buyerId);
      }
    }
    if (ids.isEmpty) return;
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name')
          .inFilter('id', ids.toList());
      if (res is List) {
        for (final row in res) {
          final map = Map<String, dynamic>.from(row as Map);
          final id = map['id']?.toString();
          if (id == null || id.isEmpty) continue;
          _playerNames[id] = _displayNameFromProfile(map);
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshTradingData() async {
    await _fetchIncomingOffers();
    await _fetchOutgoingOffers();
    await _fetchTradeHistory();
  }

  void _subscribeToOfferChanges() {
    try {
      _offersChannel = supabase.channel('inventory-item-offers-${widget.user.id}');
      _offersChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'item_offers',
            callback: (payload) async {
              final record = payload.newRecord;
              final sellerId = record['seller_id']?.toString();
              final buyerId = record['buyer_id']?.toString();
              if (sellerId != widget.user.id && buyerId != widget.user.id) return;
              if (!mounted) return;
              await _refreshTradingData();
              await _loadInventory();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'item_offers',
            callback: (payload) async {
              final record = payload.newRecord;
              final sellerId = record['seller_id']?.toString();
              final buyerId = record['buyer_id']?.toString();
              if (sellerId != widget.user.id && buyerId != widget.user.id) return;
              if (!mounted) return;
              await _refreshTradingData();
              await _loadInventory();
            },
          )
          .subscribe();
    } catch (_) {}
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось загрузить список игроков: $e'),
          backgroundColor: TitanicTheme.surfaceNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет доступных покупателей'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      return;
    }

    final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TitanicTheme.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TitanicTheme.surfaceNavy,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Text(
                      'Выберите покупателя',
                      style: TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: TitanicTheme.ivoryCream,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: TitanicTheme.panelDark.withOpacity(0.5),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Поиск покупателя...',
                          hintStyle: TextStyle(color: TitanicTheme.ivoryCream.withOpacity(0.6)),
                          prefixIcon: Icon(Icons.search, color: TitanicTheme.raptureGold),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        style: TextStyle(color: TitanicTheme.ivoryCream),
                        onChanged: doFilter,
                      ),
                    ),
                  ),
                  TitanicTheme.decoDivider(),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Не найдено',
                              style: TextStyle(
                                fontFamily: 'Cinzel',
                                color: TitanicTheme.ivoryCream.withOpacity(0.5),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 0,
                              color: TitanicTheme.raptureGold.withOpacity(0.1),
                            ),
                            itemBuilder: (context, i) {
                              final p = filtered[i];
                              final first = (p['first_name'] ?? '').toString();
                              final last = (p['last_name'] ?? '').toString();
                              final displayName = ('$first $last').trim().isEmpty ? (p['telegram_username'] ?? 'Без имени') : '$first $last';
                              return Container(
                                decoration: BoxDecoration(
                                  color: TitanicTheme.surfaceNavy.withOpacity(0.5),
                                ),
                                child: ListTile(
                                  title: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      color: TitanicTheme.ivoryCream,
                                    ),
                                  ),
                                  subtitle: Text(
                                    p['telegram_username']?.toString() ?? '',
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    color: TitanicTheme.raptureGold,
                                    size: 16,
                                  ),
                                  onTap: () => Navigator.of(context).pop(p),
                                ),
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
        return Dialog(
          backgroundColor: TitanicTheme.panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.4), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Продажа: "$itemLabel"',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: TitanicTheme.raptureGold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TitanicTheme.surfaceNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Войсы:',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          color: TitanicTheme.ivoryCream,
                        ),
                      ),
                      Text(
                        '${item['voices'] ?? 0}',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: TitanicTheme.raptureGold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Цена (войсы, V)',
                    labelStyle: TextStyle(color: TitanicTheme.ivoryCream.withOpacity(0.7)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.seaFoamGreen),
                    ),
                  ),
                  style: TextStyle(color: TitanicTheme.ivoryCream),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: TitanicTheme.outlineGildedButton(),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(false),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  'Отмена',
                                  style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: TitanicTheme.ivoryCream,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: TitanicTheme.primaryAccentButtonDecoration,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(true),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send, color: Colors.black, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Отправить',
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) {
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Введите корректную цену',
            style: TextStyle(fontFamily: 'Cinzel'),
          ),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      try {
        priceCtrl.dispose();
      } catch (_) {}
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TitanicTheme.panelDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TitanicTheme.raptureGold),
              const SizedBox(height: 16),
              Text(
                'Отправка оффера...',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: TitanicTheme.ivoryCream,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final params = {
        'p_from': widget.user.id,
        'p_to': chosen['id'].toString(),
        'p_item_id': itemId ?? itemLabel,
        'p_price': price
      };

      await supabase.rpc('create_item_offer', params: params);

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Оффер отправлен покупателю',
            style: TextStyle(fontFamily: 'Cinzel'),
          ),
          backgroundColor: TitanicTheme.surfaceNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _loadInventory();
      await _refreshTradingData();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ошибка при создании оффера: $msg',
            style: TextStyle(fontFamily: 'Cinzel'),
          ),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
    } finally {
      try {
        priceCtrl.dispose();
      } catch (_) {}
    }
  }

  Future<void> _openSellToBank(Map<String, dynamic> item) async {
    final itemLabel = item['label']?.toString() ?? 'item';
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: TitanicTheme.panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.4), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Продажа в Банк',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: TitanicTheme.raptureGold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '"$itemLabel"',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 16,
                    color: TitanicTheme.ivoryCream,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TitanicTheme.surfaceNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Войсы:',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          color: TitanicTheme.ivoryCream,
                        ),
                      ),
                      Text(
                        '${item['voices'] ?? 0}',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: TitanicTheme.raptureGold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Количество (обычно 1)',
                    labelStyle: TextStyle(color: TitanicTheme.ivoryCream.withOpacity(0.7)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.seaFoamGreen),
                    ),
                  ),
                  style: TextStyle(color: TitanicTheme.ivoryCream),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Цена за единицу (M)',
                    labelStyle: TextStyle(color: TitanicTheme.ivoryCream.withOpacity(0.7)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.seaFoamGreen),
                    ),
                  ),
                  style: TextStyle(color: TitanicTheme.ivoryCream),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: TitanicTheme.outlineGildedButton(),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(false),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  'Отмена',
                                  style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: TitanicTheme.ivoryCream,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: TitanicTheme.primaryAccentButtonDecoration,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(true),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance, color: Colors.black, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Продать',
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректное количество'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      return;
    }
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите корректную цену'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TitanicTheme.panelDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TitanicTheme.raptureGold),
              const SizedBox(height: 16),
              Text(
                'Продажа в банк...',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: TitanicTheme.ivoryCream,
                ),
              ),
            ],
          ),
        ),
      ),
    );

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Предмет продан в банк'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      await _loadInventory();
      await _refreshTradingData();

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при продаже в банк: $msg'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
    }
  }

  Future<void> _fetchIncomingOffers() async {
    setState(() {
      _loadingOffers = true;
    });
    try {
      final res = await supabase
          .from('item_offers')
          .select('id, seller_id, buyer_id, item_json, price, status, created_at')
          .eq('status', 'pending')
          .eq('buyer_id', widget.user.id)
          .order('created_at', ascending: false);
      final List<Map<String, dynamic>> offers = [];
      if (res is List) {
        for (final r in res) {
          offers.add(Map<String, dynamic>.from(r as Map));
        }
      }
      await _loadPlayerNames(offers);
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

  Future<void> _fetchOutgoingOffers() async {
    try {
      final res = await supabase
          .from('item_offers')
          .select('id, seller_id, buyer_id, item_json, price, status, created_at')
          .eq('status', 'pending')
          .eq('seller_id', widget.user.id)
          .order('created_at', ascending: false);
      final List<Map<String, dynamic>> offers = [];
      if (res is List) {
        for (final r in res) {
          offers.add(Map<String, dynamic>.from(r as Map));
        }
      }
      await _loadPlayerNames(offers);
      if (!mounted) return;
      setState(() {
        _outgoingOffers = offers;
      });
    } catch (_) {}
  }

  Future<void> _fetchTradeHistory() async {
    try {
      final res = await supabase
          .from('item_offers')
          .select('id, seller_id, buyer_id, item_json, price, status, created_at')
          .or('seller_id.eq.${widget.user.id},buyer_id.eq.${widget.user.id}')
          .neq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(20);
      final List<Map<String, dynamic>> offers = [];
      if (res is List) {
        for (final r in res) {
          offers.add(Map<String, dynamic>.from(r as Map));
        }
      }
      await _loadPlayerNames(offers);
      if (!mounted) return;
      setState(() {
        _tradeHistory = offers;
      });
    } catch (_) {}
  }

  Future<void> _acceptOffer(int offerId) async {
    Map<String, dynamic>? currentOffer;
    for (final offer in _incomingOffers) {
      if (offer['id']?.toString() == offerId.toString()) {
        currentOffer = offer;
        break;
      }
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TitanicTheme.panelDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TitanicTheme.raptureGold),
              const SizedBox(height: 16),
              Text(
                'Принятие оффера...',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: TitanicTheme.ivoryCream,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await supabase.rpc('accept_item_offer', params: {'p_offer_id': offerId, 'p_buyer_id': widget.user.id});
      if (currentOffer != null) {
        final sellerId = currentOffer['seller_id']?.toString();
        if (sellerId != null && sellerId.isNotEmpty) {
          await _sendUserEvent(
            userId: sellerId,
            title: 'Оффер принят',
            message: '${_currentUserDisplayName()} принял(а) ваш оффер "${_extractItemLabel(currentOffer['item_json'])}" за ${_formatPrice(currentOffer['price'])} V',
            metadata: {'type': 'item_offer_accepted', 'offer_id': offerId},
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Оффер принят — предмет добавлен в инвентарь'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      await _loadInventory();
      await _refreshTradingData();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при принятии оффера: $msg'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
    }
  }

  Future<void> _rejectOffer(int offerId) async {
    Map<String, dynamic>? currentOffer;
    for (final offer in _incomingOffers) {
      if (offer['id']?.toString() == offerId.toString()) {
        currentOffer = offer;
        break;
      }
    }
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: TitanicTheme.panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.4), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Отклонение оффера',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: TitanicTheme.raptureGold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Укажите причину (необязательно):',
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    color: TitanicTheme.ivoryCream,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: TitanicTheme.seaFoamGreen),
                    ),
                  ),
                  style: TextStyle(color: TitanicTheme.ivoryCream),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: TitanicTheme.outlineGildedButton(),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(false),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  'Отмена',
                                  style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: TitanicTheme.ivoryCream,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.shade700, Colors.red.shade900],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(true),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.close, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Отклонить',
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TitanicTheme.panelDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TitanicTheme.raptureGold),
              const SizedBox(height: 16),
              Text(
                'Отклонение оффера...',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: TitanicTheme.ivoryCream,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await supabase.rpc('reject_item_offer', params: {'p_offer_id': offerId, 'p_buyer_id': widget.user.id, 'p_reason': reasonCtrl.text});
      if (currentOffer != null) {
        final sellerId = currentOffer['seller_id']?.toString();
        if (sellerId != null && sellerId.isNotEmpty) {
          final reason = reasonCtrl.text.trim();
          await _sendUserEvent(
            userId: sellerId,
            title: 'Оффер отклонён',
            message: reason.isEmpty
                ? '${_currentUserDisplayName()} отклонил(а) ваш оффер "${_extractItemLabel(currentOffer['item_json'])}"'
                : '${_currentUserDisplayName()} отклонил(а) ваш оффер "${_extractItemLabel(currentOffer['item_json'])}". Причина: $reason',
            metadata: {'type': 'item_offer_rejected', 'offer_id': offerId},
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Оффер отклонён — предмет возвращён продавцу'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
      await _loadInventory();
      await _refreshTradingData();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      final msg = (e is PostgrestException) ? (e.message ?? e.toString()) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при отклонении оффера: $msg'),
          backgroundColor: TitanicTheme.surfaceNavy,
        ),
      );
    } finally {
      try {
        reasonCtrl.dispose();
      } catch (_) {}
    }
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final name = item['label']?.toString() ?? 'item';
    final voices = (item['voices'] is num) ? (item['voices'] as num).toInt() : 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: TitanicTheme.geometricTileDecoration(highlighted: true),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: TitanicTheme.seaGradient,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          child: Icon(
            Icons.inventory,
            color: TitanicTheme.ivoryCream,
            size: 24,
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: TitanicTheme.ivoryCream,
          ),
        ),
        subtitle: Text(
          '$voices войсов',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: 14,
            color: TitanicTheme.raptureGold,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: TitanicTheme.raptureGold),
          color: TitanicTheme.panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
          ),
          onSelected: (v) async {
            if (v == 'sell_player') {
              await _openSellToPlayer(item);
            } else if (v == 'sell_bank') {
              await _openSellToBank(item);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'sell_player',
              child: Row(
                children: [
                  Icon(Icons.person, color: TitanicTheme.raptureGold, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Продать игроку',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      color: TitanicTheme.ivoryCream,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'sell_bank',
              child: Row(
                children: [
                  Icon(Icons.account_balance, color: TitanicTheme.raptureGold, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Продать в Банк',
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      color: TitanicTheme.ivoryCream,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ NEW: Enterprises block (shows color WORD)
  Widget _buildEnterprisesBlock() {
    if (_enterprises.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: TitanicTheme.artDecoPanelDecoration(),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: TitanicTheme.goldGradient,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.business_center,
            color: Colors.black,
            size: 20,
          ),
        ),
        title: Text(
          'Предприятия',
          style: TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: TitanicTheme.ivoryCream,
          ),
        ),
        subtitle: Text(
          '${_enterprises.length} шт.',
          style: TextStyle(
            fontFamily: 'Cinzel',
            color: TitanicTheme.ivoryCream.withOpacity(0.7),
          ),
        ),
        children: _enterprises.map((e) {
          final name = (e['name'] ?? 'Предприятие').toString();
          final region = (e['region'] ?? '').toString();
          final colorWord = _normalizeEnterpriseColorWord(e['color']);
          final c = _colorFromWord(colorWord);

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: TitanicTheme.surfaceNavy.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.2)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (c ?? TitanicTheme.surfaceNavy).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.25)),
                ),
                child: Icon(
                  Icons.apartment,
                  color: c ?? TitanicTheme.raptureGold,
                  size: 20,
                ),
              ),
              title: Text(
                name,
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TitanicTheme.ivoryCream,
                ),
              ),
              subtitle: Text(
                [
                  if (region.isNotEmpty) region,
                  if (colorWord != '—') 'Цвет: $colorWord',
                ].join(' • '),
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  color: TitanicTheme.ivoryCream.withOpacity(0.7),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOfferActions({
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required VoidCallback? onTap,
    required BoxDecoration decoration,
    required Color textColor,
    IconData? icon,
  }) {
    return Container(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: textColor, size: 18),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: TitanicTheme.panelDark.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: 11,
          color: TitanicTheme.ivoryCream.withOpacity(0.82),
        ),
      ),
    );
  }

  Widget _buildOfferSection({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> offers,
    required String Function(Map<String, dynamic>) counterpartLabelBuilder,
    bool incoming = false,
    bool showStatus = false,
  }) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: TitanicTheme.artDecoPanelDecoration(),
      child: ExpansionTile(
        initiallyExpanded: incoming,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: TitanicTheme.goldGradient,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.black, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: TitanicTheme.ivoryCream,
          ),
        ),
        subtitle: Text(
          '${offers.length}',
          style: TextStyle(
            fontFamily: 'Cinzel',
            color: TitanicTheme.ivoryCream.withOpacity(0.7),
          ),
        ),
        children: offers.map((o) {
          final offerId = (o['id'] is int) ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '') ?? 0;
          final itemLabel = _extractItemLabel(o['item_json']);
          final itemVoices = _extractItemVoices(o['item_json']);
          final price = _formatPrice(o['price']);
          final createdAt = DateTime.tryParse(o['created_at']?.toString() ?? '');
          final createdLabel = createdAt == null
              ? ''
              : '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
          final status = (o['status'] ?? '').toString();

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TitanicTheme.surfaceNavy.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: TitanicTheme.seaFoamGreen.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.shopping_bag, color: TitanicTheme.seaFoamGreen, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemLabel,
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: TitanicTheme.ivoryCream,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            counterpartLabelBuilder(o),
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 12,
                              color: TitanicTheme.ivoryCream.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMetaChip('$itemVoices войсов'),
                    _buildMetaChip('Цена: $price V'),
                    if (createdLabel.isNotEmpty) _buildMetaChip(createdLabel),
                    if (showStatus && status.isNotEmpty) _buildMetaChip('Статус: $status'),
                  ],
                ),
                if (incoming && status == 'pending')
                  _buildOfferActions(
                    children: [
                      _buildActionChip(
                        label: 'Отклонить',
                        icon: Icons.close,
                        onTap: () => _rejectOffer(offerId),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textColor: Colors.white,
                      ),
                      _buildActionChip(
                        label: 'Принять',
                        icon: Icons.check,
                        onTap: () => _acceptOffer(offerId),
                        decoration: TitanicTheme.primaryAccentButtonDecoration,
                        textColor: Colors.black,
                      ),
                    ],
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOffersList() {
    if (_loadingOffers) {
      return Center(
        child: CircularProgressIndicator(color: TitanicTheme.raptureGold),
      );
    }
    if (_incomingOffers.isEmpty && _outgoingOffers.isEmpty && _tradeHistory.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        _buildOfferSection(
          title: 'Входящие офферы',
          icon: Icons.mark_email_unread,
          offers: _incomingOffers,
          incoming: true,
          counterpartLabelBuilder: (offer) => 'От: ${_resolvePlayerName(offer['seller_id']?.toString())}',
        ),
        _buildOfferSection(
          title: 'Исходящие офферы',
          icon: Icons.outbox,
          offers: _outgoingOffers,
          counterpartLabelBuilder: (offer) => 'Кому: ${_resolvePlayerName(offer['buyer_id']?.toString())}',
        ),
        _buildOfferSection(
          title: 'История торговли',
          icon: Icons.history,
          offers: _tradeHistory,
          showStatus: true,
          counterpartLabelBuilder: (offer) {
            final isSeller = offer['seller_id']?.toString() == widget.user.id;
            final otherParty = isSeller ? offer['buyer_id']?.toString() : offer['seller_id']?.toString();
            return isSeller
                ? 'Покупатель: ${_resolvePlayerName(otherParty)}'
                : 'Продавец: ${_resolvePlayerName(otherParty)}';
          },
        ),
      ],
    );
    /*
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: TitanicTheme.artDecoPanelDecoration(),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: TitanicTheme.goldGradient,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mark_email_unread,
            color: Colors.black,
            size: 20,
          ),
        ),
        title: Text(
          'Входящие офферы',
          style: TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: TitanicTheme.ivoryCream,
          ),
        ),
        subtitle: Text(
          '${_incomingOffers.length} предложений',
          style: TextStyle(
            fontFamily: 'Cinzel',
            color: TitanicTheme.ivoryCream.withOpacity(0.7),
          ),
        ),
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

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: TitanicTheme.surfaceNavy.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.2)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TitanicTheme.seaFoamGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.shopping_cart,
                  color: TitanicTheme.seaFoamGreen,
                  size: 20,
                ),
              ),
              title: Text(
                itemLabel,
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TitanicTheme.ivoryCream,
                ),
              ),
              subtitle: Text(
                '$itemVoices войсов • Цена: $price • От: $seller',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 12,
                  color: TitanicTheme.ivoryCream.withOpacity(0.7),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _rejectOffer(offerId),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Отклонить',
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: TitanicTheme.primaryAccentButtonDecoration,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _acceptOffer(offerId),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Принять',
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
    */
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompletelyEmpty = _itemsList.isEmpty && _enterprises.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: TitanicTheme.raptureGold),
            const SizedBox(width: 12),
            Text(
              'ИНВЕНТАРЬ',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: TitanicTheme.ivoryCream,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        backgroundColor: TitanicTheme.abyssalBlue.withOpacity(0.95),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        iconTheme: TitanicTheme.iconTheme,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: TitanicTheme.raptureGold.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: TitanicTheme.raptureGold),
              onPressed: () async {
                await _loadInventory();
                await _refreshTradingData();
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: TitanicTheme.backgroundGradient,
        ),
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadInventory();
            await _refreshTradingData();
          },
          backgroundColor: TitanicTheme.panelDark,
          color: TitanicTheme.raptureGold,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: TitanicTheme.raptureGold),
                  )
                : _error != null
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: TitanicTheme.artDecoPanelDecoration(),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              color: TitanicTheme.ivoryCream,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : isCompletelyEmpty
                        ? Column(
                            children: [
                              _buildOffersList(),
                              _buildEnterprisesBlock(),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: TitanicTheme.artDecoPanelDecoration(),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inventory_2,
                                          color: TitanicTheme.raptureGold,
                                          size: 64,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Инвентарь пуст',
                                          style: TextStyle(
                                            fontFamily: 'CormorantGaramond',
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: TitanicTheme.ivoryCream,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Предметы будут отображаться здесь',
                                          style: TextStyle(
                                            fontFamily: 'Cinzel',
                                            color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _buildOffersList(),
                              _buildEnterprisesBlock(),
                              Expanded(
                                child: ListView(
                                  children: [
                                    const SizedBox(height: 8),
                                    ..._itemsList.map((item) => _buildItemRow(item)).toList(),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.only(top: 8),
                                decoration: TitanicTheme.artDecoPanelDecoration(prominent: true),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Общая стоимость:',
                                      style: TextStyle(
                                        fontFamily: 'CormorantGaramond',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: TitanicTheme.ivoryCream,
                                      ),
                                    ),
                                    Text(
                                      '${_totalVoicesSum()} войсов',
                                      style: TextStyle(
                                        fontFamily: 'Cinzel',
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: TitanicTheme.raptureGold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}
