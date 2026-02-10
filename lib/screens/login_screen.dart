// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
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

  // Background overlay assets (optional). If the asset is missing in pubspec.yaml,
  // the UI will simply skip drawing it (see errorBuilder).
  static const String _bgAsset = 'assets/art_deco_login.png';
  static const String _frameOverlayAsset = 'assets/art_deco_frame_overlay.png';
  static const String _ornamentAsset = 'assets/art_deco_ornament.png';

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
          .select(
            'id, telegram_username, role, first_name, last_name, v_balance, m_balance, color, region',
          )
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
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(currentUser: user)),
          );
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
          .select(
            'id, telegram_username, role, first_name, last_name, v_balance, m_balance, password, color, region',
          )
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(currentUser: user)),
        );
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

  InputDecoration _fieldDecoration({required String label, required IconData icon}) {
    return TitanicTheme.inputDecoration.copyWith(
      labelText: label,
      labelStyle: TextStyle(
        color: TitanicTheme.ivoryCream.withOpacity(0.9),
        fontSize: 15,
        fontFamily: 'Cinzel',
        letterSpacing: 0.5,
      ),
      hintStyle: TextStyle(
        color: TitanicTheme.ivoryCream.withOpacity(0.5),
        fontSize: 15,
        fontFamily: 'Cinzel',
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.only(right: 12, left: 4),
        child: Icon(
          icon,
          color: TitanicTheme.raptureGold,
          size: 22,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 40),
    );
  }

  Widget _buildArtDecoBackground({required Widget child}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base background image
        const Positioned.fill(
          child: Image(
            image: AssetImage(_bgAsset),
            fit: BoxFit.cover,
          ),
        ),

        // Darken layer to keep readability
        Positioned.fill(
          child: Container(
            color: TitanicTheme.abyssalBlue.withOpacity(0.82),
          ),
        ),

        // Subtle vignette for depth
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 1.05,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Frame overlay (optional)
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.22,
              child: Image.asset(
                _frameOverlayAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),

        // Top ornament (optional)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.22,
              child: Image.asset(
                _ornamentAsset,
                height: 44,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),

        // Bottom ornament (optional, mirrored)
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.18,
              child: RotatedBox(
                quarterTurns: 2,
                child: Image.asset(
                  _ornamentAsset,
                  height: 44,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),

        // Foreground content
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildArtDecoBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ЗАГОЛОВОЧНАЯ СЕКЦИЯ
                  Column(
                    children: [
                      // Декоративный элемент
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: TitanicTheme.goldGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.directions_boat,
                            size: 50,
                            color: TitanicTheme.abyssalBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Заголовок
                      Text(
                        'TITANIC',
                        style: TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: isSmallScreen ? 42 : 48,
                          fontWeight: FontWeight.w800,
                          color: TitanicTheme.raptureGold,
                          letterSpacing: 6.0,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.8),
                              blurRadius: 12,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Подзаголовок
                      Text(
                        'ВХОД В СИСТЕМУ',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: TitanicTheme.ivoryCream.withOpacity(0.9),
                          letterSpacing: 3.0,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Декоративная линия
                      Container(
                        height: 2,
                        width: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              TitanicTheme.raptureGold.withOpacity(0.6),
                              TitanicTheme.seaFoamGreen.withOpacity(0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // ФОРМА ВХОДА
                  Container(
                    decoration: BoxDecoration(
                      color: TitanicTheme.panelDark.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: TitanicTheme.raptureGold.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 25,
                          offset: const Offset(0, 12),
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Поле username
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 15 : 16,
                            fontFamily: 'Cinzel',
                          ),
                          cursorColor: TitanicTheme.raptureGold,
                          cursorWidth: 2.0,
                          cursorHeight: 20,
                          decoration: _fieldDecoration(
                            label: 'Telegram Username',
                            icon: Icons.person_outline,
                          ),
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 16),

                        // Поле пароля
                        TextField(
                          controller: _passCtrl,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 15 : 16,
                            fontFamily: 'Cinzel',
                          ),
                          cursorColor: TitanicTheme.raptureGold,
                          cursorWidth: 2.0,
                          cursorHeight: 20,
                          decoration: _fieldDecoration(
                            label: 'Пароль',
                            icon: Icons.lock_outline,
                          ),
                          onSubmitted: (_) {
                            if (!_loading) _signIn();
                          },
                        ),

                        // Сообщение об ошибке
                        if (_error != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.redAccent.withOpacity(0.9),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Colors.redAccent.withOpacity(0.9),
                                      fontSize: 14,
                                      fontFamily: 'Cinzel',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Декоративный разделитель
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: TitanicTheme.raptureGold.withOpacity(0.3),
                                thickness: 1,
                                height: 20,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Icon(
                                Icons.diamond,
                                color: TitanicTheme.raptureGold,
                                size: 16,
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: TitanicTheme.raptureGold.withOpacity(0.3),
                                thickness: 1,
                                height: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Кнопка входа
                        ArtDecoButton(
                          text: 'ВОЙТИ В СИСТЕМУ',
                          icon: Icons.login_rounded,
                          primary: true,
                          loading: _loading,
                          expanded: true,
                          onPressed: _loading ? null : _signIn,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ДЕКОРАТИВНЫЙ ЭЛЕМЕНТ ВНИЗУ
                  Column(
                    children: [
                      Container(
                        height: 3,
                        width: 150,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              TitanicTheme.raptureGold.withOpacity(0.0),
                              TitanicTheme.raptureGold.withOpacity(0.7),
                              TitanicTheme.seaFoamGreen.withOpacity(0.5),
                              TitanicTheme.raptureGold.withOpacity(0.7),
                              TitanicTheme.raptureGold.withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
