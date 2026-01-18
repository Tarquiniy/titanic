// lib/services/persistent_storage.dart
// Возвращает/сохраняет/удаляет строковый saved_user_id
export 'persistent_storage_io.dart' if (dart.library.html) 'persistent_storage_web.dart';
