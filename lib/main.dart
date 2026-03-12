// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/theme/app_theme.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<void> _initFuture;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  int _elapsedMs = 0;
  int? _initDurationMs;
  late final String _supabaseUrl;

  @override
  void initState() {
    super.initState();
    _supabaseUrl = _resolveSupabaseUrl();
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedMs = _stopwatch.elapsedMilliseconds;
      });
    });
    _initFuture = _initializeApp();
  }

  

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final initSw = Stopwatch()..start();
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _resolveSupabaseAnonKey(),
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // During hot-restart or remount Supabase can already be initialized.
      if (!msg.contains('already initialized')) {
        rethrow;
      }
    } finally {
      initSw.stop();
      _stopwatch.stop();
      _ticker?.cancel();
      if (mounted) {
        setState(() {
          _initDurationMs = initSw.elapsedMilliseconds;
          _elapsedMs = _stopwatch.elapsedMilliseconds;
        });
      }
    }
  }

  String _resolveSupabaseUrl() {
    const fromEnv = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;

    if (kIsWeb) {
      final host = Uri.base.host;
      final sameHost = (host == 'localhost' || host == '127.0.0.1') ? '127.0.0.1' : host;
      final scheme = (Uri.base.scheme == 'https') ? 'https' : 'http';
      return '$scheme://$sameHost:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  String _resolveSupabaseAnonKey() {
    const fromEnv = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzcxMzUzODMyLCJleHAiOjIwODY3MTM4MzJ9.Rb3oNN5eIBYaH8U-mCa-3bkRdBGzZRcY6H2SII5Q8EQ';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Titanic',
      theme: TitanicTheme.themeData,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: TitanicTheme.themeData,
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _StartupSplash(
              elapsedMs: _elapsedMs,
              supabaseUrl: _supabaseUrl,
            );
          }
          if (snapshot.hasError) {
            return _StartupError(
              error: snapshot.error.toString(),
              elapsedMs: _elapsedMs,
              supabaseUrl: _supabaseUrl,
            );
          }
          return _InitInfoOverlay(
            initDurationMs: _initDurationMs ?? _elapsedMs,
            child: const LoginScreen(),
          );
        },
      ),
    );
  }
}

class _StartupSplash extends StatelessWidget {
  final int elapsedMs;
  final String supabaseUrl;
  const _StartupSplash({
    required this.elapsedMs,
    required this.supabaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              TitanicTheme.abyssalBlue,
              Color(0xFF0D2B4A),
              TitanicTheme.deepTeal,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 12),
              Text(
                'Initializing: ${elapsedMs} ms',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                supabaseUrl,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  final String error;
  final int elapsedMs;
  final String supabaseUrl;
  const _StartupError({
    required this.error,
    required this.elapsedMs,
    required this.supabaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TitanicTheme.abyssalBlue,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Initialization error after ${elapsedMs} ms.\n$supabaseUrl\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _InitInfoOverlay extends StatelessWidget {
  final int initDurationMs;
  final Widget child;
  const _InitInfoOverlay({
    required this.initDurationMs,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
