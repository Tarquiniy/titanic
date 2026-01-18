// lib/admin_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final supabase = Supabase.instance.client;

  int _tabIndex = 0;

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_id');
    } catch (_) {}
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const UsersTab(),
      const DebatesTab(),
      const ResolutionsTab(),
      const ColorBanksTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Панель управления'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: tabs[_tabIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Пользователи'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Дебаты'),
          BottomNavigationBarItem(icon: Icon(Icons.gavel), label: 'Политрешения'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Банки цветов'),
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
          ElevatedButton(
            onPressed: _loadUsers,
            child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Обновить'),
          ),
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

// ----------------- DebatesTab (admin create/close) -----------------
class DebatesTab extends StatefulWidget {
  const DebatesTab({Key? key}) : super(key: key);
  @override
  State<DebatesTab> createState() => _DebatesTabState();
}

class _DebatesTabState extends State<DebatesTab> {
  final supabase = Supabase.instance.client;
  final GameService svc = GameService();

  final TextEditingController _titleCtrl = TextEditingController(text: 'Дебаты');
  final TextEditingController _descCtrl = TextEditingController();

  bool _creating = false;
  bool _closing = false;

  // politicians list
  List<Map<String, dynamic>> _politicians = [];

  // speakers selection: maps color -> selected id (string) or null
  final Map<String, String?> _speakerA = {};
  final Map<String, String?> _speakerB = {};

  Map<String, dynamic>? _activeDebate;

  final List<_ColorDef> _colorDefs = const [
    _ColorDef(label: 'красный', hex: '#FF0000'),
    _ColorDef(label: 'зелёный', hex: '#00FF00'),
    _ColorDef(label: 'жёлтый', hex: '#FFFF00'),
    _ColorDef(label: 'малиновый', hex: '#FF00FF'),
    _ColorDef(label: 'синий', hex: '#0000FF'),
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _colorDefs) {
      _speakerA[c.label] = null;
      _speakerB[c.label] = null;
    }
    _loadPoliticians();
    _loadActiveDebate();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPoliticians() async {
    try {
      final res = await supabase.from('user_credentials').select('id, first_name, last_name, telegram_username').eq('role', 'politician').order('first_name');
      if (res is List) {
        _politicians = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _politicians = <Map<String, dynamic>>[];
      }
    } catch (_) {
      _politicians = <Map<String, dynamic>>[];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadActiveDebate() async {
    try {
      final row = await supabase.from('debates').select().eq('is_closed', false).order('created_at', ascending: false).limit(1).maybeSingle();
      if (row is Map<String, dynamic>) {
        _activeDebate = Map<String, dynamic>.from(row);
      } else {
        _activeDebate = null;
      }
    } catch (_) {
      _activeDebate = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _createDebate() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      // ensure no active debate
      final existing = await supabase.from('debates').select('id').eq('is_closed', false).limit(1).maybeSingle();
      if (existing != null) {
        throw Exception('Уже существует активный дебат. Закройте его перед созданием нового.');
      }

      // create debate row
      final debateInsert = {
        'title': _titleCtrl.text.trim().isEmpty ? 'Дебаты' : _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };

      final debateRes = await supabase.from('debates').insert(debateInsert).select().maybeSingle();
      if (debateRes == null || debateRes is! Map<String, dynamic> || debateRes['id'] == null) {
        throw Exception('Не удалось создать запись дебата');
      }
      final int debateId = (debateRes['id'] is int) ? debateRes['id'] as int : int.parse(debateRes['id'].toString());

      // create fixed options
      final List<Map<String, dynamic>> optionRows = [];
      for (final c in _colorDefs) {
        optionRows.add({'debate_id': debateId, 'label': c.label, 'color': c.label});
      }
      final optsRes = await supabase.from('debate_options').insert(optionRows).select();
      if (optsRes == null || optsRes is! List) {
        throw Exception('Не удалось создать варианты голосования');
      }
      // map color -> option_id
      final Map<String, int> colorToOptionId = {};
      for (final row in optsRes) {
        final m = Map<String, dynamic>.from(row as Map);
        final label = (m['label'] ?? '').toString();
        final id = (m['id'] is int) ? m['id'] as int : int.parse(m['id'].toString());
        colorToOptionId[label] = id;
      }

      // insert speakers if selected
      final List<Map<String, dynamic>> speakerInserts = [];
      for (final c in _colorDefs) {
        final optId = colorToOptionId[c.label];
        final sA = _speakerA[c.label];
        final sB = _speakerB[c.label];
        if (sA != null && sA.trim().isNotEmpty) {
          speakerInserts.add({'debate_id': debateId, 'option_id': optId, 'color': c.label, 'politician_id': sA});
        }
        if (sB != null && sB.trim().isNotEmpty && sB != sA) {
          speakerInserts.add({'debate_id': debateId, 'option_id': optId, 'color': c.label, 'politician_id': sB});
        }
      }
      if (speakerInserts.isNotEmpty) {
        await supabase.from('debate_speakers').insert(speakerInserts);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты успешно созданы')));
      }
      await _loadActiveDebate();
    } catch (e) {
      final msg = e is Exception ? e.toString() : 'Ошибка: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _closeDebate() async {
    if (_closing) return;
    if (_activeDebate == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет активного дебата')));
      return;
    }
    setState(() => _closing = true);
    try {
      final debateId = (_activeDebate!['id'] is int) ? _activeDebate!['id'] as int : int.parse(_activeDebate!['id'].toString());

      // call RPC via GameService; implement rpcCloseDebate(debateId: int) in GameService
      await GameService().rpcCloseDebate(debateId: debateId);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты закрыты')));
      await _loadActiveDebate();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка закрытия: $e')));
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Widget _buildSpeakerDropdown(String color, bool first) {
    final current = (first ? _speakerA[color] : _speakerB[color]);
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('- нет -')),
    ];
    for (final p in _politicians) {
      final id = p['id']?.toString();
      final name = ((p['first_name'] ?? '') as String).toString().trim().isEmpty
          ? (p['telegram_username'] ?? p['last_name'] ?? id ?? '—').toString()
          : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
      items.add(DropdownMenuItem<String?>(value: id, child: Text(name)));
    }
    return DropdownButton<String?>(
      value: current,
      isExpanded: true,
      items: items,
      onChanged: (v) {
        setState(() {
          if (first) {
            _speakerA[color] = v;
            if (_speakerB[color] == v) _speakerB[color] = null;
          } else {
            _speakerB[color] = v;
            if (_speakerA[color] == v) _speakerA[color] = null;
          }
        });
      },
    );
  }

  Widget _buildColorRow(_ColorDef c) {
    Color parsed;
    try {
      parsed = Color(int.parse('0xFF${c.hex.replaceFirst('#', '')}'));
    } catch (_) {
      parsed = Colors.grey;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Container(width: 14, height: 14, decoration: BoxDecoration(color: parsed, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black12))),
              const SizedBox(width: 8),
              Text(c.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Спикер A', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                _buildSpeakerDropdown(c.label, true),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Спикер B', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                _buildSpeakerDropdown(c.label, false),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _activeDebate != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Создать дебаты', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
              const SizedBox(height: 8),
              TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Описание (опционально)')),
              const SizedBox(height: 12),
              const Text('Назначить спикеров по цветам (максимум 2 на цвет)', style: TextStyle(color: Colors.black87)),
              const SizedBox(height: 8),
              ..._colorDefs.map((c) => _buildColorRow(c)).toList(),
              const SizedBox(height: 12),
              Row(children: [
                ElevatedButton(
                  onPressed: _creating ? null : _createDebate,
                  child: _creating ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать дебаты'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: hasActive && !_closing ? _closeDebate : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: _closing ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Закрыть текущие дебаты'),
                ),
              ])
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Текущее состояние', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_activeDebate != null) ...[
                Text('Активный дебат: ${_activeDebate?['title'] ?? '—'}'),
                const SizedBox(height: 6),
                Text('Описание: ${_activeDebate?['description'] ?? '—'}'),
                const SizedBox(height: 6),
                Text('Создан: ${_activeDebate?['created_at'] ?? '—'}'),
              ] else
                const Text('Нет активных дебатов'),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ----------------- ResolutionsTab (admin political resolutions) -----------------
class ResolutionsTab extends StatefulWidget {
  const ResolutionsTab({Key? key}) : super(key: key);
  @override
  State<ResolutionsTab> createState() => _ResolutionsTabState();
}

class _ResolutionsTabState extends State<ResolutionsTab> {
  final supabase = Supabase.instance.client;
  final GameService svc = GameService();

  // form controllers
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _selectedColor = 'зелёный';

  // dynamic options fields
  final List<TextEditingController> _optionCtrls = [];

  bool _creating = false;
  bool _loading = false;
  bool _closing = false;

  List<Map<String, dynamic>> _resolutions = [];

  // fixed colors (must match enum values in DB)
  static const List<String> fixedColors = [
    'зелёный',
    'красный',
    'синий',
    'жёлтый',
    'малиновый'
  ];

  @override
  void initState() {
    super.initState();
    _addOptionField(); // start with one option
    _loadResolutions();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOptionField() {
    final ctrl = TextEditingController();
    _optionCtrls.add(ctrl);
    setState(() {});
  }

  void _removeOptionField(int idx) {
    if (idx < 0 || idx >= _optionCtrls.length) return;
    _optionCtrls[idx].dispose();
    _optionCtrls.removeAt(idx);
    setState(() {});
  }

  Future<void> _loadResolutions() async {
    setState(() => _loading = true);
    try {
      // try selecting expected columns; if DB doesn't have some, fallback to select('*')
      try {
        final res = await supabase
            .from('political_resolutions')
            .select('id, title, description, created_by, created_at, is_closed, closed_at, total_m, winning_bet_id, winning_option_id')
            .order('created_at', ascending: false);
        if (res is List) {
          _resolutions = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          _resolutions = [];
        }
      } catch (e) {
        // fallback: select all columns (safer when schema differs)
        debugPrint('Resolutions: specific select failed, falling back to select(*): $e');
        final res2 = await supabase.from('political_resolutions').select('*').order('created_at', ascending: false);
        if (res2 is List) {
          _resolutions = res2.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          _resolutions = [];
        }
      }
    } catch (e) {
      _resolutions = [];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки политрешений: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createResolution() async {
    if (_creating) return;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите заголовок')));
      return;
    }

    final options = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавьте хотя бы один вариант ответа')));
      return;
    }

    setState(() => _creating = true);
    try {
      // insert resolution
      final payload = {
        'title': title,
        'description': _descCtrl.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };
      final res = await supabase.from('political_resolutions').insert(payload).select().maybeSingle();
      if (res == null || res['id'] == null) {
        throw Exception('Не удалось создать политрешение');
      }
      final int resolutionId = (res['id'] is int) ? res['id'] as int : int.parse(res['id'].toString());

      // insert options; include color selection for each option as default _selectedColor
      final optRows = options.map((label) => {'resolution_id': resolutionId, 'label': label, 'color': _selectedColor}).toList();
      await supabase.from('resolution_options').insert(optRows);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Политрешение и варианты созданы')));
      _titleCtrl.clear();
      _descCtrl.clear();
      for (final c in _optionCtrls) c.clear();
      // keep one option field
      while (_optionCtrls.length > 1) {
        _optionCtrls.removeLast().dispose();
      }

      await _loadResolutions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка создания: $e')));
    } finally {
      setState(() => _creating = false);
    }
  }

  Future<void> _addOptionToResolution(int resolutionId) async {
    final ctrl = TextEditingController();
    final added = await showDialog<String?>(context: context, builder: (_) => AlertDialog(
      title: const Text('Добавить вариант'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Вариант')),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(ctrl.text.trim()), child: const Text('Добавить')),
      ],
    ));

    if (added != null && added.isNotEmpty) {
      try {
        // new option gets default color _selectedColor
        await supabase.from('resolution_options').insert({'resolution_id': resolutionId, 'label': added, 'color': _selectedColor});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вариант добавлен')));
        await _loadResolutions();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка добавления варианта: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadOptionsForResolution(int resolutionId) async {
    try {
      final res = await supabase.from('resolution_options').select('id, label, color, created_at').eq('resolution_id', resolutionId).order('id');
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadResultsForResolution(int resolutionId) async {
    try {
      // resolution_results_admin view aggregates votes per option (admin-only)
      final res = await supabase.from('resolution_results_admin').select('option_id, label, votes_count, votes_sum').eq('resolution_id', resolutionId).order('votes_sum', ascending: false);
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e) {
      debugPrint('Failed to load results: $e');
      return [];
    }
  }

  Future<void> _closeResolution(int resolutionId) async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      final res = await svc.rpcCloseResolution(resolutionId: resolutionId);
      final msg = (res != null && (res['winning_option_label'] != null || res['winner'] != null))
          ? 'Резолюция закрыта. Победитель: ${res['winning_option_label'] ?? res['winner'] ?? ''}'
          : 'Резолюция закрыта';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _loadResolutions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка закрытия: $e')));
    } finally {
      setState(() => _closing = false);
    }
  }

  Widget _buildResolutionCard(Map<String, dynamic> r) {
    final closed = (r['is_closed'] == true);
    final id = (r['id'] is int) ? r['id'] as int : int.parse(r['id'].toString());
    final int? winningOptionId = r['winning_option_id'] == null
        ? null
        : (r['winning_option_id'] is int
            ? r['winning_option_id'] as int
            : int.tryParse(r['winning_option_id'].toString()));

    // combined future: load options + results together for consistent display
    final combinedFuture = Future.wait([
      _loadOptionsForResolution(id),
      _loadResultsForResolution(id),
    ]);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r['title'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (!closed)
              ElevatedButton(
                onPressed: () => _closeResolution(id),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Закрыть'),
              ),
          ]),
          const SizedBox(height: 6),
          Text('Описание: ${r['description'] ?? '-'}'),
          const SizedBox(height: 6),
          Text('Создано: ${r['created_at'] ?? '-'}'),
          if (r['is_closed'] == true) ...[
            const SizedBox(height: 6),
            Text('Закрыто: ${r['closed_at'] ?? '-'}'),
            const SizedBox(height: 6),
            // total_m may be present; otherwise we will display aggregated sum from results
            Text('Всего вложено (M): ${r['total_m'] ?? '-'}'),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 8),
          FutureBuilder<List<dynamic>>(
            future: combinedFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
              if (!snap.hasData) {
                return const Text('Нет вариантов/ставок или ошибка при загрузке результатов.');
              }
              final opts = (snap.data![0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
              final results = (snap.data![1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

              // build map: option_id -> result row
              final Map<int, Map<String, dynamic>> resMap = {};
              num aggregatedTotal = 0;
              for (final rr in results) {
                final oid = (rr['option_id'] is int) ? rr['option_id'] as int : int.tryParse(rr['option_id']?.toString() ?? '') ?? 0;
                resMap[oid] = rr;
                final sum = (rr['votes_sum'] is num) ? (rr['votes_sum'] as num) : num.tryParse(rr['votes_sum']?.toString() ?? '') ?? 0;
                aggregatedTotal += sum;
              }

              // determine winning option label/color if closed or if winningOptionId available
              Map<String, dynamic>? winningOption;
              if (winningOptionId != null) {
                try {
                  winningOption = opts.firstWhere((o) {
                    final oid = (o['id'] is int) ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                    return oid == winningOptionId;
                  });
                } catch (_) {
                  winningOption = null;
                }
              } else {
                // if no explicit winner stored but results available, pick highest votes_sum
                if (results.isNotEmpty) {
                  results.sort((a, b) {
                    final sa = (a['votes_sum'] is num) ? (a['votes_sum'] as num) : num.tryParse(a['votes_sum']?.toString() ?? '') ?? 0;
                    final sb = (b['votes_sum'] is num) ? (b['votes_sum'] as num) : num.tryParse(b['votes_sum']?.toString() ?? '') ?? 0;
                    return sb.compareTo(sa);
                  });
                  final topOid = (results[0]['option_id'] is int) ? results[0]['option_id'] as int : int.tryParse(results[0]['option_id']?.toString() ?? '') ?? 0;
                  try {
                    winningOption = opts.firstWhere((o) {
                      final oid = (o['id'] is int) ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                      return oid == topOid;
                    });
                  } catch (_) {
                    winningOption = null;
                  }
                }
              }

              // display total sum if r['total_m'] is absent, show aggregatedTotal
              final totalToShow = (r['total_m'] != null) ? r['total_m'] : aggregatedTotal;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Варианты и ставки (детально):', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  // list options with per-option aggregated values
                  ...opts.map((o) {
                    final oid = (o['id'] is int) ? o['id'] as int : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                    final label = (o['label'] ?? '-').toString();
                    final color = (o['color'] ?? '-').toString();
                    final resRow = resMap[oid];
                    final sum = resRow != null ? ((resRow['votes_sum'] is num) ? (resRow['votes_sum'] as num) : num.tryParse(resRow['votes_sum']?.toString() ?? '') ?? 0) : 0;
                    final cnt = resRow != null ? ((resRow['votes_count'] is num) ? (resRow['votes_count'] as num).toInt() : int.tryParse(resRow['votes_count']?.toString() ?? '') ?? 0) : 0;

                    final isWinner = (winningOption != null) && ((winningOption['id'] is int ? winningOption['id'] : int.tryParse(winningOption['id']?.toString() ?? '')) == oid);

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(label, style: TextStyle(fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600))),
                                if (isWinner)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.yellow.shade100, borderRadius: BorderRadius.circular(12)),
                                    child: const Text('Победитель', style: TextStyle(fontSize: 12)),
                                  ),
                              ]),
                              const SizedBox(height: 6),
                              Text('Ставок: $cnt  •  Сумма: ${sum.toString()}'),
                            ]),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(color, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 6),
                            Text('id:${oid}', style: const TextStyle(color: Colors.black45, fontSize: 12)),
                          ]),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  // totals and winner summary
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Итого вложено (M): $totalToShow', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        if (closed)
                          Text(
                            winningOption != null
                                ? 'Победивший вариант: ${winningOption['label']} [${winningOption['color'] ?? '-'}]'
                                : 'Победивший вариант: —',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        if (!closed)
                          Text(
                            winningOption != null
                                ? 'Текущий лидер: ${winningOption['label']} [${winningOption['color'] ?? '-'}]'
                                : 'Текущий лидер: —',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ]),
                    ),
                  ]),
                ],
              );
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadResolutions,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Создать политрешение', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Заголовок')),
                const SizedBox(height: 8),
                TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Описание (опционально)')),
                // removed resolution-level color per request (colors are per-option)
                const SizedBox(height: 12),
                const Text('Варианты ответа:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._optionCtrls.asMap().entries.map((e) {
                  final idx = e.key;
                  final ctrl = e.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(children: [
                      Expanded(child: TextField(controller: ctrl, decoration: InputDecoration(labelText: 'Вариант ${idx + 1}'))),
                      const SizedBox(width: 8),
                      IconButton(
                          onPressed: () {
                            if (_optionCtrls.length <= 1) return;
                            _removeOptionField(idx);
                          },
                          icon: const Icon(Icons.delete, color: Colors.redAccent)),
                    ]),
                  );
                }).toList(),
                Row(children: [
                  ElevatedButton.icon(onPressed: _addOptionField, icon: const Icon(Icons.add), label: const Text('Добавить поле варианта')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating ? null : _createResolution,
                    child: _creating ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Создать политрешение'),
                  ),
                ])
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Список политрешений', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_resolutions.isEmpty)
                  const Text('Нет политрешений')
                else
                  Column(children: _resolutions.map((r) => _buildResolutionCard(r)).toList()),
              ]),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ----------------- ColorBanksTab -----------------
class ColorBanksTab extends StatefulWidget {
  const ColorBanksTab({Key? key}) : super(key: key);
  @override
  State<ColorBanksTab> createState() => _ColorBanksTabState();
}

class _ColorBanksTabState extends State<ColorBanksTab> {
  final supabase = Supabase.instance.client;

  static const List<String> fixedColors = [
    'зелёный',
    'красный',
    'синий',
    'жёлтый',
    'малиновый'
  ];

  Map<String, num> _balances = {};
  bool _loading = false;

  // history cache per color
  final Map<String, List<Map<String, dynamic>>> _historyCache = {};
  final Map<String, bool> _loadingHistory = {};

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    setState(() => _loading = true);
    try {
      final res = await supabase.from('color_banks').select('*');
      final Map<String, num> map = {};
      if (res is List) {
        for (final r in res) {
          final row = Map<String, dynamic>.from(r as Map);
          final color = (row['color'] ?? '').toString();
          num val = 0;
          if (row.containsKey('m_balance') && row['m_balance'] != null) {
            val = (row['m_balance'] is num) ? row['m_balance'] as num : num.tryParse(row['m_balance'].toString()) ?? 0;
          } else if (row.containsKey('balance') && row['balance'] != null) {
            val = (row['balance'] is num) ? row['balance'] as num : num.tryParse(row['balance'].toString()) ?? 0;
          } else if (row.containsKey('amount') && row['amount'] != null) {
            val = (row['amount'] is num) ? row['amount'] as num : num.tryParse(row['amount'].toString()) ?? 0;
          }
          if (color.isNotEmpty) map[color] = val;
        }
      }
      for (final c in fixedColors) {
        map.putIfAbsent(c, () => 0);
      }
      setState(() => _balances = map);
    } catch (e) {
      debugPrint('Failed to load color_banks: $e');
      final Map<String, num> map = {};
      for (final c in fixedColors) map[c] = _balances[c] ?? 0;
      setState(() => _balances = map);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadHistory(String color) async {
    if (_historyCache.containsKey(color)) return _historyCache[color]!;
    _loadingHistory[color] = true;
    try {
      // try color_bank_history table first
      try {
        final hist = await supabase
            .from('color_bank_history')
            .select('id, amount, comment, created_at')
            .eq('color', color)
            .order('created_at', ascending: false)
            .limit(500);
        if (hist is List) {
          final list = hist.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _historyCache[color] = list;
          return list;
        }
      } catch (e) {
        debugPrint('color_bank_history query failed or missing, falling back to derived: $e');
      }

      // fallback: derive from closed resolutions
      final resRows = await supabase
          .from('political_resolutions')
          .select('id, title, closed_at')
          .eq('is_closed', true)
          .order('closed_at', ascending: false)
          .limit(200);

      final List<Map<String, dynamic>> derived = [];
      if (resRows is List) {
        for (final rr in resRows) {
          final r = Map<String, dynamic>.from(rr as Map);
          final int resId = (r['id'] is int) ? r['id'] as int : int.tryParse(r['id'].toString()) ?? 0;
          final String title = (r['title'] ?? '').toString();
          final closedAt = r['closed_at'];

          final opts = await supabase
              .from('resolution_options')
              .select('id, label')
              .eq('resolution_id', resId)
              .eq('color', color);
          if (opts is! List || opts.isEmpty) continue;
          final List<int> optionIds = [];
          for (final o in opts) {
            final mo = Map<String, dynamic>.from(o as Map);
            final oid = (mo['id'] is int) ? mo['id'] as int : int.tryParse(mo['id'].toString()) ?? 0;
            if (oid > 0) optionIds.add(oid);
          }
          if (optionIds.isEmpty) continue;

          final bets = await supabase
              .from('political_bets')
              .select('amount, option_id, created_at')
              .eq('resolution_id', resId);
          if (bets is! List || bets.isEmpty) continue;

          num sumForColor = 0;
          DateTime? lastBetAt;
          for (final b in bets) {
            final mb = Map<String, dynamic>.from(b as Map);
            final oid = (mb['option_id'] is int) ? mb['option_id'] as int : int.tryParse(mb['option_id']?.toString() ?? '') ?? 0;
            if (!optionIds.contains(oid)) continue;
            final amt = (mb['amount'] is num) ? (mb['amount'] as num) : num.tryParse(mb['amount']?.toString() ?? '') ?? 0;
            sumForColor += amt;
            if (mb['created_at'] != null) {
              try {
                final dt = DateTime.tryParse(mb['created_at'].toString());
                if (dt != null && (lastBetAt == null || dt.isAfter(lastBetAt))) lastBetAt = dt;
              } catch (_) {}
            }
          }

          if (sumForColor > 0) {
            derived.add({
              'amount': sumForColor,
              'comment': 'Резолюция #$resId — ${title.isEmpty ? 'без названия' : title}',
              'created_at': closedAt ?? (lastBetAt?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String()),
              'resolution_id': resId,
            });
          }
        }
      }

      derived.sort((a, b) {
        final da = a['created_at']?.toString() ?? '';
        final db = b['created_at']?.toString() ?? '';
        final dta = DateTime.tryParse(da) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dtb = DateTime.tryParse(db) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dtb.compareTo(dta);
      });

      _historyCache[color] = derived;
      return derived;
    } catch (e, st) {
      debugPrint('_loadHistory error: $e\n$st');
      _historyCache[color] = [];
      return [];
    } finally {
      _loadingHistory[color] = false;
    }
  }

  Future<void> _showHistory(String color) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Map<String, dynamic>> hist = [];
    try {
      hist = await _loadHistory(color);
    } catch (e) {
      hist = [];
    } finally {
      if (mounted) Navigator.of(context).pop();
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('История по цвету: $color'),
        content: SizedBox(
          width: double.maxFinite,
          child: hist.isEmpty
              ? const Text('История недоступна или отсутствует.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: hist.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (context, i) {
                          final row = hist[i];
                          final amt = (row['amount'] is num) ? row['amount'].toString() : row['amount']?.toString() ?? '-';
                          final comment = row['comment']?.toString() ?? (row['resolution_id'] != null ? 'Резолюция #${row['resolution_id']}' : '-');
                          final created = row['created_at']?.toString() ?? '-';
                          String readableDate;
                          try {
                            final dt = DateTime.tryParse(created);
                            readableDate = dt != null ? '${dt.toLocal()}' : created;
                          } catch (_) {
                            readableDate = created;
                          }
                          return ListTile(
                            dense: true,
                            title: Text('$amt M'),
                            subtitle: Text(comment),
                            trailing: Text(readableDate, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadBanks,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    const Expanded(child: Text('Банки цветов', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                    IconButton(onPressed: _loadBanks, icon: const Icon(Icons.refresh)),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  Column(
                    children: fixedColors.map((c) {
                      final val = _balances[c] ?? 0;
                      Color parsed;
                      try {
                        switch (c) {
                          case 'зелёный':
                            parsed = const Color(0xFF00FF00);
                            break;
                          case 'красный':
                            parsed = const Color(0xFFFF0000);
                            break;
                          case 'синий':
                            parsed = const Color(0xFF0000FF);
                            break;
                          case 'жёлтый':
                            parsed = const Color(0xFFFFFF00);
                            break;
                          case 'малиновый':
                            parsed = const Color(0xFFFF00FF);
                            break;
                          default:
                            parsed = Colors.grey;
                        }
                      } catch (_) {
                        parsed = Colors.grey;
                      }
                      return ListTile(
                        leading: Container(width: 16, height: 16, decoration: BoxDecoration(color: parsed, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black12))),
                        title: Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Текущий баланс: ${val.toString()} M'),
                        trailing: TextButton(onPressed: () => _showHistory(c), child: const Text('История')),
                      );
                    }).toList(),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _ColorDef {
  final String label;
  final String hex;
  const _ColorDef({required this.label, required this.hex});
}
