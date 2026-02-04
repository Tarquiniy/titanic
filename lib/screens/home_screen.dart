// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titanic/blocks/blood_poker_block.dart';

import 'package:titanic/models/app_user.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/services/debate_service.dart';
import 'package:titanic/services/speech_service.dart';
import 'package:titanic/screens/transfer_v_screen.dart';
import 'package:titanic/screens/inventory_screen.dart';
import 'package:titanic/screens/debates_screen.dart';
import 'package:titanic/screens/purchase_enterprise_screen.dart';
import 'login_screen.dart';

// Блоки
import 'package:titanic/blocks/movie_vote_block.dart';
import 'package:titanic/blocks/watched_movie_block.dart';
import 'package:titanic/blocks/hollywood_block.dart';
import 'package:titanic/blocks/mafia_block.dart' as mafia_blocks;

// Тема
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class HomeScreen extends StatefulWidget {
  final AppUser currentUser;
  const HomeScreen({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppUser user;
  final SupabaseClient supabase = Supabase.instance.client;
  final GameService svc = GameService();

  // Track speech button availability transitions
  bool _speechButtonPreviouslyEnabled = true;

  // services
  late final DebateService debateService;
  late final SpeechService speechService;

  // UI / state
  String? _userColor;
  bool _rpcLoading = false;

  // speech
  bool speechActive = false;
  String? speechActorId;
  DateTime? speechExpiresAt;
  bool _waitingForServerConfirm = false;
  int? _activeSpeechId;
  bool _listenedToThisSpeech = false;

  // debates / resolutions
  bool _hasActiveDebate = false;
  int? _activeDebateId;
  bool _alreadyVotedInActiveDebate = false;

  bool _hasActiveResolution = false;
  int? _activeResolutionId;
  bool _alreadyBetInActiveResolution = false;

  Timer? _debatePollTimer;
  Timer? _resolutionPollTimer;
  Timer? _pollTimer;

  // pending client-side inventory additions
  final List<Map<String, dynamic>> _pendingInventoryItems = [];

  // journal
  List<Map<String, dynamic>> _journalEntries = [];

  // single journal channel (client-side filtering)
  RealtimeChannel? _journalChannel;

  // honor article local state
  bool? _honorUsedLocal;
  double? _honorMBalance;

  // Helper function to check if user has a specific role
  bool _isRole(String role) {
    final userRole = user.role?.toLowerCase() ?? '';
    final roleLower = role.toLowerCase();
    return userRole.contains(roleLower) ||
        (roleLower == 'мафия' &&
            (userRole.contains('mafia') || userRole.contains('мафия')));
  }

  @override
  void initState() {
    super.initState();
    user = widget.currentUser;

    debateService = DebateService(supabase);
    speechService = SpeechService(svc: svc, supabase: supabase);

    _refreshProfile();
    _fetchSpeechState();
    _startPollingSpeechState();
    _loadDebateState();
    _startDebatePolling();
    _loadResolutionState();
    _startResolutionPolling();

    // initialize previous availability so transitions are detected
    _speechButtonPreviouslyEnabled = _isSpeechButtonEnabled;

    _loadJournal();
    _subscribeToJournal();

    // load local honor state (balance + used flag)
    _loadHonorLocalState();
  }

  @override
  void dispose() {
    _stopPollingSpeechState();
    _debatePollTimer?.cancel();
    _resolutionPollTimer?.cancel();
    _pollTimer?.cancel();
    debateService.dispose();
    speechService.dispose();
    _journalChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _onBloodPokerBetPlaced() async {
    try {
      await _refreshProfile();
      await _loadJournal();
    } catch (_) {}
  }

  Future<void> _onDebtCollected() async {
    try {
      await _refreshProfile();
      await _loadJournal();
    } catch (_) {}
  }

  Future<void> _onMafiaEnterpriseBought() async {
    try {
      await _refreshProfile();
      await _loadJournal();
    } catch (_) {}
  }

  /// Load honor article state (used flag + m_balance) and update local user copy.
  Future<void> _loadHonorLocalState() async {
    try {
      final st = await fetchHonorState(user.id);
      if (!mounted) return;
      setState(() {
        _honorUsedLocal = (st['used'] as bool?) ?? false;
        _honorMBalance = (st['m_balance'] as double?) ?? user.mBalance;
        user = user.copyWith(mBalance: _honorMBalance ?? user.mBalance);
      });
    } catch (_) {
      // ignore
    }
  }

  /// Local insert to journal list (immediate UI) with dedupe, and best-effort DB insert.
  Future<void> _insertJournalEntry(
    String title,
    String message, {
    String? visibleRole,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    // avoid duplicates: if identical title+message already present locally, skip
    final existsLocally = _journalEntries.any((e) {
      final t = (e['title'] ?? '').toString();
      final m = (e['message'] ?? '').toString();
      return t.trim() == title.trim() && m.trim() == message.trim();
    });
    if (existsLocally) return;

    final localRow = {
      'id': null,
      'user_id': user.id,
      'visible_role': visibleRole ?? user.role ?? 'all',
      'actor_id': user.id,
      'title': title,
      'message': message,
      'metadata': null,
      'created_at': nowIso,
    };

    // show immediately in UI
    if (mounted) {
      setState(() {
        _journalEntries.insert(0, localRow);
      });
    }

    // best-effort persist to DB
    try {
      await supabase.from('user_journal').insert({
        'user_id': user.id,
        'visible_role': visibleRole ?? user.role ?? 'all',
        'actor_id': user.id,
        'title': title,
        'message': message,
        'metadata': null,
        'created_at': nowIso,
      });
    } catch (_) {
      // ignore DB write errors (we already showed local)
    }
  }

  // -----------------------
  // Journal loader & subscription
  // -----------------------

  /// Normalize server message text to Russian-friendly, compact form.
  String _normalizeJournalMessage(String msg) {
    if (msg.isEmpty) return msg;
    var out = msg;

    try {
      // replace english/field names using case-insensitive regex (Dart: use caseSensitive:false)
      out = out.replaceAll(
        RegExp(r'Тип:\s*UPDATE', caseSensitive: false),
        'Изменён статус',
      );
      out = out.replaceAll(
        RegExp(r'Тип:\s*INSERT', caseSensitive: false),
        'Создано',
      );
      out = out.replaceAll(
        RegExp(r'Тип:\s*DELETE', caseSensitive: false),
        'Удалено',
      );

      // v_balance -> Войсы, m_balance -> Майнды
      out = out.replaceAll(
        RegExp(r'<b>\s*v_balance\s*<\/b>', caseSensitive: false),
        'Войсы',
      );
      out = out.replaceAll(
        RegExp(r'\bv_balance\b', caseSensitive: false),
        'Войсы',
      );
      out = out.replaceAll(
        RegExp(r'<b>\s*m_balance\s*<\/b>', caseSensitive: false),
        'Майнды',
      );
      out = out.replaceAll(
        RegExp(r'\bm_balance\b', caseSensitive: false),
        'Майнды',
      );

      // compact verbose patterns
      out = out.replaceAll('Тип: Изменён статус', 'Изменён статус');
      out = out.replaceAll(RegExp(r'\s+'), ' ');
      return out.trim();
    } catch (_) {
      // on any regex error or unexpected input, return original cleaned whitespace
      return msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }

  /// Loads journal entries visible to current user using a single OR filter (robust).
  Future<void> _loadJournal() async {
    try {
      final role = (user.role ?? '').toString();
      final userId = user.id;
      // Build OR filter string: include user-specific, role-specific, all, non_politician and NULL visible_role
      final orFilter =
          'user_id.eq.$userId,visible_role.eq.$role,visible_role.eq.all,visible_role.eq.non_politician,visible_role.is.null';

      final res = await supabase
          .from('user_journal')
          .select(
            'id,user_id,visible_role,actor_id,title,message,metadata,created_at',
          )
          .or(orFilter)
          .order('created_at', ascending: false)
          .limit(200);

      if (res is List) {
        // transform and dedupe here similarly to subscription transform
        final List<Map<String, dynamic>> rows = res
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final Map<String, Map<String, dynamic>> uniq = {};
        for (final r in rows) {
          // transform title/message
          String title = (r['title'] ?? '').toString();
          String message = (r['message'] ?? '').toString();

          if (title.toLowerCase().contains('speech_state') ||
              title.toLowerCase().contains('речь')) {
            title = 'Речь жизни';
          }
          message = _normalizeJournalMessage(message);

          // filter bland profile change entries (unless message mentions add)
          if (title.toLowerCase().contains('изменение профиля') &&
              !message.toLowerCase().contains('добав')) {
            continue;
          }
          if (message.toLowerCase().contains('добавлен') &&
              title.toLowerCase().contains('изменение профиля')) {
            title = 'Добавлен предмет';
          }

          final idVal = r['id']?.toString();
          final key = (idVal != null && idVal.isNotEmpty)
              ? 'id::$idVal'
              : 'txt::${title}::${message}::${(r['created_at'] ?? '').toString()}';
          if (!uniq.containsKey(key)) {
            final copy = Map<String, dynamic>.from(r);
            copy['title'] = title;
            copy['message'] = message;
            uniq[key] = copy;
          }
        }

        final merged = uniq.values.toList();
        merged.sort((a, b) {
          final sa = (a['created_at'] ?? '').toString();
          final sb = (b['created_at'] ?? '').toString();
          final da = DateTime.tryParse(sa);
          final db = DateTime.tryParse(sb);
          if (da != null && db != null) return db.compareTo(da);
          if (da != null) return -1;
          if (db != null) return 1;
          return 0;
        });

        if (!mounted) return;
        setState(() {
          _journalEntries = merged;
        });
      } else {
        // ensure not leaving list empty
        if (!mounted) return setState(() => _journalEntries = []);
      }
    } catch (e) {
      // If query fails, keep previous entries; print error for debugging
      // ignore: avoid_print
      print('loadJournal error: $e');
    }
  }

  void _subscribeToJournal() {
    try {
      _journalChannel = supabase.channel('journal-${user.id}');
      _journalChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            // no server-side filter to avoid missing any rows; do client-side visibility filtering below
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final Map<String, dynamic> row = Map<String, dynamic>.from(
                rec as Map,
              );

              // client-side visibility check
              final String? vis = row['visible_role']?.toString();
              final String role = (user.role ?? '').toString();
              final bool visibleToUser =
                  (row['user_id']?.toString() == user.id) ||
                  vis == null ||
                  vis == 'all' ||
                  vis == role ||
                  (vis == 'non_politician' && role != 'politician');

              if (!visibleToUser) return;

              // transform title/message same as loader
              String title = (row['title'] ?? '').toString();
              String message = (row['message'] ?? '').toString();

              if (title.toLowerCase().contains('speech_state') ||
                  title.toLowerCase().contains('речь')) {
                title = 'Речь жизни';
              }
              message = _normalizeJournalMessage(message);
              if (title.toLowerCase().contains('изменение профиля') &&
                  !message.toLowerCase().contains('добав')) {
                return; // ignore bland profile changes
              }
              if (message.toLowerCase().contains('добавлен') &&
                  title.toLowerCase().contains('изменение профиля')) {
                title = 'Добавлен предмет';
              }

              // dedupe: by id or by title+message+created_at
              final exists = _journalEntries.any(
                (e) =>
                    (e['id'] != null &&
                        row['id'] != null &&
                        e['id'].toString() == row['id'].toString()) ||
                    ((e['title'] ?? '').toString().trim() == title.trim() &&
                        (e['message'] ?? '').toString().trim() ==
                            message.trim() &&
                        (e['created_at'] ?? '').toString().trim() ==
                            (row['created_at'] ?? '').toString().trim()),
              );
              if (exists) return;

              final toInsert = Map<String, dynamic>.from(row);
              toInsert['title'] = title;
              toInsert['message'] = message;

              if (!mounted) return;
              setState(() {
                _journalEntries.insert(0, toInsert);
              });
            },
          )
          .subscribe();
    } catch (e) {
      // ignore subscription errors but print for debugging
      // ignore: avoid_print
      print('subscribeToJournal error: $e');
    }
  }

  // -----------------------
  // Profile / refresh
  // -----------------------
  Future<void> _refreshProfile() async {
    try {
      final profileRaw = await supabase
          .from('user_credentials')
          .select(
            'v_balance, m_balance, first_name, last_name, telegram_username, role, color, region',
          )
          .eq('id', user.id)
          .maybeSingle();

      final profile = (profileRaw is Map<String, dynamic>) ? profileRaw : null;
      if (profile != null) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        final fn = profile['first_name'];
        final ln = profile['last_name'];
        final uname = profile['telegram_username'];
        final role = profile['role'];
        final color = profile['color'];
        final region = profile['region'];

        if (!mounted) return;
        setState(() {
          user = AppUser(
            id: user.id,
            username: uname is String ? uname : user.username,
            role: role is String ? role : user.role,
            firstName: fn is String ? fn : user.firstName,
            lastName: ln is String ? ln : user.lastName,
            vBalance: v is num ? (v).toDouble() : user.vBalance,
            mBalance: m is num ? (m).toDouble() : user.mBalance,
            color: color is String ? color : user.color,
            region: region is String ? region : user.region,
          );
          _userColor = color is String ? color : null;
        });
      }
    } catch (_) {}
    // update honor local state after refreshing profile
    await _loadHonorLocalState();
  }

  // -----------------------
  // Debates (uses DebateService)
  // -----------------------
  Future<void> _loadDebateState() async {
    try {
      final id = await debateService.loadActiveDebateId();
      if (id != null) {
        final voted = await debateService.userAlreadyVoted(user.id, id);
        if (!mounted) return;
        setState(() {
          _hasActiveDebate = true;
          _activeDebateId = id;
          _alreadyVotedInActiveDebate = voted;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasActiveDebate = false;
          _activeDebateId = null;
          _alreadyVotedInActiveDebate = false;
        });
      }
    } catch (_) {}
  }

  void _startDebatePolling({int seconds = 5}) {
    _debatePollTimer?.cancel();
    _debatePollTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => _loadDebateState(),
    );
  }

  // -----------------------
  // Resolutions
  // -----------------------
  Future<void> _loadResolutionState() async {
    try {
      final active = await supabase
          .from('political_resolutions')
          .select('id')
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (active is Map<String, dynamic> && active['id'] != null) {
        final int id = (active['id'] is int)
            ? (active['id'] as int)
            : int.parse(active['id'].toString());
        bool already = false;
        try {
          final bet = await supabase
              .from('political_bets')
              .select('id')
              .eq('resolution_id', id)
              .eq('user_id', user.id)
              .limit(1)
              .maybeSingle();
          already = bet != null;
        } catch (_) {
          already = false;
        }
        if (!mounted) return;
        setState(() {
          _hasActiveResolution = true;
          _activeResolutionId = id;
          _alreadyBetInActiveResolution = already;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasActiveResolution = false;
          _activeResolutionId = null;
          _alreadyBetInActiveResolution = false;
        });
      }
    } catch (_) {}
  }

  void _startResolutionPolling({int seconds = 5}) {
    _resolutionPollTimer?.cancel();
    _resolutionPollTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => _loadResolutionState(),
    );
  }

  // -----------------------
  // Speech (uses GameService)
  // -----------------------
  Future<void> _fetchSpeechState() async {
    try {
      final res = await svc.fetchSpeechState();

      if (res is Map<String, dynamic>) {
        final active = (res['active'] as bool?) ?? false;
        final actor = res['actor_id']?.toString();
        final expiresRaw = res['expires_at'];
        final expires = expiresRaw != null
            ? DateTime.tryParse(expiresRaw.toString())
            : null;

        final nowUtc = DateTime.now().toUtc();

        // expired according to server -> mark inactive
        if (expires != null && nowUtc.isAfter(expires)) {
          if (!mounted) return;
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
            _waitingForServerConfirm = false;
            _activeSpeechId = null;
            _listenedToThisSpeech = false;
          });

          // detect button availability transition -> log if previously disabled -> now enabled
          final newEnabled = _isSpeechButtonEnabled;
          if (_speechButtonPreviouslyEnabled == false && newEnabled == true) {
            await _insertJournalEntry(
              'Речь жизни доступна!',
              'Кнопка "Речь жизни" снова доступна для запуска.',
              visibleRole: 'politician',
            );
          }
          _speechButtonPreviouslyEnabled = newEnabled;
          return;
        }

        // normal branch: set server-provided values
        if (!mounted) return;
        setState(() {
          speechActive = active;
          speechActorId = actor;
          speechExpiresAt = expires;
        });

        // get active life speech id + listen state
        try {
          final life = await svc.getActiveLifeSpeech();
          if (life is Map<String, dynamic>) {
            _activeSpeechId = (life['id'] is int)
                ? (life['id'] as int)
                : int.tryParse(life['id']?.toString() ?? '');
          }
          await _checkIfListened();
        } catch (_) {}

        // after applying server state, detect transition of button enabledness
        final newEnabled = _isSpeechButtonEnabled;
        if (_speechButtonPreviouslyEnabled == false && newEnabled == true) {
          await _insertJournalEntry(
            'Речь жизни доступна!',
            'Кнопка "Речь жизни" снова доступна для запуска.',
            visibleRole: 'politician',
          );
        }
        _speechButtonPreviouslyEnabled = newEnabled;
      } else {
        // response missing -> treat as inactive
        if (!mounted) return;
        setState(() {
          speechActive = false;
          speechActorId = null;
          speechExpiresAt = null;
          _activeSpeechId = null;
          _listenedToThisSpeech = false;
        });

        final newEnabled = _isSpeechButtonEnabled;
        if (_speechButtonPreviouslyEnabled == false && newEnabled == true) {
          await _insertJournalEntry(
            'Речь жизни доступна!',
            'Кнопка "Речь жизни" снова доступна для запуска.',
            visibleRole: 'politician',
          );
        }
        _speechButtonPreviouslyEnabled = newEnabled;
      }
    } catch (_) {}
  }

  void _startPollingSpeechState({int seconds = 3}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: seconds),
      (_) => _fetchSpeechState(),
    );
  }

  void _stopPollingSpeechState() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkIfListened() async {
    final sid = _activeSpeechId;
    if (sid == null) {
      if (!mounted) return setState(() => _listenedToThisSpeech = false);
      return;
    }
    try {
      final res = await supabase
          .from('life_speech_listeners')
          .select('id')
          .eq('speech_id', sid)
          .eq('user_id', user.id)
          .limit(1)
          .maybeSingle();
      final listened = res != null;
      if (!mounted) return setState(() => _listenedToThisSpeech = listened);
    } catch (_) {}
  }

  bool get _isSpeechButtonEnabled {
    if (user.role != 'politician') return false;
    if (_rpcLoading) return false;

    final nowUtc = DateTime.now().toUtc();

    if (speechExpiresAt != null) {
      if (nowUtc.isBefore(speechExpiresAt!)) return false;
    }

    if (speechActive) {
      if (speechExpiresAt != null) {
        return nowUtc.isAfter(speechExpiresAt!);
      } else {
        final next20 = _nextYekaterinburg20Utc();
        return nowUtc.isAfter(next20);
      }
    }

    if (_waitingForServerConfirm) return false;
    return true;
  }

  Future<void> _onStartSpeechPressed() async {
    if (user.role != 'politician') return;
    if (!_isSpeechButtonEnabled) return;

    final target20Utc = _nextYekaterinburg20Utc();
    final secondsForRpc = _secondsUntilUtc(target20Utc);
    if (secondsForRpc <= 0) {
      _showMessage('Невозможно вычислить время до 20:00 YEKT');
      return;
    }

    final clientNextSlotUtc = _nextYekaterinburg12or20Utc();

    if (!mounted) return;
    setState(() {
      _rpcLoading = true;
      speechActive = true;
      speechActorId = user.id;
      speechExpiresAt = clientNextSlotUtc;
      _waitingForServerConfirm = true;
    });

    // Immediately mark button previously disabled and publish journal entry visible to all politicians
    try {
      _speechButtonPreviouslyEnabled = false;
      await _insertJournalEntry(
        'Произносится Речь жизни',
        'Вы начали Речь жизни — кнопка недоступна, пока длится речь.',
        visibleRole: 'politician',
      );
    } catch (_) {}

    DateTime? applyExpires = clientNextSlotUtc;

    try {
      final dynamic rpcRes = await svc.rpcStartSpeech(
        actorId: user.id,
        durationSeconds: secondsForRpc,
      );

      Map<String, dynamic>? parsed;
      if (rpcRes is Map<String, dynamic>) {
        parsed = rpcRes;
      } else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
        parsed = Map<String, dynamic>.from(rpcRes[0] as Map);
      } else if (rpcRes is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(rpcRes) as Map);
        } catch (_) {
          parsed = null;
        }
      } else {
        parsed = null;
      }

      if (parsed != null) {
        final serverExpiresRaw = parsed['expires_at'];
        final serverExpires = serverExpiresRaw != null
            ? DateTime.tryParse(serverExpiresRaw.toString())
            : null;
        DateTime chosen = serverExpires ?? clientNextSlotUtc;
        if (clientNextSlotUtc.isAfter(chosen)) chosen = clientNextSlotUtc;
        applyExpires = chosen;

        if (!mounted) return;
        setState(() {
          speechActive = parsed?['active'] as bool? ?? true;
          speechActorId = parsed?['actor_id']?.toString();
          speechExpiresAt = applyExpires;
          _waitingForServerConfirm = false;
        });
      } else {
        await _fetchSpeechState();
        if (!mounted) return;
        setState(() {
          if (speechExpiresAt == null ||
              clientNextSlotUtc.isAfter(speechExpiresAt!)) {
            speechExpiresAt = clientNextSlotUtc;
          }
          _waitingForServerConfirm = false;
        });
      }

      try {
        final upsertObj = {
          'id': 1,
          'active': true,
          'actor_id': user.id,
          'expires_at': applyExpires!.toUtc().toIso8601String(),
        };
        await svc.upsertSpeechState(obj: upsertObj);
      } catch (e) {
        _showMessage(
          'Не удалось сохранить состояние речи на сервере (права). Кнопка всё равно будет локально заблокирована.',
        );
      }

      _showMessage(
        'Речь запущена. Кнопка будет недоступна до ${_formatYe(applyExpires)} (YEKT)',
      );
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg != null && msg.contains('Speech already active')) {
        await _fetchSpeechState();
      } else {
        _showMessage(msg ?? e.toString());
        if (!mounted) return;
        setState(() {
          speechActive = false;
          speechActorId = null;
          _waitingForServerConfirm = false;
          speechExpiresAt = null;
        });
      }
    } catch (e) {
      _showMessage(e.toString());
      if (!mounted) return;
      setState(() {
        speechActive = false;
        speechActorId = null;
        _waitingForServerConfirm = false;
        speechExpiresAt = null;
      });
    } finally {
      if (!mounted) return;
      setState(() => _rpcLoading = false);
    }
  }

  // -----------------------
  // Actions for buttons
  // -----------------------
  Future<void> _openTransferScreen() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransferVScreen(user: user)),
    );
    if (res == true) {
      await _refreshProfile();
    }
  }

  Future<void> _openInventoryScreen() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => InventoryScreen(user: user)));
    if (!mounted) return;
    setState(() {
      _pendingInventoryItems.removeWhere((it) => it['owner_id'] == user.id);
    });
  }

  Future<void> _openBuyTurnFlow() async {
    await openBuyTurnFlow(
      context: context,
      supabase: supabase,
      svc: svc,
      currentUser: user,
      onRefreshProfile: () async {
        await _refreshProfile();
        await _loadJournal();
      },
      showMessage: _showMessage,
    );
  }

  Future<void> _openPurchaseEnterprise() async {
    if (user.role != 'economist') return;
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseEnterpriseScreen(currentUser: user),
      ),
    );
    if (res == true) {
      await _refreshProfile();
      _showMessage('Предприятие куплено и добавлено в ваш инвентарь');
    }
  }

  Future<void> _openDebates() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DebatesScreen(currentUserId: user.id, service: svc),
      ),
    );

    if (res == true) {
      if (!mounted) return;
      setState(() {
        _alreadyVotedInActiveDebate = true;
      });
      await _refreshProfile();
      await _loadDebateState();
    } else {
      await _loadDebateState();
    }
  }

  Future<void> _onOpenResolutionPressed() async {
    if (_activeResolutionId == null) return;
    final resolutionId = _activeResolutionId!;

    List<Map<String, dynamic>> options = [];
    try {
      final res = await supabase
          .from('resolution_options')
          .select('id,label')
          .eq('resolution_id', resolutionId)
          .order('id');
      if (res is List)
        options = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _showMessage('Не удалось загрузить варианты: $e');
      return;
    }

    if (options.isEmpty) {
      _showMessage('Нет доступных вариантов для этого политрешения');
      return;
    }

    int? selectedOptionId;
    final TextEditingController amtCtrl = TextEditingController();

    final resDialogResult = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) {
            return AlertDialog(
              title: const Text('Политрешение — ваш выбор'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Выберите вариант:'),
                    const SizedBox(height: 8),
                    ...options.map((opt) {
                      final oid = (opt['id'] is int)
                          ? opt['id'] as int
                          : int.parse(opt['id'].toString());
                      return RadioListTile<int>(
                        value: oid,
                        groupValue: selectedOptionId,
                        onChanged: (v) =>
                            setStateDialog(() => selectedOptionId = v),
                        title: Text(opt['label'] ?? '-'),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amtCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            'Сумма майндов (целое). Ваш баланс: ${user.mBalance.toStringAsFixed(2)}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(false),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedOptionId == null) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        const SnackBar(content: Text('Выберите вариант')),
                      );
                      return;
                    }
                    final txt = amtCtrl.text.trim();
                    final n = int.tryParse(txt);
                    if (n == null || n <= 0) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        const SnackBar(
                          content: Text('Введите положительное целое число'),
                        ),
                      );
                      return;
                    }
                    if (n > user.mBalance) {
                      ScaffoldMessenger.of(ctx2).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Недостаточно майндов: у вас ${user.mBalance.toStringAsFixed(2)}',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(ctx2).pop(true);

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    try {
                      await svc.placeBetInResolution(
                        resolutionId: resolutionId,
                        optionId: selectedOptionId!,
                        userId: user.id,
                        amount: n,
                      );
                      await _refreshProfile();
                      await _loadResolutionState();
                      if (mounted) Navigator.of(context).pop();
                      await showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text(
                            'Спасибо за участие в политрешении',
                          ),
                          content: const Text('Ваша ставка принята.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                      if (!mounted) return;
                      setState(() {
                        _alreadyBetInActiveResolution = true;
                      });
                    } catch (e) {
                      if (mounted) Navigator.of(context).pop();
                      final msg = e is PostgrestException
                          ? (e.message ?? e.toString())
                          : e.toString();
                      _showMessage('Ошибка при ставке: $msg');
                    }
                  },
                  child: const Text('Подтвердить ставку'),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      amtCtrl.dispose();
    } catch (_) {}
  }

  // -----------------------
  // Helpers (YEKT / ui)
  // -----------------------
  DateTime _nextYekaterinburg20Utc() {
    final nowUtc = DateTime.now().toUtc();
    final nowYe = nowUtc.add(const Duration(hours: 5));
    DateTime targetYe = DateTime(nowYe.year, nowYe.month, nowYe.day, 20, 0);
    if (!nowYe.isBefore(targetYe)) {
      final tomorrow = nowYe.add(const Duration(days: 1));
      targetYe = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0);
    }
    return targetYe.subtract(const Duration(hours: 5));
  }

  DateTime _nextYekaterinburg12or20Utc() {
    final nowUtc = DateTime.now().toUtc();
    final nowYe = nowUtc.add(const Duration(hours: 5));
    final today12 = DateTime(nowYe.year, nowYe.month, nowYe.day, 12, 0);
    final today20 = DateTime(nowYe.year, nowYe.month, nowYe.day, 20, 0);

    DateTime nextYe;
    if (nowYe.isBefore(today12)) {
      nextYe = today12;
    } else if (nowYe.isBefore(today20)) {
      nextYe = today20;
    } else {
      final tomorrow = nowYe.add(const Duration(days: 1));
      nextYe = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 0);
    }
    return nextYe.subtract(const Duration(hours: 5));
  }

  int _secondsUntilUtc(DateTime targetUtc) {
    final nowUtc = DateTime.now().toUtc();
    final diff = targetUtc.difference(nowUtc);
    final secs = diff.inSeconds;
    return secs > 0 ? secs : 0;
  }

  String _formatYe(DateTime? utc) {
    if (utc == null) return '—';
    final ye = utc.toUtc().add(const Duration(hours: 5));
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(ye.day)}.${z(ye.month)} ${z(ye.hour)}:${z(ye.minute)}';
  }

  void _showMessage(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: TitanicTheme.surfaceNavy.withOpacity(0.95),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: TitanicTheme.raptureGold.withOpacity(0.3)),
        ),
      ),
    );
  }

  void _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_id');
    } catch (_) {}
    try {
      await supabase.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) {
          return const LoginScreen();
        },
      ),
    );
  }

  // -----------------------
  // BUILD
  // -----------------------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/art_deco_login.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          color: TitanicTheme.abyssalBlue.withOpacity(0.85),
          child: SafeArea(
            child: Column(
              children: [
                // ВЕРХНЯЯ ПАНЕЛЬ С КНОПКАМИ
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        TitanicTheme.abyssalBlue.withOpacity(0.95),
                        TitanicTheme.abyssalBlue.withOpacity(0.7),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: TitanicTheme.raptureGold.withOpacity(0.2),
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ЛОГОТИП И ЗАГОЛОВОК
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: TitanicTheme.goldGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.directions_boat,
                              color: TitanicTheme.abyssalBlue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ГЛАВНАЯ ПАЛУБА',
                                style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: isSmallScreen ? 14 : 16,
                                  fontWeight: FontWeight.w700,
                                  color: TitanicTheme.ivoryCream,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Container(
                                height: 2,
                                width: 80,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      TitanicTheme.raptureGold,
                                      TitanicTheme.seaFoamGreen,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      // КНОПКИ ДЕЙСТВИЙ
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: TitanicTheme.goldGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.inventory_2,
                                size: 20,
                                color: TitanicTheme.abyssalBlue,
                              ),
                              onPressed: _openInventoryScreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  TitanicTheme.copperDetail.withOpacity(0.9),
                                  TitanicTheme.brassAccent.withOpacity(0.8),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.exit_to_app,
                                size: 20,
                                color: TitanicTheme.abyssalBlue,
                              ),
                              onPressed: _logout,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // ОСНОВНОЙ КОНТЕНТ
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // КАРТОЧКА ПРОФИЛЯ
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
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ИНФОРМАЦИЯ О ПОЛЬЗОВАТЕЛЕ
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: TitanicTheme.goldGradient,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.4),
                                            blurRadius: 10,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.person,
                                          size: 32,
                                          color: TitanicTheme.abyssalBlue,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${user.firstName} ${user.lastName}',
                                            style: TextStyle(
                                              fontFamily: 'CormorantGaramond',
                                              fontSize: isSmallScreen ? 20 : 24,
                                              fontWeight: FontWeight.w700,
                                              color: TitanicTheme.ivoryCream,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${user.username}',
                                            style: TextStyle(
                                              fontFamily: 'Cinzel',
                                              fontSize: 14,
                                              color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          if (_userColor != null) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _getColorFromString(_userColor!).withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: _getColorFromString(_userColor!).withOpacity(0.4),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                _userColor!,
                                                style: TextStyle(
                                                  fontFamily: 'Cinzel',
                                                  fontSize: 12,
                                                  color: TitanicTheme.ivoryCream,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                
                                // БАЛАНСЫ
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: TitanicTheme.surfaceNavy.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: TitanicTheme.raptureGold.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(
                                        children: [
                                          Text(
                                            'Войсы',
                                            style: TextStyle(
                                              fontFamily: 'Cinzel',
                                              fontSize: 12,
                                              color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            user.vBalance.toStringAsFixed(2),
                                            style: TextStyle(
                                              fontFamily: 'CormorantGaramond',
                                              fontSize: isSmallScreen ? 22 : 26,
                                              fontWeight: FontWeight.w700,
                                              color: TitanicTheme.raptureGold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: 1,
                                        height: 40,
                                        color: TitanicTheme.raptureGold.withOpacity(0.2),
                                      ),
                                      Column(
                                        children: [
                                          Text(
                                            'Майнды',
                                            style: TextStyle(
                                              fontFamily: 'Cinzel',
                                              fontSize: 12,
                                              color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            user.mBalance.toStringAsFixed(2),
                                            style: TextStyle(
                                              fontFamily: 'CormorantGaramond',
                                              fontSize: isSmallScreen ? 22 : 26,
                                              fontWeight: FontWeight.w700,
                                              color: TitanicTheme.seaFoamGreen,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                
                                // КНОПКИ ДЕЙСТВИЙ
                                Row(
                                  children: [
                                    Expanded(
                                      child: ArtDecoButton(
                                        text: 'Перевод V',
                                        icon: Icons.swap_horiz,
                                        onPressed: _openTransferScreen,
                                        primary: false,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ArtDecoButton(
                                        text: 'Инвентарь',
                                        icon: Icons.inventory_2,
                                        onPressed: _openInventoryScreen,
                                        primary: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // СЕКЦИЯ ВОЗМОЖНОСТЕЙ РОЛИ
                        Container(
                          decoration: BoxDecoration(
                            color: TitanicTheme.panelDark.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Возможности вашей роли',
                                  style: TextStyle(
                                    fontFamily: 'CormorantGaramond',
                                    fontSize: isSmallScreen ? 20 : 22,
                                    fontWeight: FontWeight.w700,
                                    color: TitanicTheme.ivoryCream,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: TitanicTheme.raptureGold.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: TitanicTheme.raptureGold.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    user.role,
                                    style: TextStyle(
                                      fontFamily: 'Cinzel',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: TitanicTheme.raptureGold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                
                                // КНОПКИ ДЛЯ РОЛЕЙ
                                if (_isRole('economist')) ...[
                                  ArtDecoButton(
                                    text: 'Купить ход',
                                    icon: Icons.shopping_cart,
                                    onPressed: _openBuyTurnFlow,
                                    primary: true,
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                if (_hasActiveDebate && !_alreadyVotedInActiveDebate) ...[
                                  ArtDecoButton(
                                    text: 'Участвовать в дебатах',
                                    icon: Icons.forum,
                                    onPressed: _openDebates,
                                    primary: false,
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                if (_hasActiveResolution && !_alreadyBetInActiveResolution) ...[
                                  Container(
                                    decoration: TitanicTheme.outlineGildedButton(highlighted: true),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _onOpenResolutionPressed,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.gavel, color: TitanicTheme.seaFoamGreen, size: 20),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Политрешение',
                                                style: TextStyle(
                                                  fontFamily: 'Cinzel',
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: TitanicTheme.ivoryCream,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                if (user.role == 'politician') ...[
                                  Container(
                                    decoration: _isSpeechButtonEnabled
                                        ? TitanicTheme.primaryAccentButtonDecoration
                                        : TitanicTheme.outlineGildedButton(),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _isSpeechButtonEnabled ? _onStartSpeechPressed : null,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (_rpcLoading)
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: _isSpeechButtonEnabled
                                                        ? Colors.black
                                                        : TitanicTheme.raptureGold,
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  Icons.campaign,
                                                  color: _isSpeechButtonEnabled
                                                      ? Colors.black
                                                      : TitanicTheme.raptureGold,
                                                  size: 20,
                                                ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _isSpeechButtonEnabled
                                                      ? 'Речь жизни (старт)'
                                                      : 'Речь жизни (неактивна)',
                                                  style: TextStyle(
                                                    fontFamily: 'Cinzel',
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: _isSpeechButtonEnabled
                                                        ? Colors.black
                                                        : TitanicTheme.ivoryCream,
                                                    letterSpacing: 0.8,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // БЛОК ФИЛЬМОВ
                        Container(
                          decoration: BoxDecoration(
                            color: TitanicTheme.panelDark.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: TitanicTheme.copperDetail.withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Кинематограф',
                                style: TextStyle(
                                  fontFamily: 'CormorantGaramond',
                                  fontSize: isSmallScreen ? 20 : 22,
                                  fontWeight: FontWeight.w700,
                                  color: TitanicTheme.ivoryCream,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Кнопка "Я посмотрел фильм"
                              WatchedMovieBlock(
                                currentUserId: user.id,
                                onChanged: () async {
                                  try {
                                    await _refreshProfile();
                                    await _loadJournal();
                                  } catch (_) {}
                                },
                              ),
                              const SizedBox(height: 12),
                              
                              // Голосование за фильм
                              MovieVoteBlock(
                                currentUserId: user.id,
                                currentUserRole: user.role,
                                onVoted: () async {
                                  try {
                                    await _refreshProfile();
                                    await _loadJournal();
                                  } catch (_) {}
                                },
                              ),
                              const SizedBox(height: 12),
                              
                              // Hollywood кнопки
                              HollywoodPayBlock(
                                currentUserId: user.id,
                                currentUserRole: user.role,
                                onPaid: () async {
                                  try {
                                    await _refreshProfile();
                                    await _loadJournal();
                                  } catch (_) {}
                                },
                              ),
                            ],
                          ),
                        ),

                        // БЛОКИ ДЛЯ МАФИИ
                        if (_isRole('мафия')) ...[
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: TitanicTheme.panelDark.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Особые возможности',
                                  style: TextStyle(
                                    fontFamily: 'CormorantGaramond',
                                    fontSize: isSmallScreen ? 20 : 22,
                                    fontWeight: FontWeight.w700,
                                    color: TitanicTheme.ivoryCream,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                mafia_blocks.MafiaBlock(
                                  currentUserId: user.id,
                                  currentUserRole: user.role,
                                  onProposalUsed: () async {
                                    try {
                                      await _refreshProfile();
                                      await _loadJournal();
                                    } catch (_) {}
                                  },
                                  onDebtCollected: _onDebtCollected,
                                  onEnterpriseBought: _onMafiaEnterpriseBought,
                                ),
                                const SizedBox(height: 16),
                                
                                BloodPokerBlock(
                                  currentUserId: user.id,
                                  onBetPlaced: _onBloodPokerBetPlaced,
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ЖУРНАЛ СОБЫТИЙ
                        const SizedBox(height: 20),
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
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Журнал событий',
                                  style: TextStyle(
                                    fontFamily: 'CormorantGaramond',
                                    fontSize: isSmallScreen ? 20 : 22,
                                    fontWeight: FontWeight.w700,
                                    color: TitanicTheme.ivoryCream,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                if (_journalEntries.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 30),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.history_toggle_off,
                                          size: 50,
                                          color: TitanicTheme.ivoryCream.withOpacity(0.2),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'История событий пуста',
                                          style: TextStyle(
                                            fontFamily: 'Cinzel',
                                            fontSize: 14,
                                            color: TitanicTheme.ivoryCream.withOpacity(0.5),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ..._journalEntries.take(5).map((entry) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: TitanicTheme.surfaceNavy.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: TitanicTheme.raptureGold.withOpacity(0.1),
                                          width: 1,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry['title']?.toString() ?? 'Событие',
                                              style: TextStyle(
                                                fontFamily: 'Cinzel',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: TitanicTheme.ivoryCream,
                                                letterSpacing: 0.3,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              entry['message']?.toString() ?? '',
                                              style: TextStyle(
                                                fontFamily: 'Cinzel',
                                                fontSize: 13,
                                                color: TitanicTheme.ivoryCream.withOpacity(0.85),
                                                letterSpacing: 0.3,
                                                height: 1.4,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Icon(
                                                  Icons.access_time,
                                                  size: 12,
                                                  color: TitanicTheme.ivoryCream.withOpacity(0.5),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _formatJournalDate(entry['created_at']?.toString()),
                                                  style: TextStyle(
                                                    fontFamily: 'Cinzel',
                                                    fontSize: 11,
                                                    color: TitanicTheme.ivoryCream.withOpacity(0.5),
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Вспомогательные методы для форматирования
  Color _getColorFromString(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'красный':
        return const Color(0xFFC62828);
      case 'зелёный':
        return const Color(0xFF2E7D32);
      case 'синий':
        return const Color(0xFF1565C0);
      case 'малиновый':
        return const Color(0xFFAD1457);
      case 'жёлтый':
        return const Color(0xFFF9A825);
      case 'золотой':
        return const Color(0xFFD4AF37);
      default:
        return TitanicTheme.raptureGold;
    }
  }

  String _formatJournalDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inMinutes < 1) {
        return 'Только что';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} мин. назад';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} ч. назад';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} дн. назад';
      } else {
        return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return dateString;
    }
  }
}

// Вспомогательные функции
Future<Map<String, dynamic>> fetchHonorState(String userId) async {
  // Заглушка - замените на реальную реализацию
  return {'used': false, 'm_balance': 0.0};
}

Future<void> openBuyTurnFlow({
  required BuildContext context,
  required SupabaseClient supabase,
  required GameService svc,
  required AppUser currentUser,
  required Future<void> Function() onRefreshProfile,
  required Function(String) showMessage,
}) async {
  // Заглушка - замените на реальную реализацию
}