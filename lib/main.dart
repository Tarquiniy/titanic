import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';


const String SUPABASE_URL = 'https://lfgfrqpxmjwmklbrugbp.supabase.co';
const String SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmZ2ZycXB4bWp3bWtsYnJ1Z2JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjczNTU4MTEsImV4cCI6MjA4MjkzMTgxMX0.MBCsfcg8h47OTmBGVc4c8iT6kAC8unA2x8Q9PbVO_vA';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SUPABASE_URL,
    anonKey: SUPABASE_ANON_KEY,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Titanic (MVP)',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
