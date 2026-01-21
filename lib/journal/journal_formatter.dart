class JournalViewEntry {
  final String title;
  final String message;
  final String time;

  JournalViewEntry({
    required this.title,
    required this.message,
    required this.time,
  });
}

JournalViewEntry? formatJournalEvent(Map<String, dynamic> raw) {
  final table = (raw['table_name'] ?? '').toString();
  final op = (raw['op'] ?? '').toString().toUpperCase();
  final payload = raw['payload'] as Map<String, dynamic>? ?? {};
  final createdAt = raw['created_at']?.toString() ?? '';

  String time = _fmtTime(createdAt);

  // ====== 1. Полное скрытие "Изменение профиля" ======
  if (table == 'user_profiles' || table == 'user_credentials') {
    // но разрешаем предметы
    if (payload['item_name'] != null) {
      return JournalViewEntry(
        title: 'Добавлен предмет',
        message: 'Добавлен предмет: ${payload['item_name']}',
        time: time,
      );
    }
    return null; // НЕ ПОКАЗЫВАЕМ
  }

  // ====== 2. Речь ======
  if (table == 'speech_state') {
    return JournalViewEntry(
      title: 'Речь жизни',
      message: 'Изменён статус',
      time: time,
    );
  }

  // ====== 3. Баланс ======
  if (payload.containsKey('v_balance')) {
    final before = payload['v_balance']['old'];
    final after = payload['v_balance']['new'];

    return JournalViewEntry(
      title: 'Баланс изменён',
      message: 'Войсы: $before → $after',
      time: time,
    );
  }

  // ====== 4. Политрешения ======
  if (table == 'resolutions' && op == 'INSERT') {
    return JournalViewEntry(
      title: 'Новое политрешение',
      message: 'Создано политрешение: ${payload['title'] ?? '—'}',
      time: time,
    );
  }

  // ====== 5. Дебаты ======
  if (table == 'debates') {
    return JournalViewEntry(
      title: 'Дебаты',
      message: op == 'INSERT'
          ? 'Созданы новые дебаты'
          : 'Изменено состояние дебатов',
      time: time,
    );
  }

  // ====== Fallback ======
  return JournalViewEntry(
    title: 'Событие',
    message: 'Произошло обновление',
    time: time,
  );
}

String _fmtTime(String raw) {
  final dt = DateTime.tryParse(raw);
  if (dt == null) return '';
  final l = dt.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.hour)}:${z(l.minute)}';
}
