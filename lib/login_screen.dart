// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';
import 'home_screen.dart';

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
      // --- Правильный современный вызов Supabase ---
      // .select(...) без generic, затем .eq(...).maybeSingle()
      final data = await _supabase
          .from('user_credentials')
          .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance')
          .eq('telegram_username', username)
          .eq('password', password)
          .maybeSingle(); // вернёт Map<String, dynamic>? или null

      // Если ошибка соединения / сервера — SDK обычно бросит исключение,
      // поэтому мы ловим исключения в catch.
      if (data == null) {
        setState(() => _error = 'Неверный username или пароль');
        return;
      }

      // Приведение типов: data — динамический Map
      final row = Map<String, dynamic>.from(data as Map);

      final user = AppUser(
        id: row['id']?.toString() ?? '',
        username: row['telegram_username'] ?? username,
        role: row['role'] ?? 'public_figure',
        firstName: row['first_name'] ?? '',
        lastName: row['last_name'] ?? '',
        vBalance: (row['v_balance'] is num) ? (row['v_balance'] as num).toDouble() : 0.0,
        mBalance: (row['m_balance'] is num) ? (row['m_balance'] as num).toDouble() : 0.0,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      );
    } on PostgrestException catch (e) {
      // PostgrestException может присутствовать в некоторых версиях SDK
      setState(() => _error = 'Ошибка сервера: ${e.message}');
    } catch (e, st) {
      // Общая обработка ошибок (сетевая ошибка и т.д.)
      // В продакшне логируйте st в ваш Sentry/логгер
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
                  Text(
                    'Примечание: username хранится без @. Пароли в таблице — plain/demo (рекомендуется заменить на хэширование).',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
