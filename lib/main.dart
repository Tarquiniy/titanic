// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'package:titanic/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация Supabase — оставлена как в вашем исходном main.dart.
  await Supabase.initialize(
    url: 'https://lfgfrqpxmjwmklbrugbp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmZ2ZycXB4bWp3bWtsYnJ1Z2JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjczNTU4MTEsImV4cCI6MjA4MjkzMTgxMX0.MBCsfcg8h47OTmBGVc4c8iT6kAC8unA2x8Q9PbVO_vA',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Titanic',
      theme: AppTheme.vintageTheme,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}
