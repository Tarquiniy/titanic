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
  static const double _baseEnterprisePrice = 200.0;
  static const String _supranationalInstitutesType =
      '\u041d\u0430\u0434\u043d\u0430\u0446\u0438\u043e\u043d\u0430\u043b\u044c\u043d\u044b\u0435 \u0438\u043d\u0441\u0442\u0438\u0442\u0443\u0442\u044b';
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  String? _selectedColor;
  String? _selectedRegion;
  String? _selectedEnterpriseType;

  List<_InvestorRow> _investors = [];
  List<Map<String, dynamic>> _players = [];

  final List<String> _fixedRegions = [
    'Азиатская группа',
    'Англа-саксонская группа',
    'Предсоциалистический блок',
    'Пиренейская группа',
    'Центрально-европейская группа',
  ];

  final List<String> _enterpriseTypes = const [
    'Чёрная металлургия',
    'Лёгкая промышленность',
    'Сельское хозяйство',
    'Инфраструктура и транспорт',
    'Финансово-торговый сектор',
    'Наднациональные институты',
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

  double get _enterprisePrice {
    if (_selectedEnterpriseType == _supranationalInstitutesType) {
      return _baseEnterprisePrice * 2;
    }
    return _baseEnterprisePrice;
  }

  @override
  void initState() {
    super.initState();

    // Цвет предприятия = цвет покупающего пользователя (экономиста).
    // В user.color хранится название ("синий", "красный"...).
    // Здесь переводим название в hex из _colorOptions только для отображения кружка в UI.
    final userColorName = (widget.currentUser.color ?? '').toString().toLowerCase().trim();
    final hex = _colorOptions[userColorName];
    _selectedColor = hex ?? _colorOptions.values.first;

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
    final region = _selectedRegion ?? widget.currentUser.region ?? '';
    final enterpriseType = _selectedEnterpriseType ?? '';

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
      final fresh = await supabase.from('user_credentials').select('m_balance, enterprises').eq('id', widget.currentUser.id).maybeSingle();
      if (fresh is! Map<String, dynamic>) throw 'Не удалось получить профиль';
      final mbalRaw = fresh['m_balance'];
      final currentBalance = (mbalRaw is num) ? mbalRaw.toDouble() : double.tryParse(mbalRaw?.toString() ?? '') ?? 0.0;
      final enterprisePrice = _enterprisePrice;
      if (currentBalance < enterprisePrice) {
        setState(() => _loading = false);
        _showError('\u041d\u0435\u0434\u043e\u0441\u0442\u0430\u0442\u043e\u0447\u043d\u043e M: \u0442\u0440\u0435\u0431\u0443\u0435\u0442\u0441\u044f ${enterprisePrice.toStringAsFixed(0)}, \u0443 \u0432\u0430\u0441 ${currentBalance.toStringAsFixed(2)}');
        return;
      }

      dynamic enterprises = fresh['enterprises'];
      List<dynamic> entList = [];
      if (enterprises == null) {
        entList = [];
      } else if (enterprises is String) {
        try {
          final d = jsonDecode(enterprises);
          if (d is List) entList = List.from(d);
          else if (d is Map) entList = [d];
        } catch (_) {
          entList = [];
        }
      } else if (enterprises is List) {
        entList = List.from(enterprises);
      } else if (enterprises is Map) {
        entList = [enterprises];
      } else {
        entList = [];
      }

      // ✅ Объект предприятия, который хранится в user_credentials.enterprises (json)
      // Важно: color хранится словом (widget.currentUser.color)
      // ✅ NEW: добавляем p_payout = 200
      final Map<String, dynamic> enterprise = {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': name,
        'region': region,
        'enterprise_type': enterpriseType,
        'color': widget.currentUser.color,
        'investors': investorsLog,
        'created_at': DateTime.now().toIso8601String(),
        'p_payout': enterprisePrice,
      };

      entList.add(enterprise);

      final newBalance = currentBalance - enterprisePrice;
      final updateObj = {
        'm_balance': newBalance,
        'enterprises': entList,
      };

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
      builder: (context) {
        List<Map<String, dynamic>> filtered = List.from(_players);
        return StatefulBuilder(builder: (context, setModal) {
          filtered = _players.where((p) {
            final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''} ${p['telegram_username'] ?? ''}'.toLowerCase();
            return n.contains(query.toLowerCase());
          }).toList();
          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Поиск игрока'),
                  onChanged: (v) => setModal(() => query = v),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 320,
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final label = (((p['first_name'] ?? '').toString().trim().isEmpty)
                              ? (p['telegram_username'] ?? '')
                              : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}')
                          .toString();
                      return ListTile(
                        title: Text(label),
                        onTap: () => Navigator.pop(context, p['id']?.toString()),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorHex = _selectedColor ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Купить предприятие')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Название предприятия'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
              ),
              const SizedBox(height: 12),

              // Цвет фиксируется автоматически по пользователю
              Row(
                children: [
                  const Text('Цвет:'),
                  const SizedBox(width: 12),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hexToColor(colorHex) ?? Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.currentUser.color ?? '—'),
                ],
              ),

              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: (_selectedRegion != null && _fixedRegions.contains(_selectedRegion))
                    ? _selectedRegion
                    : (_fixedRegions.contains(widget.currentUser.region) ? widget.currentUser.region : null),
                decoration: const InputDecoration(labelText: 'Регион'),
                items: _fixedRegions.toSet().map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => _selectedRegion = v),
                validator: (v) => (v == null || v.isEmpty) ? 'Выберите регион' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedEnterpriseType,
                decoration: const InputDecoration(labelText: 'Тип предприятия'),
                items: _enterpriseTypes
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedEnterpriseType = value),
                validator: (value) => (value == null || value.isEmpty) ? 'Выберите тип предприятия' : null,
              ),
              const SizedBox(height: 14),

              Align(
                alignment: Alignment.centerLeft,
                child: Text('Инвесторы (до 10)', style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 8),

              for (int i = 0; i < _investors.length; i++) _buildInvestorRow(i),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _investors.length >= 10 ? null : _addInvestorRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить инвестора'),
                ),
              ),

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _onSubmit,
                child: _loading ? const CircularProgressIndicator() : Text('\u041a\u0443\u043f\u0438\u0442\u044c (${_enterprisePrice.toStringAsFixed(0)} M)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvestorRow(int index) {
    final row = _investors[index];
    final selectedId = row.selectedPlayerId;
    final selectedPlayer = _players.firstWhere(
      (p) => p['id']?.toString() == selectedId,
      orElse: () => {},
    );
    final selectedLabel = selectedPlayer.isEmpty
        ? (selectedId == null ? 'Выберите игрока' : 'Игрок')
        : (((selectedPlayer['first_name'] ?? '').toString().trim().isEmpty)
                ? (selectedPlayer['telegram_username'] ?? '')
                : '${selectedPlayer['first_name'] ?? ''} ${selectedPlayer['last_name'] ?? ''}')
            .toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(selectedLabel)),
              TextButton(
                onPressed: () async {
                  final picked = await _showPlayerPicker(index);
                  if (picked == null) return;
                  setState(() => row.selectedPlayerId = picked);
                },
                child: const Text('Выбрать'),
              ),
              if (_investors.length > 1)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeInvestorRow(index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.controllerAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Сумма (M)'),
          ),
        ],
      ),
    );
  }

  Color? _hexToColor(String hex) {
    if (!hex.startsWith('#')) return null;
    try {
      final h = hex.substring(1);
      final v = int.parse(h, radix: 16);
      return Color(h.length == 6 ? (0xFF000000 | v) : v);
    } catch (_) {
      return null;
    }
  }
}

class _InvestorRow {
  String? selectedPlayerId;
  final TextEditingController controllerAmount = TextEditingController();
}
