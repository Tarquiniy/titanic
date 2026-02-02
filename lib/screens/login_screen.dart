// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/decorative_elements.dart';
import '../widgets/art_deco_button.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'package:titanic/services/persistent_storage.dart';
import 'package:titanic/models/app_user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _trySavedLogin();
  }

  Future<void> _trySavedLogin() async {
    try {
      final id = await getSavedUserId();
      if (id == null || id.isEmpty) return;
      final row = await supabase
          .from('user_credentials')
          .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance, color, region')
          .eq('id', id)
          .maybeSingle();
      if (row is Map<String, dynamic>) {
        final user = AppUser(
          id: row['id']?.toString() ?? '',
          username: row['telegram_username']?.toString() ?? '',
          role: row['role']?.toString() ?? 'public_figure',
          firstName: row['first_name']?.toString() ?? '',
          lastName: row['last_name']?.toString() ?? '',
          vBalance: (row['v_balance'] is num) ? (row['v_balance'] as num).toDouble() : 0.0,
          mBalance: (row['m_balance'] is num) ? (row['m_balance'] as num).toDouble() : 0.0,
          color: row['color']?.toString(),
          region: row['region']?.toString(),
        );
        if ((row['role'] ?? '').toString().toLowerCase() == 'admin') {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminScreen()));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(currentUser: user)));
        }
      }
    } catch (_) {}
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
    });
    final username = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите username и пароль');
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('user_credentials')
          .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance, password, color, region')
          .eq('telegram_username', username)
          .maybeSingle();
      if (data == null) {
        setState(() => _error = 'Неверный username или пароль');
        return;
      }
      final row = Map<String, dynamic>.from(data as Map);
      final stored = (row['password'] ?? '').toString();
      if (stored.isEmpty || stored != password) {
        setState(() => _error = 'Неверный username или пароль');
        return;
      }
      final user = AppUser(
        id: row['id']?.toString() ?? '',
        username: row['telegram_username']?.toString() ?? username,
        role: row['role']?.toString() ?? 'public_figure',
        firstName: row['first_name']?.toString() ?? '',
        lastName: row['last_name']?.toString() ?? '',
        vBalance: (row['v_balance'] is num) ? (row['v_balance'] as num).toDouble() : 0.0,
        mBalance: (row['m_balance'] is num) ? (row['m_balance'] as num).toDouble() : 0.0,
        color: row['color']?.toString(),
        region: row['region']?.toString(),
      );
      try {
        await saveUserId(user.id);
      } catch (_) {}
      if ((row['role'] ?? '').toString().toLowerCase() == 'admin') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminScreen()));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(currentUser: user)));
      }
    } catch (e) {
      setState(() => _error = 'Ошибка: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({required String label, required Icon prefix}) {
    // enhance base decoration with white label + subtle translucent fill
    return TitanicTheme.inputDecoration.copyWith(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.92), fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      prefixIcon: prefix,
      // ensure border contrasts nicely on the glass panel
      enabledBorder: TitanicTheme.inputDecoration.enabledBorder,
      focusedBorder: TitanicTheme.inputDecoration.focusedBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecorativeBackground(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        showEmblem: true,
        patternIntensity: 0.28, // a bit stronger pattern
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                radius: 18,
                elevated: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // header emblem
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: TitanicTheme.goldGradient,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.38), blurRadius: 12, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: TitanicTheme.nearBlack,
                        child: Icon(Icons.directions_boat, size: 44, color: TitanicTheme.gold),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('TITANIC', style: TitanicTheme.heading.copyWith(fontSize: 38, letterSpacing: 6)),
                    const SizedBox(height: 6),
                    Text('Добро пожаловать',
                        style: TitanicTheme.body.copyWith(fontSize: 14, color: TitanicTheme.body.color?.withOpacity(0.88))),
                    const SizedBox(height: 18),

                    // form fields: TEXT STYLE WHITE & cursor gold
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: TitanicTheme.gold,
                      decoration: _fieldDecoration(
                        label: 'Telegram Username',
                        prefix: Icon(Icons.person, color: TitanicTheme.gold),
                      ),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: TitanicTheme.gold,
                      decoration: _fieldDecoration(
                        label: 'Пароль',
                        prefix: Icon(Icons.lock, color: TitanicTheme.gold),
                      ),
                      onSubmitted: (_) {
                        if (!_loading) _signIn();
                      },
                    ),
                    const SizedBox(height: 16),

                    // decorative thin divider with gold accent
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [TitanicTheme.gold.withOpacity(0.0), TitanicTheme.gold.withOpacity(0.45), TitanicTheme.gold.withOpacity(0.0)]),
                      ),
                    ),

                    // error message (stylized)
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.08)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.redAccent),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: TitanicTheme.body.copyWith(color: Colors.redAccent))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ArtDecoButton(
                            text: 'ВОЙТИ',
                            icon: Icons.login,
                            primary: true,
                            loading: _loading,
                            onPressed: _loading ? null : _signIn,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
