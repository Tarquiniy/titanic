// lib/admin_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final supabase = Supabase.instance.client;

  int _tabIndex = 0;

  // GlobalKeys для доступа к методам состояний табов
  final GlobalKey<_PollsAuctionsTabState> _pollsKey = GlobalKey<_PollsAuctionsTabState>();
  final GlobalKey<_EnterprisesTabState> _enterprisesKey = GlobalKey<_EnterprisesTabState>();

  void _openCreatePoll() {
    setState(() => _tabIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pollsKey.currentState?._createPoll();
    });
  }

  void _openCreateAuction() {
    setState(() => _tabIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pollsKey.currentState?._createAuction();
    });
  }

  void _openCreateEnterprise() {
    setState(() => _tabIndex = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterprisesKey.currentState?._openCreateEnterpriseDialog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const UsersTab(),
      PollsAuctionsTab(key: _pollsKey),
      const InventoryTab(),
      EnterprisesTab(key: _enterprisesKey),
      const BulkTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Панель управления'),
        actions: [
          IconButton(
            tooltip: 'Создать опрос',
            icon: const Icon(Icons.how_to_vote),
            onPressed: _openCreatePoll,
          ),
          IconButton(
            tooltip: 'Создать аукцион',
            icon: const Icon(Icons.gavel),
            onPressed: _openCreateAuction,
          ),
          IconButton(
            tooltip: 'Создать предприятие',
            icon: const Icon(Icons.apartment),
            onPressed: _openCreateEnterprise,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: tabs[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Пользователи'),
          BottomNavigationBarItem(icon: Icon(Icons.how_to_vote), label: 'Опросы/Аукционы'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Инвентарь'),
          BottomNavigationBarItem(icon: Icon(Icons.apartment), label: 'Предприятия'),
          BottomNavigationBarItem(icon: Icon(Icons.copy_all), label: 'Массово'),
        ],
      ),
    );
  }
}

// ----------------- UsersTab -----------------
class UsersTab extends StatefulWidget {
  const UsersTab({Key? key}) : super(key: key);
  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
    });
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name, role, v_balance, m_balance, color, inventory, enterprises')
          .order('first_name');
      if (res is List) {
        setState(() {
          _users = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } else {
        setState(() => _users = []);
      }
    } catch (e) {
      setState(() => _users = []);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserEditDialog(user: Map<String, dynamic>.from(user)),
    );
    if (updated != null) {
      try {
        await supabase.from('user_credentials').update(updated).eq('id', user['id']);
        await _loadUsers();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
      }
    }
  }

  Future<void> _bulkAssignInventory() async {
    final body = await showDialog<String>(context: context, builder: (_) => const _BulkJsonDialog(title: 'Вставьте JSON { "username": { "item": count } }'));
    if (body == null) return;
    try {
      final Map parsed = jsonDecode(body);
      for (final entry in parsed.entries) {
        final username = entry.key.toString();
        final inv = entry.value;
        final profile = await supabase.from('user_credentials').select('id, inventory').eq('telegram_username', username).maybeSingle();
        if (profile == null) continue;
        final id = (profile as Map)['id'].toString();
        // Получаем текущее inventory и объединяем
        dynamic cur = (profile as Map)['inventory'];
        Map merged = {};
        if (cur != null) {
          try {
            if (cur is String) cur = jsonDecode(cur);
            if (cur is Map) merged.addAll(Map<String, dynamic>.from(cur as Map));
          } catch (_) {}
        }
        if (inv is Map) {
          inv.forEach((k, v) {
            final key = k.toString();
            final count = int.tryParse(v.toString()) ?? 0;
            merged[key] = (merged[key] ?? 0) + count;
          });
        }
        await supabase.from('user_credentials').update({'inventory': merged}).eq('id', id);
      }
      await _loadUsers();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Массовая операция завершена')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка парсинга JSON: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _users.where((u) {
      final q = _filter.toLowerCase();
      if (q.isEmpty) return true;
      return (u['telegram_username'] ?? '').toString().toLowerCase().contains(q) ||
          (u['first_name'] ?? '').toString().toLowerCase().contains(q) ||
          (u['last_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(hintText: 'Поиск username/имя/фамилия'),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loadUsers, child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Обновить')),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _bulkAssignInventory, child: const Text('Массово: инвентарь')),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (context, i) {
                  final u = visible[i];
                  final name = ((u['first_name'] ?? '') + ' ' + (u['last_name'] ?? '')).trim();
                  return ListTile(
                    title: Text(name.isEmpty ? (u['telegram_username'] ?? 'Без имени') : name),
                    subtitle: Text('role: ${u['role'] ?? '-'}  V:${(u['v_balance'] ?? 0).toString()} M:${(u['m_balance'] ?? 0).toString()}'),
                    trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editUser(u)),
                  );
                },
              ),
      ),
    ]);
  }
}

class _UserEditDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  const _UserEditDialog({required this.user, Key? key}) : super(key: key);
  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  late TextEditingController _vCtrl;
  late TextEditingController _mCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _inventoryCtrl;
  late TextEditingController _enterprisesCtrl;

  @override
  void initState() {
    super.initState();
    _vCtrl = TextEditingController(text: (widget.user['v_balance'] ?? '').toString());
    _mCtrl = TextEditingController(text: (widget.user['m_balance'] ?? '').toString());
    _roleCtrl = TextEditingController(text: (widget.user['role'] ?? '').toString());
    _colorCtrl = TextEditingController(text: (widget.user['color'] ?? '').toString());
    _inventoryCtrl = TextEditingController(text: jsonEncode(widget.user['inventory'] ?? {}));
    _enterprisesCtrl = TextEditingController(text: jsonEncode(widget.user['enterprises'] ?? {}));
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _mCtrl.dispose();
    _roleCtrl.dispose();
    _colorCtrl.dispose();
    _inventoryCtrl.dispose();
    _enterprisesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() {
    final Map out = {};
    final v = double.tryParse(_vCtrl.text.replaceAll(',', '.'));
    final m = double.tryParse(_mCtrl.text.replaceAll(',', '.'));
    if (v != null) out['v_balance'] = v;
    if (m != null) out['m_balance'] = m;
    out['role'] = _roleCtrl.text.trim();
    out['color'] = _colorCtrl.text.trim();
    try {
      final inv = jsonDecode(_inventoryCtrl.text);
      out['inventory'] = inv;
    } catch (_) {}
    try {
      final ent = jsonDecode(_enterprisesCtrl.text);
      out['enterprises'] = ent;
    } catch (_) {}
    return Map<String, dynamic>.from(out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать пользователя'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _roleCtrl, decoration: const InputDecoration(labelText: 'role')),
          TextField(controller: _vCtrl, decoration: const InputDecoration(labelText: 'V balance'), keyboardType: TextInputType.numberWithOptions(decimal: true)),
          TextField(controller: _mCtrl, decoration: const InputDecoration(labelText: 'M balance'), keyboardType: TextInputType.numberWithOptions(decimal: true)),
          TextField(controller: _colorCtrl, decoration: const InputDecoration(labelText: 'color (hex)')),
          const SizedBox(height: 8),
          TextField(controller: _inventoryCtrl, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'inventory (JSON)')),
          const SizedBox(height: 8),
          TextField(controller: _enterprisesCtrl, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'enterprises (JSON)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_buildPayload()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ----------------- Polls/Auctions tab -----------------
class PollsAuctionsTab extends StatefulWidget {
  const PollsAuctionsTab({Key? key}) : super(key: key);
  @override
  State<PollsAuctionsTab> createState() => _PollsAuctionsTabState();
}

class _PollsAuctionsTabState extends State<PollsAuctionsTab> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _polls = [];
  List<Map<String, dynamic>> _auctions = [];
  bool _loadingPolls = false;
  bool _loadingAuctions = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadPolls(), _loadAuctions()]);
  }

  Future<void> _loadPolls() async {
    setState(() => _loadingPolls = true);
    try {
      final res = await supabase.from('polls').select('id, title, is_closed, created_at').order('created_at', ascending: false);
      if (res is List) {
        _polls = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _polls = [];
      }
    } catch (e) {
      _polls = [];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки опросов: $e')));
    } finally {
      setState(() => _loadingPolls = false);
    }
  }

  Future<void> _loadAuctions() async {
    setState(() => _loadingAuctions = true);
    try {
      final res = await supabase.from('auctions').select('id, title, starts_at, ends_at, is_closed, created_at').order('created_at', ascending: false);
      if (res is List) {
        _auctions = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _auctions = [];
      }
    } catch (e) {
      _auctions = [];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки аукционов: $e')));
    } finally {
      setState(() => _loadingAuctions = false);
    }
  }

  // эти методы вызываются также из AppBar через GlobalKey
  Future<void> _createPoll() async {
    final payload = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreatePollDialog());
    if (payload == null) return;
    try {
      final pollInsert = {
        'title': payload['title'],
        'is_closed': payload['isClosed'] ?? true,
        'meta': payload['meta'] ?? {},
      };
      final pollRes = await supabase.from('polls').insert(pollInsert).select().maybeSingle();
      if (pollRes == null) throw 'Не удалось создать опрос';
      final pollId = (pollRes as Map)['id'];
      final List options = payload['options'] ?? [];

      if (options.isNotEmpty) {
        final List<Map<String, dynamic>> batch = options.map((o) => {'poll_id': pollId, 'label': o}).toList();
        await supabase.from('poll_options').insert(batch);
      }

      await _loadPolls();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Опрос создан')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания опроса: $e')));
    }
  }

  Future<void> _createAuction() async {
    final payload = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreateAuctionDialog());
    if (payload == null) return;
    try {
      final auction = {
        'title': payload['title'],
        'item': payload['item'] ?? {},
        'starts_at': payload['startsAt']?.toIso8601String(),
        'ends_at': payload['endsAt']?.toIso8601String(),
        'is_closed': true,
      };
      await supabase.from('auctions').insert(auction);
      await _loadAuctions();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аукцион создан')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания аукциона: $e')));
    }
  }

  Future<void> _viewPollDetails(Map<String, dynamic> poll) async {
    final pollId = poll['id'];
    try {
      final optionsRes = await supabase.from('poll_options').select('id, label').eq('poll_id', pollId).order('id');
      final votesRes = await supabase.from('poll_votes').select('id, option_id, user_id, created_at').eq('poll_id', pollId);
      final options = (optionsRes is List) ? optionsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
      final votes = (votesRes is List) ? votesRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

      final Map<dynamic, int> counts = {};
      for (final v in votes) {
        final opt = v['option_id'];
        counts[opt] = (counts[opt] ?? 0) + 1;
      }

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Опрос: ${poll['title']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (options.isEmpty) const Text('Варианты отсутствуют'),
              ...options.map((o) {
                final optId = o['id'];
                final label = o['label'] ?? '';
                final cnt = counts[optId] ?? 0;
                return ListTile(
                  title: Text(label.toString()),
                  trailing: Text(cnt.toString()),
                );
              }).toList(),
              const Divider(),
              Text('Всего голосов: ${votes.length}'),
              if (votes.isNotEmpty) const SizedBox(height: 8),
              if (votes.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: votes.length,
                    itemBuilder: (context, i) {
                      final v = votes[i];
                      return ListTile(
                        dense: true,
                        title: Text('vote id: ${v['id']}'),
                        subtitle: Text('option: ${v['option_id']} user: ${v['user_id']}'),
                        trailing: Text(v['created_at']?.toString() ?? ''),
                      );
                    },
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
            TextButton(
                onPressed: () async {
                  try {
                    await supabase.from('polls').delete().eq('id', pollId);
                    await _loadPolls();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Опрос удалён')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
                  }
                },
                child: const Text('Удалить опрос')),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка получения данных опроса: $e')));
    }
  }

  Future<void> _viewAuctionDetails(Map<String, dynamic> auction) async {
    final auctionId = auction['id'];
    try {
      final bidsRes = await supabase.from('auction_bids').select('id, user_id, bid, created_at').eq('auction_id', auctionId).order('created_at', ascending: false);
      final bids = (bidsRes is List) ? bidsRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Аукцион: ${auction['title']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Начало: ${auction['starts_at'] ?? '-'}'),
              Text('Конец: ${auction['ends_at'] ?? '-'}'),
              const SizedBox(height: 12),
              if (bids.isEmpty) const Text('Ставок нет'),
              if (bids.isNotEmpty)
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: bids.length,
                    itemBuilder: (context, i) {
                      final b = bids[i];
                      return ListTile(
                        title: Text('Bid: ${b['bid']}'),
                        subtitle: Text('user: ${b['user_id']}'),
                        trailing: Text(b['created_at']?.toString() ?? ''),
                      );
                    },
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
            TextButton(
                onPressed: () async {
                  try {
                    await supabase.from('auctions').delete().eq('id', auctionId);
                    await _loadAuctions();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аукцион удалён')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
                  }
                },
                child: const Text('Удалить аукцион')),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка получения ставок: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        Row(children: [
          ElevatedButton.icon(onPressed: _createPoll, icon: const Icon(Icons.add), label: const Text('Создать опрос')),
          const SizedBox(width: 8),
          ElevatedButton.icon(onPressed: _createAuction, icon: const Icon(Icons.add_shopping_cart), label: const Text('Создать аукцион')),
          const Spacer(),
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(children: [
            // Left: polls
            Expanded(
              child: Card(
                child: Column(children: [
                  ListTile(title: const Text('Опросы'), trailing: _loadingPolls ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null),
                  const Divider(height: 0),
                  Expanded(
                    child: _loadingPolls
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: _polls.length,
                            separatorBuilder: (_, __) => const Divider(height: 0),
                            itemBuilder: (context, i) {
                              final p = _polls[i];
                              return ListTile(
                                title: Text(p['title'] ?? 'Без названия'),
                                subtitle: Text('id: ${p['id']}  closed: ${p['is_closed'] ?? true}'),
                                onTap: () => _viewPollDetails(p),
                              );
                            },
                          ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            // Right: auctions
            Expanded(
              child: Card(
                child: Column(children: [
                  ListTile(title: const Text('Аукционы'), trailing: _loadingAuctions ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null),
                  const Divider(height: 0),
                  Expanded(
                    child: _loadingAuctions
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: _auctions.length,
                            separatorBuilder: (_, __) => const Divider(height: 0),
                            itemBuilder: (context, i) {
                              final a = _auctions[i];
                              return ListTile(
                                title: Text(a['title'] ?? 'Без названия'),
                                subtitle: Text('id: ${a['id']}  до: ${a['ends_at'] ?? '-'}'),
                                onTap: () => _viewAuctionDetails(a),
                              );
                            },
                          ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog({Key? key}) : super(key: key);
  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _title = TextEditingController();
  final _optionCtrl = TextEditingController();
  List<String> _options = [];
  bool _isClosed = true;

  @override
  void dispose() {
    _title.dispose();
    _optionCtrl.dispose();
    super.dispose();
  }

  void _addOption() {
    final t = _optionCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _options.add(t);
      _optionCtrl.clear();
    });
  }

  void _removeOptionAt(int index) {
    setState(() {
      _options.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать опрос'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Заголовок')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _optionCtrl, decoration: const InputDecoration(hintText: 'Вариант'))),
            IconButton(icon: const Icon(Icons.add), onPressed: _addOption),
          ]),
          const SizedBox(height: 8),
          if (_options.isEmpty) const Text('Варианты ещё не добавлены'),
          ..._options.asMap().entries.map((e) {
            final idx = e.key;
            final val = e.value;
            return ListTile(
              title: Text(val),
              trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeOptionAt(idx)),
            );
          }).toList(),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Закрытый (только админ смотрит результаты)'),
            const SizedBox(width: 8),
            Switch(value: _isClosed, onChanged: (v) => setState(() => _isClosed = v)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            if (_title.text.trim().isEmpty || _options.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Название и варианты обязательны')));
              return;
            }
            Navigator.of(context).pop({'title': _title.text.trim(), 'options': _options, 'isClosed': _isClosed});
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

class _CreateAuctionDialog extends StatefulWidget {
  const _CreateAuctionDialog({Key? key}) : super(key: key);
  @override
  State<_CreateAuctionDialog> createState() => _CreateAuctionDialogState();
}

class _CreateAuctionDialogState extends State<_CreateAuctionDialog> {
  final _title = TextEditingController();
  final _item = TextEditingController();
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void dispose() {
    _title.dispose();
    _item.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final pick = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 365)));
    if (pick == null) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 12, minute: 0));
    if (time == null) return;
    final dt = DateTime(pick.year, pick.month, pick.day, time.hour, time.minute);
    setState(() {
      if (isStart) _startsAt = dt;
      else _endsAt = dt;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать аукцион'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Заголовок')),
          const SizedBox(height: 8),
          TextField(controller: _item, decoration: const InputDecoration(labelText: 'Item JSON (пример: {"name":"sword","count":1})')),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton(onPressed: () => _pickDate(true), child: Text(_startsAt == null ? 'Выбрать старт' : _startsAt!.toString())),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => _pickDate(false), child: Text(_endsAt == null ? 'Выбрать конец' : _endsAt!.toString())),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заголовок обязателен')));
              return;
            }
            Map itemJson = {};
            try {
              itemJson = jsonDecode(_item.text);
            } catch (_) {}
            Navigator.of(context).pop({'title': _title.text.trim(), 'item': itemJson, 'startsAt': _startsAt, 'endsAt': _endsAt});
          },
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

// ----------------- InventoryTab -----------------
class InventoryTab extends StatefulWidget {
  const InventoryTab({Key? key}) : super(key: key);
  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final supabase = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _loading = false;

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final row = await supabase
          .from('user_credentials')
          .select('id, telegram_username, inventory')
          .eq('telegram_username', _usernameCtrl.text.trim())
          .maybeSingle();

      // Безопасное преобразование PostgrestMap -> Map<String, dynamic>
      Map<String, dynamic>? profile;
      if (row == null) {
        profile = null;
      } else if (row is Map) {
        profile = Map<String, dynamic>.from(row as Map);
      } else {
        // fallback через сериализацию, если тип необычный
        try {
          profile = Map<String, dynamic>.from(jsonDecode(jsonEncode(row)));
        } catch (_) {
          profile = null;
        }
      }

      setState(() => _profile = profile);
    } catch (e) {
      setState(() => _profile = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _setInventory() async {
    if (_profile == null) return;
    final body = await showDialog<String>(context: context, builder: (_) => _BulkJsonDialog(title: 'Введите inventory JSON, например {"sword":3}'));
    if (body == null) return;
    try {
      final parsed = jsonDecode(body);
      await supabase.from('user_credentials').update({'inventory': parsed}).eq('id', _profile!['id']);
      await _loadProfile();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Инвентарь обновлён')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: 'telegram username (без @)'))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loadProfile, child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Загрузить')),
        ]),
        const SizedBox(height: 12),
        if (_profile != null)
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Пользователь: ${_profile!['telegram_username']}'),
              const SizedBox(height: 8),
              Expanded(child: SingleChildScrollView(child: Text(jsonEncode(_profile!['inventory'] ?? {})))),
              ElevatedButton(onPressed: _setInventory, child: const Text('Установить / Перезаписать инвентарь')),
            ]),
          ),
      ]),
    );
  }
}

// ----------------- EnterprisesTab -----------------
class EnterprisesTab extends StatefulWidget {
  const EnterprisesTab({Key? key}) : super(key: key);
  @override
  State<EnterprisesTab> createState() => _EnterprisesTabState();
}

class _EnterprisesTabState extends State<EnterprisesTab> {
  final supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _sharesController = TextEditingController(); // ожидаем JSON [{ "user":"username","pct":50 }, ...]
  bool _loading = false;
  List<Map<String, dynamic>> _enterprises = [];

  @override
  void initState() {
    super.initState();
    _loadEnterprises();
  }

  Future<void> _loadEnterprises() async {
    setState(() => _loading = true);
    try {
      final res = await supabase.from('enterprises').select('id, title, created_at').order('created_at', ascending: false);
      if (res is List) {
        _enterprises = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _enterprises = [];
      }
    } catch (e) {
      _enterprises = [];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки предприятий: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openCreateEnterpriseDialog() async {
    final payload = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreateEnterpriseDialog());
    if (payload == null) return;
    await _createEnterprise(payload);
  }

  Future<void> _createEnterprise(Map<String, dynamic> payload) async {
    final name = payload['title']?.toString() ?? '';
    final shares = payload['shares'] as List<dynamic>? ?? [];
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя предприятия нужно')));
      return;
    }

    try {
      final ent = await supabase.from('enterprises').insert({'title': name}).select().maybeSingle();
      if (ent == null) throw 'Не удалось создать предприятие';
      final entId = (ent as Map)['id'];
      final List<Map<String, dynamic>> sharesBatch = [];
      for (final s in shares) {
        final username = s['user']?.toString();
        final pctRaw = s['pct'];
        if (username == null || pctRaw == null) continue;
        final pct = (pctRaw is num) ? pctRaw : double.tryParse(pctRaw.toString());
        if (pct == null) continue;
        final u = await supabase.from('user_credentials').select('id, telegram_username').eq('telegram_username', username).maybeSingle();
        if (u == null) continue;
        sharesBatch.add({'enterprise_id': entId, 'user_id': (u as Map)['id'], 'percent': pct});
      }

      if (sharesBatch.isNotEmpty) {
        await supabase.from('enterprise_shares').insert(sharesBatch);
      }

      await _loadEnterprises();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятие создано')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _viewEnterpriseDetails(Map<String, dynamic> ent) async {
    final entId = ent['id'];
    try {
      final sharesRes = await supabase.from('enterprise_shares').select('id, user_id, percent, meta, created_at').eq('enterprise_id', entId);
      final shares = (sharesRes is List) ? sharesRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Предприятие: ${ent['title']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (shares.isEmpty) const Text('Доли не распределены'),
              if (shares.isNotEmpty)
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: shares.length,
                    itemBuilder: (context, i) {
                      final s = shares[i];
                      return ListTile(
                        title: Text('user id: ${s['user_id']}'),
                        subtitle: Text('percent: ${s['percent']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_forever),
                          onPressed: () async {
                            try {
                              await supabase.from('enterprise_shares').delete().eq('id', s['id']);
                              Navigator.of(context).pop();
                              await _viewEnterpriseDetails(ent); // reopen to refresh
                              await _loadEnterprises();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Доля удалена')));
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть')),
            TextButton(
                onPressed: () async {
                  try {
                    await supabase.from('enterprises').delete().eq('id', entId);
                    await _loadEnterprises();
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятие удалено')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
                  }
                },
                child: const Text('Удалить предприятие')),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка получения долей: $e')));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sharesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        Row(children: [
          ElevatedButton.icon(onPressed: _openCreateEnterpriseDialog, icon: const Icon(Icons.add_business), label: const Text('Создать предприятие')),
          const SizedBox(width: 12),
          ElevatedButton(onPressed: _loadEnterprises, child: const Text('Обновить список')),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _enterprises.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final e = _enterprises[i];
                    return ListTile(
                      title: Text(e['title'] ?? 'Без названия'),
                      subtitle: Text('id: ${e['id']}'),
                      onTap: () => _viewEnterpriseDetails(e),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ----------------- BulkTab -----------------
class BulkTab extends StatefulWidget {
  const BulkTab({Key? key}) : super(key: key);
  @override
  State<BulkTab> createState() => _BulkTabState();
}

class _BulkTabState extends State<BulkTab> {
  final supabase = Supabase.instance.client;
  final _payloadCtrl = TextEditingController();

  Future<void> _applyBulkUpdate() async {
    final text = _payloadCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final doc = jsonDecode(text);
      if (doc is List) {
        for (final el in doc) {
          final username = el['username']?.toString();
          final set = el['set'];
          if (username == null || set == null) continue;
          await supabase.from('user_credentials').update(set).eq('telegram_username', username);
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Массовое обновление выполнено')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ожидается список объектов')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка JSON: $e')));
    }
  }

  @override
  void dispose() {
    _payloadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        const Text('Массовые операции: вставьте JSON-список изменений'),
        const SizedBox(height: 8),
        Expanded(child: TextField(controller: _payloadCtrl, maxLines: null, expands: true, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '[{ "username":"alice","set":{"v_balance":10}}]'))),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _applyBulkUpdate, child: const Text('Применить')),
      ]),
    );
  }
}

// ----------------- Reusable small dialogs -----------------
class _BulkJsonDialog extends StatefulWidget {
  final String title;
  const _BulkJsonDialog({required this.title, Key? key}) : super(key: key);
  @override
  State<_BulkJsonDialog> createState() => _BulkJsonDialogState();
}

class _BulkJsonDialogState extends State<_BulkJsonDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _ctrl, minLines: 4, maxLines: 12, decoration: const InputDecoration(hintText: '{}')),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(_ctrl.text), child: const Text('OK')),
      ],
    );
  }
}

// ----------------- Create Enterprise Dialog -----------------
class _CreateEnterpriseDialog extends StatefulWidget {
  const _CreateEnterpriseDialog({Key? key}) : super(key: key);
  @override
  State<_CreateEnterpriseDialog> createState() => _CreateEnterpriseDialogState();
}

class _CreateEnterpriseDialogState extends State<_CreateEnterpriseDialog> {
  final _titleCtrl = TextEditingController();
  final _sharesCtrl = TextEditingController(text: '[{"user":"alice","pct":50},{"user":"bob","pct":50}]');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _sharesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Название предприятия нужно')));
      return;
    }

    try {
      final parsed = jsonDecode(_sharesCtrl.text);
      if (parsed is! List) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Доли должны быть списком объектов')));
        return;
      }
      Navigator.of(context).pop({'title': title, 'shares': parsed});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка парсинга JSON: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать предприятие и распределить доли'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Название предприятия')),
          const SizedBox(height: 8),
          TextField(
            controller: _sharesCtrl,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Доли (JSON) пример [{"user":"alice","pct":50}]'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: _submit, child: const Text('Создать')),
      ],
    );
  }
}
