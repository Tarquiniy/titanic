// lib/services/persistent_storage_web.dart
// Использует window.localStorage — работает в PWA/браузере
import 'dart:html' as html;

Future<String?> getSavedUserId() async {
  return html.window.localStorage['saved_user_id'];
}

Future<void> saveUserId(String id) async {
  try {
    html.window.localStorage['saved_user_id'] = id;
  } catch (_) {}
}

Future<void> removeSavedUserId() async {
  try {
    html.window.localStorage.remove('saved_user_id');
  } catch (_) {}
}
