// lib/admin_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final supabase = Supabase.instance.client;

  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const UsersTab(),
      const PollsAuctionsTab(),
      const InventoryTab(),
      const EnterprisesTab(),
      const BulkTab(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Панель управления')),
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
          _users = List<Map<String, dynamic>>.from(res.map((e) => Map<String, dynamic>.from(e)));
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
        final id = profile['id'].toString();
        // Получаем текущее inventory и объединяем
        dynamic cur = profile['inventory'];
        Map merged = {};
        if (cur != null) {
          try {
            if (cur is String) cur = jsonDecode(cur);
            if (cur is Map) merged.addAll(Map<String, dynamic>.from(cur));
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

  Future<void> _createPoll() async {
    final payload = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreatePollDialog());
    if (payload == null) return;
    try {
      // Простая схема: polls + poll_options
      final pollInsert = {
        'title': payload['title'],
        'is_closed': payload['isClosed'] ?? true,
        'meta': payload['meta'] ?? {},
      };
      final pollRes = await supabase.from('polls').insert(pollInsert).select().maybeSingle();
      if (pollRes == null) throw 'Не удалось создать опрос';
      final pollId = pollRes['id'];
      final List options = payload['options'] ?? [];

      if (options.isNotEmpty) {
        // Собираем список для пакетной вставки (вместо вызова .execute() на каждом элементе)
        final List<Map<String, dynamic>> batch = options.map((o) => {'poll_id': pollId, 'label': o}).toList();
        await supabase.from('poll_options').insert(batch);
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Опрос создан')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания опроса: $e')));
    }
  }

  Future<void> _createAuction() async {
    final payload = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreateAuctionDialog());
    if (payload == null) return;
    try {
      // auctions table: title, item_json, starts_at, ends_at, closed_votes boolean
      final auction = {
        'title': payload['title'],
        'item': payload['item'] ?? {},
        'starts_at': payload['startsAt']?.toIso8601String(),
        'ends_at': payload['endsAt']?.toIso8601String(),
        'is_closed': true,
      };
      await supabase.from('auctions').insert(auction);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аукцион создан')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания аукциона: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        Row(children: [
          ElevatedButton(onPressed: _createPoll, child: const Text('Создать опрос')),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _createAuction, child: const Text('Создать аукцион')),
        ]),
        const SizedBox(height: 12),
        const Expanded(child: Center(child: Text('Список опросов/аукционов можно реализовать аналогично (fetch+list).'))),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать опрос'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Заголовок')),
          Row(children: [
            Expanded(child: TextField(controller: _optionCtrl, decoration: const InputDecoration(hintText: 'Вариант'))),
            IconButton(icon: const Icon(Icons.add), onPressed: _addOption),
          ]),
          const SizedBox(height: 8),
          ..._options.map((o) => ListTile(title: Text(o))).toList(),
          Row(children: [
            const Text('Закрытый (только админ смотрит результаты)'),
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
          TextField(controller: _item, decoration: const InputDecoration(labelText: 'Item JSON (пример: {"name":"sword","count":1})')),
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
      final row = await supabase.from('user_credentials').select('id, telegram_username, inventory').eq('telegram_username', _usernameCtrl.text.trim()).maybeSingle();
      setState(() => _profile = row is Map ? Map.from(row!) : null);
    } catch (e) {
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

  Future<void> _createEnterprise() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Имя предприятия нужно')));
      return;
    }
    try {
      final List parsed = jsonDecode(_sharesController.text);
      // Создадим запись в enterprises и распределение в enterprise_shares
      final ent = await supabase.from('enterprises').insert({'title': name}).select().maybeSingle();
      if (ent == null) throw 'Не удалось создать предприятие';
      final entId = ent['id'];
      for (final sh in parsed) {
        final username = sh['user']?.toString();
        final pct = (sh['pct'] is num) ? sh['pct'] : double.tryParse(sh['pct'].toString());
        if (username == null || pct == null) continue;
        // Находим пользователя
        final u = await supabase.from('user_credentials').select('id').eq('telegram_username', username).maybeSingle();
        if (u == null) continue;
        await supabase.from('enterprise_shares').insert({'enterprise_id': entId, 'user_id': u['id'], 'percent': pct});
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятие создано')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Название предприятия')),
        const SizedBox(height: 8),
        TextField(
          controller: _sharesController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Доли (JSON): [{"user":"alice","pct":50},{"user":"bob","pct":50}]'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _createEnterprise, child: const Text('Создать предприятие и распределить доли')),
        const SizedBox(height: 12),
        const Expanded(child: Center(child: Text('Список предприятий/активов можно добавить при необходимости'))),
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
      // Ожидаемый формат: [{ "username":"alice", "set": { "v_balance": 10, "inventory": {...} } }, ...]
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
