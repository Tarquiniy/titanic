// lib/screens/purchase_enterprise_screen.dart
// This is a complete implementation copied/adapted from your previous logic.
// It provides the PurchaseEnterpriseScreen used by HomeScreen.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/models/app_user.dart';

class PurchaseEnterpriseScreen extends StatefulWidget {
  final AppUser currentUser;
  const PurchaseEnterpriseScreen({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<PurchaseEnterpriseScreen> createState() => _PurchaseEnterpriseScreenState();
}

class _PurchaseEnterpriseScreenState extends State<PurchaseEnterpriseScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  String? _selectedColor;
  String? _selectedRegion;

  List<_InvestorRow> _investors = [];
  List<Map<String, dynamic>> _players = [];

  final List<String> _fixedRegions = [
    'Азиатская группа',
    'Англа-саксонская группа',
    'Предсоциалистический блок',
    'Пиренейская группа',
    'Центрально-европейская группа',
  ];

  final Map<String, String> _colorOptions = {
    'красный': '#F44336',
    'зелёный': '#4CAF50',
    'синий': '#2196F3',
    'малиновый': '#E91E63',
    'жёлтый': '#FFC107',
  };

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _investors.add(_InvestorRow());
    _loadPlayers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final r in _investors) {
      r.controllerAmount.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlayers() async {
    try {
      final res = await supabase.from('user_credentials').select('id, telegram_username, first_name, last_name').order('first_name');
      if (res is List) {
        _players = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _addInvestorRow() {
    if (_investors.length >= 10) return;
    setState(() => _investors.add(_InvestorRow()));
  }

  void _removeInvestorRow(int idx) {
    if (idx < 0 || idx >= _investors.length) return;
    setState(() => _investors.removeAt(idx));
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final name = _nameCtrl.text.trim();
    final colorHex = _selectedColor ?? '';
    final region = _selectedRegion ?? widget.currentUser.region ?? '';

    final List<Map<String, dynamic>> investorsLog = [];
    for (final row in _investors) {
      final pid = row.selectedPlayerId;
      final amt = row.controllerAmount.text.trim();
      if ((pid == null || pid.toString().isEmpty) && (amt.isEmpty)) continue;
      final player = _players.firstWhere((p) => p['id']?.toString() == pid, orElse: () => {});
      final playerName = player.isNotEmpty
          ? (((player['first_name'] ?? '').toString().trim().isEmpty) ? (player['telegram_username'] ?? '') : '${player['first_name'] ?? ''} ${player['last_name'] ?? ''}')
          : '';
      investorsLog.add({'player_id': pid, 'player_name': playerName, 'minds': amt});
    }

    try {
      final fresh = await supabase.from('user_credentials').select('v_balance, inventory').eq('id', widget.currentUser.id).maybeSingle();
      if (fresh is! Map<String, dynamic>) throw 'Не удалось получить профиль';
      final vbalRaw = fresh['v_balance'];
      final currentBalance = (vbalRaw is num) ? vbalRaw.toDouble() : double.tryParse(vbalRaw?.toString() ?? '') ?? 0.0;
      if (currentBalance < 200.0) {
        setState(() => _loading = false);
        _showError('Недостаточно V: требуется 200, у вас ${currentBalance.toStringAsFixed(2)}');
        return;
      }

      dynamic inv = fresh['inventory'];
      List<dynamic> invList = [];
      if (inv == null) invList = [];
      else if (inv is String) {
        try {
          final d = jsonDecode(inv);
          if (d is List) invList = List.from(d);
          else if (d is Map) invList = [d];
        } catch (_) {
          invList = [];
        }
      } else if (inv is List) invList = List.from(inv);
      else if (inv is Map) invList = [inv];
      else invList = [];

      final Map<String, dynamic> enterpriseItem = {
        'name': 'Предприятие: $name',
        'count': 0,
        'meta': {
          'color': colorHex,
          'region': region,
          'investors': investorsLog,
          'created_at': DateTime.now().toIso8601String(),
        },
      };

      invList.add(enterpriseItem);
      final newBalance = currentBalance - 200.0;
      final updateObj = {'v_balance': newBalance, 'inventory': invList};

      final upd = await supabase.from('user_credentials').update(updateObj).eq('id', widget.currentUser.id).select().maybeSingle();
      if (upd == null) throw 'Не удалось сохранить предприятие (сервер вернул null)';

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError('Ошибка при покупке: $e');
      setState(() => _loading = false);
    }
  }

  void _showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<String?> _showPlayerPicker(int index) async {
    String query = '';
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        List<Map<String, dynamic>> filtered = List.from(_players);
        return StatefulBuilder(builder: (ctx2, setStateSheet) {
          void doFilter(String q) {
            query = q;
            final ql = q.trim().toLowerCase();
            if (ql.isEmpty) filtered = List.from(_players);
            else {
              filtered = _players.where((p) {
                final fn = (p['first_name'] ?? '').toString().toLowerCase();
                final ln = (p['last_name'] ?? '').toString().toLowerCase();
                final un = (p['telegram_username'] ?? '').toString().toLowerCase();
                return fn.contains(ql) || ln.contains(ql) || un.contains(ql);
              }).toList();
            }
            setStateSheet(() {});
          }

          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: Column(
                children: [
                  Padding(padding: const EdgeInsets.all(12.0), child: TextField(decoration: const InputDecoration(hintText: 'Поиск игрока', prefixIcon: Icon(Icons.search)), onChanged: (s) => doFilter(s))),
                  const Divider(height: 0),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, idx) {
                        if (idx == 0) return ListTile(title: const Text('— выбрать пустым —'), onTap: () => Navigator.of(ctx).pop(null));
                        final p = filtered[idx - 1];
                        final id = p['id']?.toString();
                        final name = ((p['first_name'] ?? '') as String).toString().trim().isEmpty ? (p['telegram_username'] ?? '').toString() : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}';
                        return ListTile(title: Text(name), onTap: () => Navigator.of(ctx).pop(id));
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Купить предприятие'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Название предприятия'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Цвет:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedColor,
                          items: _colorOptions.entries.map((e) => DropdownMenuItem(value: e.value, child: Row(children: [Container(width: 18, height: 18, color: Color(int.parse(e.value.substring(1), radix: 16) | 0xFF000000)), const SizedBox(width: 8), Text(e.key)])) ).toList(),
                          onChanged: (v) => setState(() => _selectedColor = v),
                          decoration: const InputDecoration(hintText: 'Выберите цвет'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Выберите цвет' : null,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Регион:'),
                      const SizedBox(width: 12),
                      Expanded(child: DropdownButtonFormField<String>(value: _selectedRegion ?? widget.currentUser.region, items: _fixedRegions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(), onChanged: (v) => setState(() => _selectedRegion = v), decoration: const InputDecoration(hintText: 'Выберите регион'), validator: (v) => (v == null || v.isEmpty) ? 'Выберите регион' : null)),
                    ]),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Инвесторы (до 10)', style: TextStyle(fontWeight: FontWeight.w600)), TextButton(onPressed: _investors.length >= 10 ? null : _addInvestorRow, child: const Text('Добавить инвестора'))]),
                    const SizedBox(height: 8),
                    ..._buildInvestorRows(),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: _onSubmit, child: const Text('Купить (200 V)')),
                    const SizedBox(height: 12),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildInvestorRows() {
    final List<Widget> rows = [];
    for (var i = 0; i < _investors.length; i++) {
      final r = _investors[i];
      final selectedName = _players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId, orElse: () => {}).isNotEmpty
          ? (_players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId)['first_name']?.toString().trim().isEmpty ?? true
              ? (_players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId)['telegram_username'] ?? '')
              : '${_players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId)['first_name'] ?? ''} ${_players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId)['last_name'] ?? ''}')
          : null;
      rows.add(Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final selected = await _showPlayerPicker(i);
                    setState(() {
                      r.selectedPlayerId = selected;
                    });
                  },
                  child: AbsorbPointer(
                    child: TextFormField(
                      decoration: InputDecoration(labelText: 'Игрок', hintText: '— выбрать игрока —', suffixIcon: const Icon(Icons.search)),
                      controller: TextEditingController(text: selectedName ?? ''),
                      readOnly: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: TextFormField(controller: r.controllerAmount, decoration: const InputDecoration(labelText: 'Майндов'), keyboardType: TextInputType.text)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _removeInvestorRow(i)),
            ]),
          ]),
        ),
      ));
    }
    return rows;
  }
}

class _InvestorRow {
  String? selectedPlayerId;
  final TextEditingController controllerAmount = TextEditingController();
  _InvestorRow({this.selectedPlayerId});
}
