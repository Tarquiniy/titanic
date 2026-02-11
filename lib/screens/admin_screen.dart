// lib/admin_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/services/persistent_storage.dart';
import 'login_screen.dart';
import 'package:titanic/screens/movie_poll_admin_screen.dart';
import 'package:titanic/screens/admin/blood_poker_tab.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

// Перечисление пунктов бокового меню
enum AdminDrawerItem {
  users,
  colorBanks,
  debates,
  resolutions,
  bloodPoker,
  moviePoll,
  economist, // заглушка для экономистов
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final supabase = Supabase.instance.client;
  AdminDrawerItem _selectedItem = AdminDrawerItem.users; // по умолчанию пользователи

  Future<void> _logout() async {
    try {
      await removeSavedUserId();
    } catch (_) {}
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// Возвращает виджет для выбранного пункта меню
  Widget _buildBody() {
    switch (_selectedItem) {
      case AdminDrawerItem.users:
        return const UsersTab();
      case AdminDrawerItem.colorBanks:
        return const ColorBanksTab();
      case AdminDrawerItem.debates:
        return const DebatesTab();
      case AdminDrawerItem.resolutions:
        return const ResolutionsTab();
      case AdminDrawerItem.bloodPoker:
        return const BloodPokerTab();
      case AdminDrawerItem.moviePoll:
        return const MoviePollAdminScreen();
      case AdminDrawerItem.economist:
        // Заглушка для экономистов (можно развить позже)
        return const _EconomistPlaceholder();
    }
  }

  /// Заголовок экрана в зависимости от выбранного пункта
  String _getTitle() {
    switch (_selectedItem) {
      case AdminDrawerItem.users:
        return 'Список игроков';
      case AdminDrawerItem.colorBanks:
        return 'Банки цветов';
      case AdminDrawerItem.debates:
        return 'Дебаты (политики)';
      case AdminDrawerItem.resolutions:
        return 'Политрешения';
      case AdminDrawerItem.bloodPoker:
        return 'Покер на крови (мафия)';
      case AdminDrawerItem.moviePoll:
        return 'Голосование за фильм';
      case AdminDrawerItem.economist:
        return 'Управление экономистами';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 380;

    return Scaffold(
      backgroundColor: TitanicTheme.abyssalBlue,
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: TitanicTheme.heading.copyWith(fontSize: isSmall ? 18 : 20),
        ),
        backgroundColor: TitanicTheme.abyssalBlue.withOpacity(0.95),
        elevation: 0,
        iconTheme: TitanicTheme.iconTheme,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            color: TitanicTheme.raptureGold,
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Меню',
          ),
        ),
        actions: [
          ArtDecoIconButton(
            icon: Icons.logout,
            onPressed: _logout,
            tooltip: 'Выйти',
          ),
        ],
      ),
      drawer: _buildDrawer(isSmall),
      body: _buildBody(),
    );
  }

  /// Строим боковое меню с группировкой по ролям
  Widget _buildDrawer(bool isSmall) {
    return Drawer(
      backgroundColor: TitanicTheme.surfaceNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              TitanicTheme.surfaceNavy.withOpacity(0.95),
              TitanicTheme.abyssalBlue.withOpacity(0.98),
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Шапка Drawer
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    TitanicTheme.abyssalBlue,
                    TitanicTheme.surfaceNavy,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: TitanicTheme.raptureGold.withOpacity(0.3),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: TitanicTheme.goldGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings,
                          color: Colors.black87,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'TITANIC',
                              style: TitanicTheme.titleLarge.copyWith(
                                fontSize: 20,
                                color: TitanicTheme.raptureGold,
                              ),
                            ),
                            Text(
                              'Администратор',
                              style: TitanicTheme.body.copyWith(
                                fontSize: 14,
                                color: TitanicTheme.ivoryCream.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // === ОБЩИЕ РАЗДЕЛЫ ===
            _buildDrawerTile(
              icon: Icons.people,
              label: 'Список игроков',
              item: AdminDrawerItem.users,
              isSmall: isSmall,
            ),
            _buildDrawerTile(
              icon: Icons.account_balance,
              label: 'Банк цветов',
              item: AdminDrawerItem.colorBanks,
              isSmall: isSmall,
            ),

            const Divider(
              color: Color(0xFFD4AF37),
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              height: 24,
            ),

            // === ПОЛИТИКИ ===
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
              child: Text(
                'ПОЛИТИКИ',
                style: TextStyle(
                  color: TitanicTheme.seaFoamGreen,
                  fontSize: isSmall ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _buildDrawerTile(
              icon: Icons.forum,
              label: 'Дебаты',
              item: AdminDrawerItem.debates,
              isSmall: isSmall,
            ),
            _buildDrawerTile(
              icon: Icons.gavel,
              label: 'Политрешения',
              item: AdminDrawerItem.resolutions,
              isSmall: isSmall,
            ),

            // === МАФИЯ ===
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
              child: Text(
                'МАФИЯ',
                style: TextStyle(
                  color: Colors.redAccent.shade200,
                  fontSize: isSmall ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _buildDrawerTile(
              icon: Icons.casino,
              label: 'Покер на крови',
              item: AdminDrawerItem.bloodPoker,
              isSmall: isSmall,
            ),

            // === ГОЛЛИВУД ===
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
              child: Text(
                'ГОЛЛИВУД',
                style: TextStyle(
                  color: TitanicTheme.raptureGold,
                  fontSize: isSmall ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _buildDrawerTile(
              icon: Icons.movie,
              label: 'Голосование за фильм',
              item: AdminDrawerItem.moviePoll,
              isSmall: isSmall,
            ),

            // === ЭКОНОМИСТЫ ===
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
              child: Text(
                'ЭКОНОМИСТЫ',
                style: TextStyle(
                  color: TitanicTheme.copperDetail,
                  fontSize: isSmall ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _buildDrawerTile(
              icon: Icons.business_center,
              label: 'Управление',
              item: AdminDrawerItem.economist,
              isSmall: isSmall,
            ),

            const SizedBox(height: 20),
            // Кнопка выхода внизу (дублирующая, но может быть удобно)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ArtDecoButton(
                text: 'Выйти',
                icon: Icons.logout,
                onPressed: _logout,
                primary: false,
                expanded: true,
                customColor: Colors.redAccent.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Универсальная плитка для Drawer с подсветкой выбранного элемента
  Widget _buildDrawerTile({
    required IconData icon,
    required String label,
    required AdminDrawerItem item,
    required bool isSmall,
  }) {
    final isSelected = _selectedItem == item;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: isSelected
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  TitanicTheme.raptureGold.withOpacity(0.2),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? TitanicTheme.raptureGold
              : TitanicTheme.ivoryCream.withOpacity(0.7),
          size: isSmall ? 22 : 24,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? TitanicTheme.raptureGold
                : TitanicTheme.ivoryCream.withOpacity(0.9),
            fontSize: isSmall ? 14 : 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selected: isSelected,
        selectedTileColor: Colors.transparent,
        onTap: () {
          setState(() {
            _selectedItem = item;
          });
          Navigator.of(context).pop(); // закрываем drawer
        },
      ),
    );
  }
}

// ==================== ВСПОМОГАТЕЛЬНЫЙ ВИДЖЕТ-ЗАГЛУШКА ДЛЯ ЭКОНОМИСТОВ ====================
class _EconomistPlaceholder extends StatelessWidget {
  const _EconomistPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TitanicTheme.copperDetail.withOpacity(0.15),
                border: Border.all(
                  color: TitanicTheme.copperDetail.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.business_center,
                size: 50,
                color: TitanicTheme.copperDetail,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Управление экономистами',
              style: TitanicTheme.titleLarge.copyWith(
                fontSize: isSmall ? 20 : 22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Здесь будет размещён функционал для работы с экономистами:\n'
              '- Покупка ходов\n'
              '- Управление предприятиями\n'
              '- Статистика по регионам\n\n'
              'Функция находится в разработке.',
              textAlign: TextAlign.center,
              style: TitanicTheme.body,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------- ОСТАЛЬНЫЕ ВКЛАДКИ (UsersTab, DebatesTab, ResolutionsTab, ColorBanksTab) -----------------
// Полностью идентичны предыдущей версии, поэтому оставляем их без изменений.
// (Код вставлен ниже для полноты, но он не менялся)

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
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('user_credentials')
          .select(
              'id, telegram_username, first_name, last_name, role, v_balance, m_balance, color, inventory, enterprises')
          .order('first_name');
      if (res is List) {
        _users = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _users = [];
      }
    } catch (e) {
      _users = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: TitanicTheme.copperDetail,
          ),
        );
      }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сохранено')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось сохранить: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    final visible = _users.where((u) {
      final q = _filter.toLowerCase();
      if (q.isEmpty) return true;
      return (u['telegram_username'] ?? '').toString().toLowerCase().contains(q) ||
          (u['first_name'] ?? '').toString().toLowerCase().contains(q) ||
          (u['last_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(isSmall ? 8 : 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: TitanicTheme.inputDecoration.copyWith(
                    hintText: 'Поиск username/имя/фамилия',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: isSmall ? 12 : 14,
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 12),
              ArtDecoButton(
                text: _loading ? '' : 'Обновить',
                loading: _loading,
                icon: Icons.refresh,
                onPressed: _loadUsers,
                width: isSmall ? 56 : 100,
                padding: EdgeInsets.symmetric(
                  vertical: isSmall ? 10 : 12,
                  horizontal: isSmall ? 8 : 16,
                ),
                primary: false,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmall ? 8 : 12,
                    vertical: 8,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = visible[i];
                    final name =
                        ((u['first_name'] ?? '') + ' ' + (u['last_name'] ?? '')).trim();
                    final displayName = name.isEmpty
                        ? (u['telegram_username'] ?? 'Без имени')
                        : name;
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: TitanicTheme.raptureGold.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: isSmall ? 6 : 8,
                        ),
                        title: Text(
                          displayName,
                          style: TitanicTheme.subtitle.copyWith(
                            fontSize: isSmall ? 14 : 16,
                          ),
                        ),
                        subtitle: Text(
                          'role: ${u['role'] ?? '-'}  '
                          'V:${(u['v_balance'] ?? 0).toStringAsFixed(0)}  '
                          'M:${(u['m_balance'] ?? 0).toStringAsFixed(0)}',
                          style: TitanicTheme.body.copyWith(
                            fontSize: isSmall ? 12 : 13,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          color: TitanicTheme.raptureGold,
                          iconSize: isSmall ? 22 : 26,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: () => _editUser(u),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
  bool _usurer = false;

  @override
  void initState() {
    super.initState();
    _vCtrl = TextEditingController(text: (widget.user['v_balance'] ?? '').toString());
    _mCtrl = TextEditingController(text: (widget.user['m_balance'] ?? '').toString());
    _roleCtrl = TextEditingController(text: (widget.user['role'] ?? '').toString());
    _colorCtrl = TextEditingController(text: (widget.user['color'] ?? '').toString());
    _inventoryCtrl = TextEditingController(text: jsonEncode(widget.user['inventory'] ?? {}));
    _enterprisesCtrl = TextEditingController(text: jsonEncode(widget.user['enterprises'] ?? {}));
    _usurer = (widget.user['usurer'] == true) ||
        (widget.user['usurer']?.toString().toLowerCase() == 'true');
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
    out['usurer'] = _usurer;
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
    final isSmall = MediaQuery.of(context).size.width < 380;
    return AlertDialog(
      title: Text(
        'Редактировать пользователя',
        style: TitanicTheme.titleLarge,
      ),
      backgroundColor: TitanicTheme.panelDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.4), width: 1.5),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _roleCtrl,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'role',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isSmall ? 12 : 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vCtrl,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'V balance',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isSmall ? 12 : 14,
                ),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mCtrl,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'M balance',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isSmall ? 12 : 14,
                ),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _colorCtrl,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'color (hex)',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isSmall ? 12 : 14,
                ),
              ),
            ),
            CheckboxListTile(
              title: const Text('Ростовщик (только для мафии)'),
              value: _usurer,
              onChanged: (value) {
                setState(() {
                  _usurer = value ?? false;
                });
              },
              activeColor: TitanicTheme.raptureGold,
              checkColor: TitanicTheme.abyssalBlue,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inventoryCtrl,
              minLines: 2,
              maxLines: 6,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'inventory (JSON)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _enterprisesCtrl,
              minLines: 2,
              maxLines: 6,
              decoration: TitanicTheme.inputDecoration.copyWith(
                labelText: 'enterprises (JSON)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_buildPayload()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// ----------------- DebatesTab -----------------
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

  List<Map<String, dynamic>> _politicians = [];
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
      final res = await supabase
          .from('user_credentials')
          .select('id, first_name, last_name, telegram_username')
          .eq('role', 'politician')
          .order('first_name');
      _politicians = (res is List)
          ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    } catch (_) {
      _politicians = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadActiveDebate() async {
    try {
      final row = await supabase
          .from('debates')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _activeDebate = (row is Map<String, dynamic>) ? Map<String, dynamic>.from(row) : null;
    } catch (_) {
      _activeDebate = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _createDebate() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final existing = await supabase
          .from('debates')
          .select('id')
          .eq('is_closed', false)
          .limit(1)
          .maybeSingle();
      if (existing != null) {
        throw Exception('Уже существует активный дебат. Закройте его перед созданием нового.');
      }

      final debateInsert = {
        'title': _titleCtrl.text.trim().isEmpty ? 'Дебаты' : _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };

      final debateRes = await supabase
          .from('debates')
          .insert(debateInsert)
          .select()
          .maybeSingle();
      if (debateRes == null || debateRes is! Map<String, dynamic> || debateRes['id'] == null) {
        throw Exception('Не удалось создать запись дебата');
      }
      final int debateId = (debateRes['id'] is int)
          ? debateRes['id'] as int
          : int.parse(debateRes['id'].toString());

      final List<Map<String, dynamic>> optionRows = [];
      for (final c in _colorDefs) {
        optionRows.add({'debate_id': debateId, 'label': c.label, 'color': c.label});
      }
      final optsRes = await supabase.from('debate_options').insert(optionRows).select();
      if (optsRes == null || optsRes is! List) {
        throw Exception('Не удалось создать варианты голосования');
      }

      final Map<String, int> colorToOptionId = {};
      for (final row in optsRes) {
        final m = Map<String, dynamic>.from(row as Map);
        final label = (m['label'] ?? '').toString();
        final id = (m['id'] is int) ? m['id'] as int : int.parse(m['id'].toString());
        colorToOptionId[label] = id;
      }

      final List<Map<String, dynamic>> speakerInserts = [];
      for (final c in _colorDefs) {
        final optId = colorToOptionId[c.label];
        final sA = _speakerA[c.label];
        final sB = _speakerB[c.label];
        if (sA != null && sA.trim().isNotEmpty) {
          speakerInserts.add({
            'debate_id': debateId,
            'option_id': optId,
            'color': c.label,
            'politician_id': sA,
          });
        }
        if (sB != null && sB.trim().isNotEmpty && sB != sA) {
          speakerInserts.add({
            'debate_id': debateId,
            'option_id': optId,
            'color': c.label,
            'politician_id': sB,
          });
        }
      }
      if (speakerInserts.isNotEmpty) {
        await supabase.from('debate_speakers').insert(speakerInserts);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дебаты успешно созданы')),
        );
      }
      await _loadActiveDebate();
    } catch (e) {
      final msg = e is Exception ? e.toString() : 'Ошибка: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _closeDebate() async {
    if (_closing) return;
    if (_activeDebate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет активного дебата')),
        );
      }
      return;
    }
    setState(() => _closing = true);
    try {
      final debateId = (_activeDebate!['id'] is int)
          ? _activeDebate!['id'] as int
          : int.parse(_activeDebate!['id'].toString());

      await GameService().rpcCloseDebate(debateId: debateId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дебаты закрыты')),
        );
      }
      await _loadActiveDebate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка закрытия: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Widget _buildSpeakerDropdown(String color, bool first) {
    final isSmall = MediaQuery.of(context).size.width < 380;
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
    return Container(
      padding: EdgeInsets.symmetric(vertical: isSmall ? 4 : 6),
      child: DropdownButton<String?>(
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
        underline: Container(
          height: 1,
          color: TitanicTheme.raptureGold.withOpacity(0.3),
        ),
        icon: Icon(
          Icons.arrow_drop_down,
          color: TitanicTheme.raptureGold,
        ),
        style: TitanicTheme.body.copyWith(fontSize: 14),
      ),
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 400;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: parsed,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      c.label,
                      style: TitanicTheme.subtitle.copyWith(
                        fontSize: isNarrow ? 14 : 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!isNarrow)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Спикер A',
                                style: TitanicTheme.body.copyWith(fontSize: 12)),
                            const SizedBox(height: 6),
                            _buildSpeakerDropdown(c.label, true),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Спикер B',
                                style: TitanicTheme.body.copyWith(fontSize: 12)),
                            const SizedBox(height: 6),
                            _buildSpeakerDropdown(c.label, false),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Спикер A',
                              style: TitanicTheme.body.copyWith(fontSize: 12)),
                          const SizedBox(height: 6),
                          _buildSpeakerDropdown(c.label, true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Спикер B',
                              style: TitanicTheme.body.copyWith(fontSize: 12)),
                          const SizedBox(height: 6),
                          _buildSpeakerDropdown(c.label, false),
                        ],
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;
    final hasActive = _activeDebate != null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: TitanicTheme.raptureGold.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(isSmall ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Создать дебаты',
                    style: TitanicTheme.titleLarge.copyWith(
                      fontSize: isSmall ? 18 : 20,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleCtrl,
                    decoration: TitanicTheme.inputDecoration.copyWith(
                      labelText: 'Заголовок',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    decoration: TitanicTheme.inputDecoration.copyWith(
                      labelText: 'Описание (опционально)',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Назначить спикеров по цветам (макс. 2 на цвет)',
                    style: TitanicTheme.body,
                  ),
                  const SizedBox(height: 12),
                  ..._colorDefs.map((c) => _buildColorRow(c)).toList(),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ArtDecoButton(
                        text: 'Создать дебаты',
                        onPressed: _creating ? null : _createDebate,
                        loading: _creating,
                        primary: true,
                      ),
                      ArtDecoButton(
                        text: 'Закрыть текущие дебаты',
                        onPressed: hasActive && !_closing ? _closeDebate : null,
                        loading: _closing,
                        primary: false,
                        customColor: Colors.redAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(isSmall ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Текущее состояние',
                    style: TitanicTheme.titleLarge.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  if (_activeDebate != null) ...[
                    Text(
                      'Активный дебат: ${_activeDebate?['title'] ?? '—'}',
                      style: TitanicTheme.body,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Описание: ${_activeDebate?['description'] ?? '—'}',
                      style: TitanicTheme.body,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Создан: ${_activeDebate?['created_at'] ?? '—'}',
                      style: TitanicTheme.body,
                    ),
                  ] else
                    Text(
                      'Нет активных дебатов',
                      style: TitanicTheme.body,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- ResolutionsTab -----------------
class ResolutionsTab extends StatefulWidget {
  const ResolutionsTab({Key? key}) : super(key: key);
  @override
  State<ResolutionsTab> createState() => _ResolutionsTabState();
}

class _ResolutionsTabState extends State<ResolutionsTab> {
  final supabase = Supabase.instance.client;
  final GameService svc = GameService();

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  String _selectedColor = 'зелёный';

  final List<TextEditingController> _optionCtrls = [];

  bool _creating = false;
  bool _loading = false;
  bool _closing = false;

  List<Map<String, dynamic>> _resolutions = [];

  static const List<String> fixedColors = [
    'зелёный',
    'красный',
    'синий',
    'жёлтый',
    'малиновый',
  ];

  @override
  void initState() {
    super.initState();
    _addOptionField();
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
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOptionField(int idx) {
    if (idx < 0 || idx >= _optionCtrls.length) return;
    _optionCtrls[idx].dispose();
    setState(() => _optionCtrls.removeAt(idx));
  }

  Future<void> _loadResolutions() async {
    setState(() => _loading = true);
    try {
      try {
        final res = await supabase
            .from('political_resolutions')
            .select(
                'id, title, description, created_by, created_at, is_closed, closed_at, total_m, winning_bet_id, winning_option_id')
            .order('created_at', ascending: false);
        _resolutions = (res is List)
            ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      } catch (e) {
        final res2 = await supabase
            .from('political_resolutions')
            .select('*')
            .order('created_at', ascending: false);
        _resolutions = (res2 is List)
            ? res2.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      }
    } catch (e) {
      _resolutions = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки политрешений: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createResolution() async {
    if (_creating) return;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите заголовок')),
      );
      return;
    }

    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы один вариант ответа')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final payload = {
        'title': title,
        'description': _descCtrl.text.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_closed': false,
      };
      final res = await supabase
          .from('political_resolutions')
          .insert(payload)
          .select()
          .maybeSingle();
      if (res == null || res['id'] == null) {
        throw Exception('Не удалось создать политрешение');
      }
      final int resolutionId = (res['id'] is int)
          ? res['id'] as int
          : int.parse(res['id'].toString());

      final optRows = options.map((label) => {
            'resolution_id': resolutionId,
            'label': label,
            'color': _selectedColor,
          }).toList();
      await supabase.from('resolution_options').insert(optRows);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Политрешение и варианты созданы')),
        );
      }
      _titleCtrl.clear();
      _descCtrl.clear();
      for (final c in _optionCtrls) c.clear();
      while (_optionCtrls.length > 1) {
        _optionCtrls.removeLast().dispose();
      }

      await _loadResolutions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания: $e')),
        );
      }
    } finally {
      setState(() => _creating = false);
    }
  }

  Future<void> _addOptionToResolution(int resolutionId) async {
    final ctrl = TextEditingController();
    final added = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить вариант'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Вариант'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (added != null && added.isNotEmpty) {
      try {
        await supabase.from('resolution_options').insert({
          'resolution_id': resolutionId,
          'label': added,
          'color': _selectedColor,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Вариант добавлен')),
          );
        }
        await _loadResolutions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка добавления варианта: $e')),
          );
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadOptionsForResolution(
      int resolutionId) async {
    try {
      final res = await supabase
          .from('resolution_options')
          .select('id, label, color, created_at')
          .eq('resolution_id', resolutionId)
          .order('id');
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadResultsForResolution(
      int resolutionId) async {
    try {
      final res = await supabase
          .from('resolution_results_admin')
          .select('option_id, label, votes_count, votes_sum')
          .eq('resolution_id', resolutionId)
          .order('votes_sum', ascending: false);
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
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
      final msg = (res != null &&
              (res['winning_option_label'] != null || res['winner'] != null))
          ? 'Резолюция закрыта. Победитель: ${res['winning_option_label'] ?? res['winner'] ?? ''}'
          : 'Резолюция закрыта';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      await _loadResolutions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка закрытия: $e')),
        );
      }
    } finally {
      setState(() => _closing = false);
    }
  }

  Widget _buildResolutionCard(Map<String, dynamic> r) {
    final isSmall = MediaQuery.of(context).size.width < 380;
    final closed = (r['is_closed'] == true);
    final id = (r['id'] is int) ? r['id'] as int : int.parse(r['id'].toString());
    final int? winningOptionId = r['winning_option_id'] == null
        ? null
        : (r['winning_option_id'] is int
            ? r['winning_option_id'] as int
            : int.tryParse(r['winning_option_id'].toString()));

    final combinedFuture = Future.wait([
      _loadOptionsForResolution(id),
      _loadResultsForResolution(id),
    ]);

    return Card(
      margin: EdgeInsets.symmetric(vertical: isSmall ? 8 : 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r['title'] ?? '—',
                    style: TitanicTheme.titleLarge.copyWith(
                      fontSize: isSmall ? 16 : 18,
                    ),
                  ),
                ),
                if (!closed)
                  ArtDecoButton(
                    text: 'Закрыть',
                    onPressed: () => _closeResolution(id),
                    primary: false,
                    customColor: Colors.redAccent,
                    width: 100,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Описание: ${r['description'] ?? '-'}',
              style: TitanicTheme.body,
            ),
            const SizedBox(height: 6),
            Text(
              'Создано: ${r['created_at'] ?? '-'}',
              style: TitanicTheme.body,
            ),
            if (r['is_closed'] == true) ...[
              const SizedBox(height: 6),
              Text(
                'Закрыто: ${r['closed_at'] ?? '-'}',
                style: TitanicTheme.body,
              ),
              const SizedBox(height: 6),
              Text(
                'Всего вложено (M): ${r['total_m'] ?? '-'}',
                style: TitanicTheme.body,
              ),
            ],
            const SizedBox(height: 12),
            FutureBuilder<List<dynamic>>(
              future: combinedFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return Text(
                    'Нет вариантов/ставок или ошибка при загрузке результатов.',
                    style: TitanicTheme.body,
                  );
                }
                final opts = (snap.data![0] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final results = (snap.data![1] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();

                final Map<int, Map<String, dynamic>> resMap = {};
                num aggregatedTotal = 0;
                for (final rr in results) {
                  final oid = (rr['option_id'] is int)
                      ? rr['option_id'] as int
                      : int.tryParse(rr['option_id']?.toString() ?? '') ?? 0;
                  resMap[oid] = rr;
                  final sum = (rr['votes_sum'] is num)
                      ? (rr['votes_sum'] as num)
                      : num.tryParse(rr['votes_sum']?.toString() ?? '') ?? 0;
                  aggregatedTotal += sum;
                }

                Map<String, dynamic>? winningOption;
                if (winningOptionId != null) {
                  try {
                    winningOption = opts.firstWhere((o) {
                      final oid = (o['id'] is int)
                          ? o['id'] as int
                          : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                      return oid == winningOptionId;
                    });
                  } catch (_) {
                    winningOption = null;
                  }
                } else {
                  if (results.isNotEmpty) {
                    results.sort((a, b) {
                      final sa = (a['votes_sum'] is num)
                          ? (a['votes_sum'] as num)
                          : num.tryParse(a['votes_sum']?.toString() ?? '') ?? 0;
                      final sb = (b['votes_sum'] is num)
                          ? (b['votes_sum'] as num)
                          : num.tryParse(b['votes_sum']?.toString() ?? '') ?? 0;
                      return sb.compareTo(sa);
                    });
                    final topOid = (results[0]['option_id'] is int)
                        ? results[0]['option_id'] as int
                        : int.tryParse(results[0]['option_id']?.toString() ?? '') ?? 0;
                    try {
                      winningOption = opts.firstWhere((o) {
                        final oid = (o['id'] is int)
                            ? o['id'] as int
                            : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                        return oid == topOid;
                      });
                    } catch (_) {
                      winningOption = null;
                    }
                  }
                }

                final totalToShow = (r['total_m'] != null) ? r['total_m'] : aggregatedTotal;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Варианты и ставки (детально):',
                      style: TitanicTheme.subtitle.copyWith(
                        fontSize: isSmall ? 14 : 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...opts.map((o) {
                      final oid = (o['id'] is int)
                          ? o['id'] as int
                          : int.tryParse(o['id']?.toString() ?? '') ?? 0;
                      final label = (o['label'] ?? '-').toString();
                      final color = (o['color'] ?? '-').toString();
                      final resRow = resMap[oid];
                      final sum = resRow != null
                          ? ((resRow['votes_sum'] is num)
                              ? (resRow['votes_sum'] as num)
                              : num.tryParse(resRow['votes_sum']?.toString() ?? '') ?? 0)
                          : 0;
                      final cnt = resRow != null
                          ? ((resRow['votes_count'] is num)
                              ? (resRow['votes_count'] as num).toInt()
                              : int.tryParse(resRow['votes_count']?.toString() ?? '') ?? 0)
                          : 0;

                      final isWinner = (winningOption != null) &&
                          ((winningOption['id'] is int
                                  ? winningOption['id']
                                  : int.tryParse(winningOption['id']?.toString() ?? '')) ==
                              oid);

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: EdgeInsets.all(isSmall ? 12 : 14),
                        decoration: BoxDecoration(
                          color: TitanicTheme.surfaceNavy.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isWinner
                                ? TitanicTheme.raptureGold
                                : TitanicTheme.raptureGold.withOpacity(0.1),
                            width: isWinner ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontWeight: isWinner
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isWinner
                                          ? TitanicTheme.raptureGold
                                          : TitanicTheme.ivoryCream,
                                      fontSize: isSmall ? 14 : 15,
                                    ),
                                  ),
                                ),
                                if (isWinner)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: TitanicTheme.raptureGold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: TitanicTheme.raptureGold,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'Победитель',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: TitanicTheme.raptureGold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ставок: $cnt  •  Сумма: ${sum.toString()}',
                              style: TitanicTheme.body.copyWith(
                                fontSize: isSmall ? 12 : 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Цвет: $color  (id:$oid)',
                              style: TextStyle(
                                color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Итого вложено (M): $totalToShow',
                          style: TitanicTheme.subtitle.copyWith(
                            fontSize: isSmall ? 14 : 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (closed || !closed)
                          Text(
                            winningOption != null
                                ? (closed
                                    ? 'Победивший вариант: ${winningOption['label']} [${winningOption['color'] ?? '-'}]'
                                    : 'Текущий лидер: ${winningOption['label']} [${winningOption['color'] ?? '-'}]')
                                : (closed
                                    ? 'Победивший вариант: —'
                                    : 'Текущий лидер: —'),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: TitanicTheme.seaFoamGreen,
                              fontSize: isSmall ? 13 : 14,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return RefreshIndicator(
      onRefresh: _loadResolutions,
      color: TitanicTheme.raptureGold,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: TitanicTheme.raptureGold.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Создать политрешение',
                      style: TitanicTheme.titleLarge.copyWith(
                        fontSize: isSmall ? 18 : 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleCtrl,
                      decoration: TitanicTheme.inputDecoration.copyWith(
                        labelText: 'Заголовок',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      decoration: TitanicTheme.inputDecoration.copyWith(
                        labelText: 'Описание (опционально)',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Варианты ответа:',
                      style: TitanicTheme.subtitle,
                    ),
                    const SizedBox(height: 12),
                    ..._optionCtrls.asMap().entries.map((e) {
                      final idx = e.key;
                      final ctrl = e.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                decoration: TitanicTheme.inputDecoration.copyWith(
                                  labelText: 'Вариант ${idx + 1}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_optionCtrls.length > 1)
                              IconButton(
                                onPressed: () => _removeOptionField(idx),
                                icon: const Icon(Icons.delete),
                                color: TitanicTheme.copperDetail,
                                iconSize: isSmall ? 22 : 26,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ArtDecoButton(
                          text: 'Добавить вариант',
                          icon: Icons.add,
                          onPressed: _addOptionField,
                          primary: false,
                        ),
                        ArtDecoButton(
                          text: 'Создать политрешение',
                          onPressed: _creating ? null : _createResolution,
                          loading: _creating,
                          primary: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Список политрешений',
                      style: TitanicTheme.titleLarge.copyWith(
                        fontSize: isSmall ? 16 : 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_resolutions.isEmpty)
                      Center(
                        child: Text(
                          'Нет политрешений',
                          style: TitanicTheme.body,
                        ),
                      )
                    else
                      Column(
                        children: _resolutions.map((r) => _buildResolutionCard(r)).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
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
    'малиновый',
  ];

  Map<String, num> _balances = {};
  bool _loading = false;

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
            val = (row['m_balance'] is num)
                ? row['m_balance'] as num
                : num.tryParse(row['m_balance'].toString()) ?? 0;
          } else if (row.containsKey('balance') && row['balance'] != null) {
            val = (row['balance'] is num)
                ? row['balance'] as num
                : num.tryParse(row['balance'].toString()) ?? 0;
          } else if (row.containsKey('amount') && row['amount'] != null) {
            val = (row['amount'] is num)
                ? row['amount'] as num
                : num.tryParse(row['amount'].toString()) ?? 0;
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
          final int resId = (r['id'] is int)
              ? r['id'] as int
              : int.tryParse(r['id'].toString()) ?? 0;
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
            final oid = (mo['id'] is int)
                ? mo['id'] as int
                : int.tryParse(mo['id'].toString()) ?? 0;
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
            final oid = (mb['option_id'] is int)
                ? mb['option_id'] as int
                : int.tryParse(mb['option_id']?.toString() ?? '') ?? 0;
            if (!optionIds.contains(oid)) continue;
            final amt = (mb['amount'] is num)
                ? (mb['amount'] as num)
                : num.tryParse(mb['amount']?.toString() ?? '') ?? 0;
            sumForColor += amt;
            if (mb['created_at'] != null) {
              try {
                final dt = DateTime.tryParse(mb['created_at'].toString());
                if (dt != null && (lastBetAt == null || dt.isAfter(lastBetAt)))
                  lastBetAt = dt;
              } catch (_) {}
            }
          }

          if (sumForColor > 0) {
            derived.add({
              'amount': sumForColor,
              'comment': 'Резолюция #$resId — ${title.isEmpty ? 'без названия' : title}',
              'created_at': closedAt ??
                  (lastBetAt?.toUtc().toIso8601String() ??
                      DateTime.now().toUtc().toIso8601String()),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
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
        title: Text(
          'История по цвету: $color',
          style: TitanicTheme.titleLarge,
        ),
        backgroundColor: TitanicTheme.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.4), width: 1.5),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: hist.isEmpty
              ? Text(
                  'История недоступна или отсутствует.',
                  style: TitanicTheme.body,
                )
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
                          final amt = (row['amount'] is num)
                              ? row['amount'].toString()
                              : row['amount']?.toString() ?? '-';
                          final comment = row['comment']?.toString() ??
                              (row['resolution_id'] != null
                                  ? 'Резолюция #${row['resolution_id']}'
                                  : '-');
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
                            title: Text('$amt M', style: TitanicTheme.subtitle),
                            subtitle: Text(comment, style: TitanicTheme.body),
                            trailing: Text(
                              readableDate,
                              style: TextStyle(
                                fontSize: 11,
                                color: TitanicTheme.ivoryCream.withOpacity(0.5),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return RefreshIndicator(
      onRefresh: _loadBanks,
      color: TitanicTheme.raptureGold,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: TitanicTheme.raptureGold.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Банки цветов',
                            style: TitanicTheme.titleLarge.copyWith(
                              fontSize: isSmall ? 18 : 20,
                            ),
                          ),
                        ),
                        ArtDecoIconButton(
                          icon: Icons.refresh,
                          onPressed: _loadBanks,
                          tooltip: 'Обновить',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: TitanicTheme.raptureGold.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: parsed,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                              title: Text(
                                c,
                                style: TitanicTheme.subtitle.copyWith(
                                  fontSize: isSmall ? 15 : 16,
                                ),
                              ),
                              subtitle: Text(
                                'Текущий баланс: ${val.toString()} M',
                                style: TitanicTheme.body,
                              ),
                              trailing: ArtDecoButton(
                                text: 'История',
                                onPressed: () => _showHistory(c),
                                primary: false,
                                width: 100,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ColorDef {
  final String label;
  final String hex;
  const _ColorDef({required this.label, required this.hex});
}