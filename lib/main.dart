// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/theme/app_theme.dart';
import 'screens/login_screen.dart';

void main() async {
WidgetsFlutterBinding.ensureInitialized();
//
//  await Supabase.initialize(
//    url: 'https://lfgfrqpxmjwmklbrugbp.supabase.co',
//    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmZ2ZycXB4bWp3bWtsYnJ1Z2JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjczNTU4MTEsImV4cCI6MjA4MjkzMTgxMX0.MBCsfcg8h47OTmBGVc4c8iT6kAC8unA2x8Q9PbVO_vA',
//  );


await Supabase.initialize(
    url: 'http://192.168.0.105:8000',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzcxMzUzODMyLCJleHAiOjIwODY3MTM4MzJ9.Rb3oNN5eIBYaH8U-mCa-3bkRdBGzZRcY6H2SII5Q8EQ',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Titanic',
      theme: TitanicTheme.themeData,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
      themeMode: ThemeMode.dark,
      darkTheme: TitanicTheme.themeData.copyWith(
        // Дополнительные настройки для темного режима
      ),
    );
  }
}
