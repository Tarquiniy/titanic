// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import 'home_screen.dart';
import 'admin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkSavedLogin();
  }

  Future<void> _checkSavedLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('saved_user_id');
      if (savedId == null || savedId.isEmpty) return;

      // try to fetch profile by id
      final data = await _supabase
          .from('user_credentials')
          .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance, color, region')
          .eq('id', savedId)
          .maybeSingle();

      if (data == null) {
        await prefs.remove('saved_user_id');
        return;
      }

      final row = Map<String, dynamic>.from(data as Map);
      final user = AppUser(
        id: row['id']?.toString() ?? '',
        username: row['telegram_username']?.toString() ?? '',
        role: row['role']?.toString() ?? 'public_figure',
        firstName: row['first_name']?.toString() ?? '',
        lastName: row['last_name']?.toString() ?? '',
        vBalance: (row['v_balance'] is num) ? (row['v_balance'] as num).toDouble() : 0.0,
        mBalance: (row['m_balance'] is num) ? (row['m_balance'] as num).toDouble() : 0.0,
        color: row['color']?.toString(),
        region: row['region'] is String ? row['region'] as String : (row['region']?.toString()),
      );

      if (!mounted) return;
      final role = (row['role'] ?? '').toString().toLowerCase();
      if (role == 'admin') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminScreen()));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(user: user)));
      }
    } catch (_) {
      // ignore — remain on login screen
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
    });

    if (!_formKey.currentState!.validate()) return;
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('user_credentials')
          .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance, password, color, region')
          .eq('telegram_username', username)
          .maybeSingle();

      if (data == null) {
        setState(() => _error = 'Неверный username или пароль');
        return;
      }

      final row = Map<String, dynamic>.from(data as Map);

      final storedPassword = (row['password'] ?? '').toString();
      if (storedPassword.isEmpty || storedPassword != password) {
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
        region: row['region'] is String ? row['region'] as String : (row['region']?.toString()),
      );

      if (!mounted) return;

      // Persist logged-in user id
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_user_id', user.id);
      } catch (_) {
        // ignore preferences errors
      }

      final role = (row['role'] ?? '').toString().toLowerCase();
      if (role == 'admin') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminScreen()));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomeScreen(user: user)));
      }
    } on PostgrestException catch (e) {
      setState(() => _error = 'Ошибка сервера: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Ошибка: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите telegram username без @';
    if (v.contains('@')) return 'Не указывайте @';
    if (v.contains(' ')) return 'Username не должен содержать пробелов';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Вход', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(labelText: 'Telegram username (без @)'),
                    textInputAction: TextInputAction.next,
                    validator: _validateUsername,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(labelText: 'Пароль'),
                    obscureText: true,
                    onFieldSubmitted: (_) => _signIn(),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Войти'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
