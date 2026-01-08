import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final supabase = Supabase.instance.client;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text;
      if (email.isEmpty || password.isEmpty) {
        _showError('Email и пароль обязательны');
        setState(() => _loading = false);
        return;
      }

      // sign in
      final res = await supabase.auth.signInWithPassword(email: email, password: password);
      final user = res.user;
      if (user == null) {
        _showError('Не удалось войти');
        setState(() => _loading = false);
        return;
      }

      // check role in user_credentials
      final row = await supabase
          .from('user_credentials')
          .select('id, role')
          .eq('id', user.id)
          .maybeSingle();

      if (row == null) {
        // no profile - sign out and error
        await supabase.auth.signOut();
        _showError('Профиль не найден. Обратитесь к администратору.');
        setState(() => _loading = false);
        return;
      }

      final role = (row['role'] ?? '').toString().toLowerCase();
      if (role != 'admin') {
        await supabase.auth.signOut();
        _showError('У вас нет прав администратора');
        setState(() => _loading = false);
        return;
      }

      // success -> replace with AdminScreen
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminScreen()));
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Вход')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _login,
            child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Войти как admin'),
          ),
        ]),
      ),
    );
  }
}