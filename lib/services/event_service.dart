// lib/services/event_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/models/app_user.dart';

typedef PopupCallback = void Function(String title, String message);

class EventService {
  final SupabaseClient supabase;
  AppUser? user;

  // Stream controller for new journal entries (realtime + persisted)
  final StreamController<Map<String, dynamic>> _journalStream = StreamController.broadcast();
  Stream<Map<String, dynamic>> get journalStream => _journalStream.stream;

  // small dedupe
  final Set<String> _seenJournalIds = {};

  // realtime channels
  RealtimeChannel? _journalUser;
  RealtimeChannel? _journalRole;
  RealtimeChannel? _journalAll;
  RealtimeChannel? _userEventsChannel;
  RealtimeChannel? _publicEventsChannel;

  PopupCallback? onPopup;

  EventService(this.supabase);

  /// Initialize service with current user and optional popup callback.
  Future<void> initFor(AppUser u, {PopupCallback? popup}) async {
    user = u;
    onPopup = popup;
    _subscribeToJournal();
    _subscribeToUserEvents();
    _subscribeToPublicEvents();
  }

  Future<List<Map<String, dynamic>>> loadInitialJournal({int limit = 200}) async {
    final u = user;
    if (u == null) return [];
    try {
      final role = u.role ?? '';
      final userId = u.id;
      final orFilter = 'user_id.eq.$userId,visible_role.eq.$role,visible_role.eq.all,visible_role.eq.non_politician';
      final res = await supabase
          .from('user_journal')
          .select('id,user_id,visible_role,actor_id,title,message,metadata,created_at')
          .or(orFilter)
          .order('created_at', ascending: false)
          .limit(limit);
      if (res is List) {
        final list = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // mark seen ids
        for (final r in list) {
          final id = (r['id'] ?? '').toString();
          if (id.isNotEmpty) _seenJournalIds.add(id);
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> persistJournalRow({
    String? userId,
    String? visibleRole,
    String? actorId,
    required String title,
    String? message,
    Map<String, dynamic>? metadata,
    bool addToStream = true,
  }) async {
    try {
      final insertObj = {
        'user_id': userId,
        'visible_role': visibleRole,
        'actor_id': actorId,
        'title': title,
        'message': message,
        'metadata': metadata,
      };
      final res = await supabase.from('user_journal').insert(insertObj).select().maybeSingle();
      if (res is Map<String, dynamic>) {
        final rec = Map<String, dynamic>.from(res);
        final id = (rec['id'] ?? '').toString();
        if (id.isNotEmpty) _seenJournalIds.add(id);
        if (addToStream) _journalStream.add(rec);
        return rec;
      }
    } catch (_) {}
    if (addToStream) {
      final local = {
        'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
        'user_id': userId,
        'visible_role': visibleRole,
        'actor_id': actorId,
        'title': title,
        'message': message,
        'metadata': metadata,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      _seenJournalIds.add(local['id'] as String);
      _journalStream.add(local);
      return local;
    }
    return null;
  }

  /// Convenience: create an event (popup + persist to user_events + journal)
  Future<void> addEventForCurrentUser(String title, String message) async {
    final u = user;
    if (u == null) return;
    // popup
    onPopup?.call(title, message);

    // persist to user_events table for per-user list
    try {
      await supabase.from('user_events').insert({'user_id': u.id, 'title': title, 'message': message, 'created_at': DateTime.now().toUtc().toIso8601String()});
    } catch (_) {}

    // persist to journal for long-term view
    try {
      await persistJournalRow(userId: u.id, actorId: u.id, title: title, message: message, addToStream: true);
    } catch (_) {}
  }

  void dispose() {
    try {
      _journalStream.close();
      _journalUser?.unsubscribe();
      _journalRole?.unsubscribe();
      _journalAll?.unsubscribe();
      _userEventsChannel?.unsubscribe();
      _publicEventsChannel?.unsubscribe();
    } catch (_) {}
  }

  // ----------------- subscriptions -----------------
  void _subscribeToJournal() {
    final u = user;
    if (u == null) return;
    try {
      _journalUser = supabase.channel('journal-user-${u.id}');
      _journalUser!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u.id),
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final map = Map<String, dynamic>.from(rec as Map);
              final id = (map['id'] ?? '').toString();
              if (id.isEmpty) return;
              if (_seenJournalIds.contains(id)) return;
              _seenJournalIds.add(id);
              _journalStream.add(map);
            },
          )
          .subscribe();

      _journalRole = supabase.channel('journal-role-${u.role}');
      _journalRole!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'visible_role', value: u.role),
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final map = Map<String, dynamic>.from(rec as Map);
              final id = (map['id'] ?? '').toString();
              if (id.isEmpty) return;
              if (_seenJournalIds.contains(id)) return;
              _seenJournalIds.add(id);
              _journalStream.add(map);
            },
          )
          .subscribe();

      _journalAll = supabase.channel('journal-all-${u.id}');
      _journalAll!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'visible_role', value: 'all'),
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final map = Map<String, dynamic>.from(rec as Map);
              final id = (map['id'] ?? '').toString();
              if (id.isEmpty) return;
              if (_seenJournalIds.contains(id)) return;
              _seenJournalIds.add(id);
              _journalStream.add(map);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'visible_role', value: 'non_politician'),
            callback: (payload) {
              // only show if current user is NOT politician
              if (user?.role == 'politician') return;
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final map = Map<String, dynamic>.from(rec as Map);
              final id = (map['id'] ?? '').toString();
              if (id.isEmpty) return;
              if (_seenJournalIds.contains(id)) return;
              _seenJournalIds.add(id);
              _journalStream.add(map);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _subscribeToUserEvents() {
    final u = user;
    if (u == null) return;
    try {
      _userEventsChannel = supabase.channel('user-events-${u.id}');
      _userEventsChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_events',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u.id),
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final map = Map<String, dynamic>.from(rec as Map);
              // popup
              onPopup?.call(map['title']?.toString() ?? 'Событие', map['message']?.toString() ?? '');
              // also forward to journal
              persistJournalRow(userId: u.id, actorId: map['actor_id']?.toString(), title: map['title']?.toString() ?? 'Событие', message: map['message']?.toString() ?? '', metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata']) : null, addToStream: true);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _subscribeToPublicEvents() {
    final u = user;
    if (u == null) return;
    try {
      _publicEventsChannel = supabase.channel('public-events-${u.id}');

      // debates created -> non-politician users
      _publicEventsChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'debates',
        callback: (payload) async {
          final rec = payload.newRecord ?? payload.oldRecord;
          if (rec == null) return;
          if (user?.role != 'politician') {
            final title = 'Новый дебат';
            final msg = 'Созданы дебаты: ${rec['title'] ?? '-'}';
            await addEventForCurrentUser(title, msg);
          }
        },
      );

      // political resolutions -> politicians
      _publicEventsChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'political_resolutions',
        callback: (payload) async {
          final rec = payload.newRecord ?? payload.oldRecord;
          if (rec == null) return;
          if (user?.role == 'politician') {
            final title = 'Новое политрешение';
            final msg = 'Создано политрешение: ${rec['title'] ?? '-'}';
            await addEventForCurrentUser(title, msg);
          }
        },
      );

      // item offers for this user
      _publicEventsChannel!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'item_offers',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'buyer_id', value: u.id),
        callback: (payload) async {
          final rec = payload.newRecord ?? payload.oldRecord;
          if (rec == null) return;
          final seller = rec['seller_id']?.toString() ?? '—';
          final price = rec['price']?.toString() ?? '-';
          final title = 'Входящий оффер';
          final msg = 'Оффер от $seller на сумму $price';
          await addEventForCurrentUser(title, msg);
        },
      );

      // user v_balance updates -> incoming V
      _publicEventsChannel!.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'user_credentials',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: u.id),
        callback: (payload) async {
          try {
            final newRec = payload.newRecord;
            final oldRec = payload.oldRecord;
            if (newRec == null) return;
            num newV = 0;
            num oldV = 0;
            if (newRec['v_balance'] is num) newV = newRec['v_balance'] as num;
            else newV = num.tryParse(newRec['v_balance']?.toString() ?? '') ?? 0;
            if (oldRec != null) {
              if (oldRec['v_balance'] is num) oldV = oldRec['v_balance'] as num;
              else oldV = num.tryParse(oldRec['v_balance']?.toString() ?? '') ?? 0;
            } else {
              // fallback: cannot compute delta
              oldV = 0;
            }
            if (newV > oldV) {
              final delta = (newV - oldV).toString();
              final title = 'Поступление войсов';
              final msg = 'На ваш счёт зачислено $delta V';
              await addEventForCurrentUser(title, msg);
            }
          } catch (_) {}
        },
      );

      _publicEventsChannel!.subscribe();
    } catch (_) {}
  }
}
