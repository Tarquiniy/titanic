// lib/services/persistent_storage_io.dart
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> getSavedUserId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('saved_user_id');
}

Future<void> saveUserId(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('saved_user_id', id);
}

Future<void> removeSavedUserId() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('saved_user_id');
}
