// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:titanic/blocks/journalist_block.dart' as journalist_block;
import 'package:titanic/screens/home_dialogs.dart' as home_dialogs;

import 'package:titanic/models/app_user.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/services/debate_service.dart';
import 'package:titanic/services/speech_service.dart';
import 'package:titanic/screens/transfer_v_screen.dart';
import 'package:titanic/screens/inventory_screen.dart';
import 'package:titanic/screens/debates_screen.dart';
import 'package:titanic/screens/blood_poker_screen.dart';
import 'package:titanic/screens/purchase_enterprise_screen.dart';
import 'package:titanic/screens/resolution_vote_screen.dart';
import 'login_screen.dart';

// ✅ Listen button (уже в ArtDecoButton-стиле)
import 'package:titanic/widgets/listen_button.dart';

// Блоки
import 'package:titanic/blocks/movie_vote_block.dart';
import 'package:titanic/blocks/watched_movie_block.dart';
import 'package:titanic/blocks/hollywood_block.dart';
import 'package:titanic/blocks/mafia_block.dart' as mafia_blocks;

// Тема
import 'package:titanic/theme/app_theme.dart';

// ✅ Все “кнопки” вынесены сюда
import 'package:titanic/widgets/role_buttons.dart';

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

  static const String _bgAsset = 'assets/art_deco_login.png';
  static const String _frameOverlayAsset = 'assets/art_deco_frame_overlay.png';

  static const List<String> _allowedRegions = [
    'Азиатская группа',
    'Англа-саксонская группа',
    'Предсоциалистический блок',
    'Пиренейская группа',
    'Центрально-европейская группа',
  ];

  bool _speechButtonPreviouslyEnabled = true;

  late final DebateService debateService;
  late final SpeechService speechService;

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

  final List<Map<String, dynamic>> _pendingInventoryItems = [];

  List<Map<String, dynamic>> _journalEntries = [];
  RealtimeChannel? _journalChannel;
  int _newJournalEntriesCount = 0;
  String? _lastSpeechJournalSignature;
  double? _lastKnownVBalance;
  double? _lastKnownMBalance;
  DateTime? _lastPersistedBalanceAt;
  Timer? _pendingVBalanceJournalTimer;
  Timer? _pendingMBalanceJournalTimer;

  bool? _honorUsedLocal;
  double? _honorMBalance;

  // ✅ Цена запуска "Речь жизни"
  static const int _lifeSpeechCostM = 100;

  // -----------------------
  // ✅ ONLY DISPLAY OF BALANCES: helpers + streams
  // -----------------------
  double _parseNumericToDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  // ✅ Войсы — всегда целым числом
  String _formatVoices(double v) => v.round().toString();

  // ✅ Майнды — целое без .00 (если реально целое), иначе 2 знака
  String _formatMinds(double m) {
    final rounded = m.roundToDouble();
    if ((m - rounded).abs() < 0.00001) return rounded.toStringAsFixed(0);
    return m.toStringAsFixed(2);
  }

  Stream<double> _voicesBalanceStream() {
    return supabase
        .from('user_credentials')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .limit(1)
        .map((rows) {
          if (rows.isEmpty) return user.vBalance;
          final vRaw = rows.first['v_balance'];
          return _parseNumericToDouble(vRaw, fallback: user.vBalance);
        });
  }

  Stream<double> _mindsBalanceStream() {
    return supabase
        .from('user_credentials')
        .stream(primaryKey: ['id'])
        .eq('id', user.id)
        .limit(1)
        .map((rows) {
          if (rows.isEmpty) return user.mBalance;
          final mRaw = rows.first['m_balance'];
          return _parseNumericToDouble(mRaw, fallback: user.mBalance);
        });
  }

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

    _speechButtonPreviouslyEnabled = _isSpeechButtonEnabled;

    _loadJournal();
    _subscribeToJournal();

    _loadHonorLocalState();
  }

  @override
  void dispose() {
    _stopPollingSpeechState();
    _debatePollTimer?.cancel();
    _resolutionPollTimer?.cancel();
    _pollTimer?.cancel();
    _pendingVBalanceJournalTimer?.cancel();
    _pendingMBalanceJournalTimer?.cancel();
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

  Future<void> _loadHonorLocalState() async {
    try {
      final st = await journalist_block.fetchHonorState(user.id);
      if (!mounted) return;
      setState(() {
        _honorUsedLocal = (st['used'] as bool?) ?? false;
        _honorMBalance = (st['m_balance'] as double?) ?? user.mBalance;
        user = user.copyWith(mBalance: _honorMBalance ?? user.mBalance);
        _lastKnownMBalance = user.mBalance;
      });
    } catch (_) {}
  }

  String _journalEntryKey(Map<String, dynamic> entry) {
    final explicit = entry['journal_key']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final id = entry['id']?.toString();
    if (id != null && id.isNotEmpty) return 'id::$id';
    final title = (entry['title'] ?? '').toString();
    final message = (entry['message'] ?? '').toString();
    final createdAt = (entry['created_at'] ?? '').toString();
    return 'txt::$title::$message::$createdAt';
  }

  String _journalText(Map<String, dynamic> entry) {
    return [
      entry['title']?.toString() ?? '',
      entry['message']?.toString() ?? '',
      entry['metadata']?.toString() ?? '',
    ].join(' ').toLowerCase();
  }

  bool _isSpeechJournalEntry(Map<String, dynamic> entry) {
    final text = _journalText(entry);
    return (text.contains('speech_state') ||
            text.contains('речь жизни') ||
            text.contains('речь')) &&
        !text.contains('доступн');
  }

  bool _isBalanceJournalEntry(Map<String, dynamic> entry) {
    if ((entry['user_id']?.toString() ?? '') != user.id) return false;
    final text = _journalText(entry);
    return text.contains('v_balance') ||
        text.contains('m_balance') ||
        text.contains('баланс') ||
        text.contains('войс') ||
        text.contains('майнд');
  }

  Map<String, dynamic> _buildOfferJournalEntry(
    Map<String, dynamic> offer, {
    String? sellerName,
  }) {
    final offerId = offer['id']?.toString() ?? '';
    final item = offer['item_json'];
    String itemName = 'предмет';
    if (item is Map) {
      itemName =
          (item['name'] ?? item['label'] ?? item['id'] ?? 'предмет').toString();
    }
    final price = offer['price']?.toString() ?? '-';
    final seller = sellerName?.trim().isNotEmpty == true
        ? sellerName!.trim()
        : 'Игрок';

    return {
      'journal_key': 'offer::$offerId',
      'id': 'offer::$offerId',
      'title': 'Входящий оффер',
      'message':
          '$seller предлагает предмет "$itemName" за $price V. Принять или отклонить оффер можно в инвентаре.',
      'created_at':
          offer['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      'user_id': user.id,
      'metadata': {'type': 'incoming_offer', 'offer_id': offerId},
    };
  }

  Map<String, dynamic> _buildBalanceJournalEntry({
    required String balanceType,
    required num oldValue,
    required num newValue,
    String? createdAt,
  }) {
    final label = balanceType == 'v_balance' ? 'Войсы' : 'Майнды';
    final delta = newValue - oldValue;
    final deltaText =
        delta > 0 ? '+${delta.toStringAsFixed(0)}' : delta.toStringAsFixed(0);

    return {
      'journal_key':
          'balance::$balanceType::${createdAt ?? DateTime.now().toUtc().toIso8601String()}::$deltaText',
      'title': 'Изменение баланса',
      'message':
          '$label: ${oldValue.toStringAsFixed(0)} -> ${newValue.toStringAsFixed(0)} ($deltaText)',
      'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
      'user_id': user.id,
      'metadata': {'type': 'balance_change', 'balance': balanceType},
    };
  }

  Map<String, dynamic>? _normalizePersistedJournalEntry(Map<String, dynamic> raw) {
    if (_isBalanceJournalEntry(raw)) {
      return {
        'journal_key':
            'persisted-balance::${raw['id'] ?? raw['created_at'] ?? DateTime.now().toUtc().toIso8601String()}',
        'id': raw['id'],
        'title': 'Изменение баланса',
        'message': (raw['message'] ?? '').toString().trim(),
        'created_at':
            raw['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
        'user_id': user.id,
        'metadata': raw['metadata'],
      };
    }

    if (_isSpeechJournalEntry(raw)) {
      return {
        'journal_key':
            'persisted-speech::${raw['id'] ?? raw['created_at'] ?? DateTime.now().toUtc().toIso8601String()}',
        'id': raw['id'],
        'title': 'Речь жизни',
        'message': (raw['message'] ?? 'Кто-то начал речь жизни').toString().trim(),
        'created_at':
            raw['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
        'metadata': raw['metadata'],
      };
    }

    return null;
  }

  Future<String> _resolveUserLabel(String? userId) async {
    final id = (userId ?? '').trim();
    if (id.isEmpty) return 'Игрок';
    try {
      final row = await supabase
          .from('user_credentials')
          .select('first_name,last_name,telegram_username')
          .eq('id', id)
          .maybeSingle();
      if (row is Map<String, dynamic>) {
        final first = (row['first_name'] ?? '').toString().trim();
        final last = (row['last_name'] ?? '').toString().trim();
        final full = '$first $last'.trim();
        if (full.isNotEmpty) return full;
        final username = (row['telegram_username'] ?? '').toString().trim();
        if (username.isNotEmpty) return username;
      }
    } catch (_) {}
    return 'Игрок';
  }

  void _pushCuratedJournalEntry(Map<String, dynamic> entry, {bool notify = false}) {
    final key = _journalEntryKey(entry);
    if (_journalEntries.any((e) => _journalEntryKey(e) == key)) return;

    final updated = List<Map<String, dynamic>>.from(_journalEntries)
      ..insert(0, entry);
    updated.sort((a, b) {
      final da = DateTime.tryParse((a['created_at'] ?? '').toString());
      final db = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return 0;
    });

    if (!mounted) return;
    setState(() {
      _journalEntries = updated.take(50).toList();
      if (notify) _newJournalEntriesCount += 1;
    });

    if (notify) {
      final title = (entry['title'] ?? 'Журнал').toString();
      _showMessageSafe('Новая запись в журнале: $title');
    }
  }

  bool _isJournalVisibleToCurrentUser(Map<String, dynamic> row) {
    final vis = row['visible_role']?.toString();
    final role = (user.role ?? '').toString();
    return (row['user_id']?.toString() == user.id) ||
        vis == 'all' ||
        vis == role ||
        (vis == 'non_politician' && role != 'politician');
  }

  Future<Map<String, dynamic>?> _persistJournalEntry({
    String? userId,
    String? visibleRole,
    String? actorId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final inserted = await supabase
          .from('user_journal')
          .insert({
            'user_id': userId,
            'visible_role': visibleRole,
            'actor_id': actorId,
            'title': title,
            'message': message,
            'metadata': metadata,
          })
          .select('id,user_id,visible_role,actor_id,title,message,metadata,created_at')
          .maybeSingle();

      if (inserted is Map<String, dynamic>) {
        final normalized = _normalizePersistedJournalEntry(inserted);
        if (normalized != null) {
          _pushCuratedJournalEntry(normalized, notify: true);
        }
        if ((metadata?['type']?.toString() ?? '') == 'balance_change') {
          _lastPersistedBalanceAt = DateTime.now();
        }
        return inserted;
      }
    } catch (_) {}
    return null;
  }

  void _scheduleBalanceJournalPersistence({
    required String balanceType,
    required num oldValue,
    required num newValue,
  }) {
    final timer = balanceType == 'v_balance'
        ? _pendingVBalanceJournalTimer
        : _pendingMBalanceJournalTimer;
    timer?.cancel();

    final nextTimer = Timer(const Duration(milliseconds: 500), () async {
      final lastPersisted = _lastPersistedBalanceAt;
      if (lastPersisted != null &&
          DateTime.now().difference(lastPersisted) <
              const Duration(milliseconds: 900)) {
        return;
      }

      final entry = _buildBalanceJournalEntry(
        balanceType: balanceType,
        oldValue: oldValue,
        newValue: newValue,
      );

      final persisted = await _persistJournalEntry(
        userId: user.id,
        actorId: user.id,
        title: entry['title']?.toString() ?? 'Изменение баланса',
        message: entry['message']?.toString() ?? '',
        metadata: entry['metadata'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(entry['metadata'] as Map<String, dynamic>)
            : null,
      );

      if (persisted == null) {
        _pushCuratedJournalEntry(entry, notify: true);
      }
    });

    if (balanceType == 'v_balance') {
      _pendingVBalanceJournalTimer = nextTimer;
    } else {
      _pendingMBalanceJournalTimer = nextTimer;
    }
  }

  void _markJournalSeen() {
    if (!mounted || _newJournalEntriesCount == 0) return;
    setState(() => _newJournalEntriesCount = 0);
  }

  Future<void> _loadJournal() async {
    try {
      final role = (user.role ?? '').toString();
      final orFilter =
          'user_id.eq.${user.id},visible_role.eq.$role,visible_role.eq.all,visible_role.eq.non_politician';

      final journalRes = await supabase
          .from('user_journal')
          .select(
            'id,user_id,visible_role,actor_id,title,message,metadata,created_at',
          )
          .or(orFilter)
          .order('created_at', ascending: false)
          .limit(100);

      final offersRes = await supabase
          .from('item_offers')
          .select('id,seller_id,buyer_id,item_json,price,status,created_at')
          .eq('buyer_id', user.id)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(20);

      final Map<String, Map<String, dynamic>> merged = {};

      if (journalRes is List) {
        for (final row in journalRes) {
          final normalized =
              _normalizePersistedJournalEntry(Map<String, dynamic>.from(row as Map));
          if (normalized != null) {
            merged[_journalEntryKey(normalized)] = normalized;
          }
        }
      }

      if (offersRes is List) {
        for (final row in offersRes) {
          final offer = Map<String, dynamic>.from(row as Map);
          final sellerName = await _resolveUserLabel(offer['seller_id']?.toString());
          final entry = _buildOfferJournalEntry(offer, sellerName: sellerName);
          merged[_journalEntryKey(entry)] = entry;
        }
      }

      final entries = merged.values.toList()
        ..sort((a, b) {
          final da = DateTime.tryParse((a['created_at'] ?? '').toString());
          final db = DateTime.tryParse((b['created_at'] ?? '').toString());
          if (da != null && db != null) return db.compareTo(da);
          if (da != null) return -1;
          if (db != null) return 1;
          return 0;
        });

      if (!mounted) return;
      setState(() => _journalEntries = entries.take(50).toList());
    } catch (e) {
      print('loadJournal error: $e');
    }
  }

  void _subscribeToJournal() {
    try {
      _journalChannel = supabase.channel('journal-feed-${user.id}');
      _journalChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'user_journal',
            callback: (payload) {
              final rec = payload.newRecord;
              if (rec == null) return;
              final row = Map<String, dynamic>.from(rec as Map);
              if (!_isJournalVisibleToCurrentUser(row)) return;
              final normalized = _normalizePersistedJournalEntry(row);
              if (normalized == null) return;
              final meta = row['metadata'];
              if (meta is Map &&
                  (meta['type']?.toString() ?? '') == 'balance_change') {
                _lastPersistedBalanceAt = DateTime.now();
              }
              _pushCuratedJournalEntry(normalized, notify: true);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'item_offers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'buyer_id',
              value: user.id,
            ),
            callback: (payload) async {
              final rec = payload.newRecord;
              if (rec == null) return;
              final offer = Map<String, dynamic>.from(rec as Map);
              if ((offer['status']?.toString() ?? 'pending') != 'pending') return;
              final sellerName = await _resolveUserLabel(offer['seller_id']?.toString());
              _pushCuratedJournalEntry(
                _buildOfferJournalEntry(offer, sellerName: sellerName),
                notify: true,
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'user_credentials',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: user.id,
            ),
            callback: (payload) {
              final newRec = payload.newRecord;
              final oldRec = payload.oldRecord;
              if (newRec == null) return;

              num parseNum(dynamic value) {
                if (value is num) return value;
                return num.tryParse(value?.toString() ?? '') ?? 0;
              }

              final newV = parseNum(newRec['v_balance']);
              final newM = parseNum(newRec['m_balance']);
              final oldV = oldRec != null && oldRec['v_balance'] != null
                  ? parseNum(oldRec['v_balance'])
                  : (_lastKnownVBalance ?? user.vBalance);
              final oldM = oldRec != null && oldRec['m_balance'] != null
                  ? parseNum(oldRec['m_balance'])
                  : (_lastKnownMBalance ?? user.mBalance);

              if (oldV != newV) {
                _scheduleBalanceJournalPersistence(
                  balanceType: 'v_balance',
                  oldValue: oldV,
                  newValue: newV,
                );
              }
              if (oldM != newM) {
                _scheduleBalanceJournalPersistence(
                  balanceType: 'm_balance',
                  oldValue: oldM,
                  newValue: newM,
                );
              }

              _lastKnownVBalance = newV.toDouble();
              _lastKnownMBalance = newM.toDouble();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'speech_state',
            callback: (payload) async {
              final rec = payload.newRecord;
              if (rec == null) return;
              final row = Map<String, dynamic>.from(rec as Map);
              final isActive = row['active'] == true;
              final actorId = row['actor_id']?.toString();
              if (!isActive || actorId == null || actorId.isEmpty) return;

              final signature =
                  '$actorId::${row['expires_at']?.toString() ?? ''}::${row['active']}';
              if (_lastSpeechJournalSignature == signature) return;
              _lastSpeechJournalSignature = signature;

              final actorName = await _resolveUserLabel(actorId);
              await _persistJournalEntry(
                visibleRole: 'all',
                actorId: actorId,
                title: 'Речь жизни',
                message: '$actorName начал(а) речь жизни.',
                metadata: {'type': 'speech_started', 'actor_id': actorId},
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'speech_state',
            callback: (payload) async {
              final rec = payload.newRecord;
              if (rec == null) return;
              final row = Map<String, dynamic>.from(rec as Map);
              final isActive = row['active'] == true;
              final actorId = row['actor_id']?.toString();
              if (!isActive || actorId == null || actorId.isEmpty) return;

              final signature =
                  '$actorId::${row['expires_at']?.toString() ?? ''}::${row['active']}';
              if (_lastSpeechJournalSignature == signature) return;
              _lastSpeechJournalSignature = signature;

              final actorName = await _resolveUserLabel(actorId);
              await _persistJournalEntry(
                visibleRole: 'all',
                actorId: actorId,
                title: 'Речь жизни',
                message: '$actorName начал(а) речь жизни.',
                metadata: {'type': 'speech_started', 'actor_id': actorId},
              );
            },
          )
          .subscribe();
    } catch (e) {
      print('subscribeToJournal error: $e');
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final profileRaw = await supabase
          .from('user_credentials')
          .select(
            'v_balance, m_balance, first_name, last_name, telegram_username, role, color, region, usurer',
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
        final usurer = profile['usurer'];

        if (!mounted) return;
        setState(() {
          final nextV = v is num ? (v).toDouble() : user.vBalance;
          final nextM = m is num ? (m).toDouble() : user.mBalance;
          user = AppUser(
            id: user.id,
            username: uname is String ? uname : user.username,
            role: role is String ? role : user.role,
            firstName: fn is String ? fn : user.firstName,
            lastName: ln is String ? ln : user.lastName,
            vBalance: nextV,
            mBalance: nextM,
            color: color is String ? color : user.color,
            region: region is String ? region : user.region,
            usurer: (usurer == true) ||
                (usurer?.toString().toLowerCase() == 'true'),
          );
          _userColor = color is String ? color : null;
          _lastKnownVBalance = nextV;
          _lastKnownMBalance = nextM;
        });
      }
    } catch (_) {}
    await _loadHonorLocalState();
  }

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

          final newEnabled = _isSpeechButtonEnabled;
          _speechButtonPreviouslyEnabled = newEnabled;
          return;
        }

        if (!mounted) return;
        setState(() {
          speechActive = active;
          speechActorId = actor;
          speechExpiresAt = expires;
        });

        try {
          final life = await svc.getActiveLifeSpeech();
          if (life is Map<String, dynamic>) {
            _activeSpeechId = (life['id'] is int)
                ? (life['id'] as int)
                : int.tryParse(life['id']?.toString() ?? '');
          }
          await _checkIfListened();
        } catch (_) {}

        final newEnabled = _isSpeechButtonEnabled;
        _speechButtonPreviouslyEnabled = newEnabled;
      } else {
        if (!mounted) return;
        setState(() {
          speechActive = false;
          speechActorId = null;
          speechExpiresAt = null;
          _activeSpeechId = null;
          _listenedToThisSpeech = false;
        });

        final newEnabled = _isSpeechButtonEnabled;
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

  // ✅ Надёжное сообщение (через post-frame), чтобы точно показывалось
  void _showMessageSafe(String m) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    });
  }

  // ✅ Текущее значение m_balance (с сервера)
  Future<double> _fetchCurrentMBalance() async {
    final row = await supabase
        .from('user_credentials')
        .select('m_balance')
        .eq('id', user.id)
        .maybeSingle();

    final raw = row?['m_balance'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? user.mBalance;
    return user.mBalance;
  }

  // ✅ Записать новый m_balance
  Future<void> _setMBalance(double newVal) async {
    await supabase
        .from('user_credentials')
        .update({'m_balance': newVal})
        .eq('id', user.id);
  }

  Future<void> _onStartSpeechPressed() async {
    if (user.role != 'politician') return;
    if (_rpcLoading) return;

    if (!_isSpeechButtonEnabled) {
      _showMessageSafe('Речь жизни сейчас недоступна.');
      return;
    }

    // ✅ 1) Проверка баланса и сообщение, если не хватает
    double currentM;
    try {
      currentM = await _fetchCurrentMBalance();
    } catch (_) {
      _showMessageSafe('Не удалось получить баланс майндов. Попробуйте ещё раз.');
      return;
    }

    if (currentM < _lifeSpeechCostM) {
      _showMessageSafe(
        'Недостаточно майндов для запуска "Речь жизни". Нужно $_lifeSpeechCostM, у вас ${_formatMinds(currentM)}.',
      );
      return;
    }

    // ✅ 2) Списываем майнды ДО RPC
    try {
      await _setMBalance(currentM - _lifeSpeechCostM);
      if (mounted) {
        setState(() => user = user.copyWith(mBalance: currentM - _lifeSpeechCostM));
      }
    } catch (_) {
      _showMessageSafe('Не удалось списать майнды. Попробуйте ещё раз.');
      return;
    }

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
      _listenedToThisSpeech = false;
    });

    _speechButtonPreviouslyEnabled = false;

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
      } catch (_) {
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
  // Навигация
  // -----------------------
  Future<void> _openTransferScreen() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransferVScreen(user: user)),
    );
    if (res == true) await _refreshProfile();
  }

  Future<void> _openInventoryScreen() async {
    _markJournalSeen();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InventoryScreen(user: user)),
    );
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
    final bool? res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResolutionVoteScreen(
          resolutionId: resolutionId,
          userId: user.id,
          service: svc,
        ),
      ),
    );

    if (res == true) {
      await _refreshProfile();
      await _loadResolutionState();
      if (!mounted) return;
      setState(() {
        _alreadyBetInActiveResolution = true;
      });
    } else {
      await _loadResolutionState();
    }
  }

  Future<void> _openBloodPokerScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BloodPokerScreen(
          currentUserId: user.id,
          onBetPlaced: _onBloodPokerBetPlaced,
        ),
      ),
    );
    await _refreshProfile();
    await _loadJournal();
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
    String z(int n) => n.toString().padLeft(2, "0");
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
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  Widget _buildArtDecoBackground({required Widget child}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: Image(
            image: AssetImage(_bgAsset),
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(
            color: TitanicTheme.abyssalBlue.withOpacity(0.82),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 1.05,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.20,
              child: Image.asset(
                _frameOverlayAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  // -----------------------
  // Chips (цвет — у всех, регион — только у экономиста)
  // -----------------------
  String? _normalizedRegion() {
    final r = (user.region ?? '').toString().trim();
    if (r.isEmpty) return null;
    if (_allowedRegions.contains(r)) return r;
    return r;
  }

  Widget _buildChip({
    required String text,
    required Color borderColor,
    required Color fillColor,
    required bool isSmallScreen,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 10 : 12,
        vertical: isSmallScreen ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: isSmallScreen ? 12.5 : 13.5,
          color: TitanicTheme.ivoryCream,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildColorAndRegionChips(bool isSmallScreen) {
    final colorName = (_userColor ?? user.color ?? '').toString().trim();
    final showColor = colorName.isNotEmpty;

    final regionName = _isRole('economist') ? _normalizedRegion() : null;
    final showRegion = regionName != null && regionName.trim().isNotEmpty;

    if (!showColor && !showRegion) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (showColor)
          _buildChip(
            text: colorName,
            borderColor: _getColorFromString(colorName).withOpacity(0.55),
            fillColor: _getColorFromString(colorName).withOpacity(0.22),
            isSmallScreen: isSmallScreen,
          ),
        if (showRegion)
          _buildChip(
            text: regionName!,
            borderColor: TitanicTheme.raptureGold.withOpacity(0.45),
            fillColor: TitanicTheme.surfaceNavy.withOpacity(0.35),
            isSmallScreen: isSmallScreen,
          ),
      ],
    );
  }

  // -----------------------
  // BUILD
  // -----------------------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

    // ✅ ПОКАЗЫВАЕМ "Прослушал речь жизни" если Речь жизни была запущена (активна сейчас).
    final nowUtc = DateTime.now().toUtc();
    final bool speechIsCurrentlyOn =
        speechActive && (speechExpiresAt == null || nowUtc.isBefore(speechExpiresAt!));
    final bool isPoliticianUser = _isRole('politician');
    final bool isCurrentUserSpeechActor =
        speechActorId != null && speechActorId == user.id;
    final bool replaceSpeechButtonWithListen =
        isPoliticianUser && speechIsCurrentlyOn && isCurrentUserSpeechActor;

    final Widget listenWidget = speechIsCurrentlyOn
        ? ListenButton(
            userId: user.id,
            activeSpeechId: _activeSpeechId,
            speechActorId: speechActorId,
            speechActive: speechActive,
            alreadyListened: _listenedToThisSpeech,
            onListenComplete: (rpcResult) async {
              try {
                if (!mounted) return;
                setState(() => _listenedToThisSpeech = true);
                await _refreshProfile();
                await _loadJournal();
                await _checkIfListened();
              } catch (_) {}
            },
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildArtDecoBackground(
        child: SafeArea(
          child: Column(
            children: [
              // TOP BAR
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildCrystalButton(
                      icon: Icons.sailing,
                      onPressed: () {},
                      iconColor: TitanicTheme.raptureGold,
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        child: Image.asset(
                          'assets/navbar.png',
                          height: isSmallScreen ? 32 : 40,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    ),
                    _buildCrystalButton(
                      icon: Icons.refresh,
                      onPressed: _logout,
                      iconColor: TitanicTheme.raptureGold,
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // PROFILE CARD
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRoleAvatar(user.role),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${user.firstName} ${user.lastName}',
                                          style: TextStyle(
                                            fontFamily: 'CormorantGaramond',
                                            fontSize: isSmallScreen ? 22 : 26,
                                            fontWeight: FontWeight.w700,
                                            color: TitanicTheme.ivoryCream,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        _buildColorAndRegionChips(isSmallScreen),
                                        if (user.usurer) ...[
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: TitanicTheme.copperDetail
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: TitanicTheme.copperDetail,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Text(
                                              'Ростовщик',
                                              style: TextStyle(
                                                fontFamily: 'Cinzel',
                                                fontSize:
                                                    isSmallScreen ? 11 : 12,
                                                fontWeight: FontWeight.w700,
                                                color: TitanicTheme.ivoryCream,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // BALANCES
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: TitanicTheme.surfaceNavy.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: TitanicTheme.raptureGold.withOpacity(0.25),
                                    width: 1.5,
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
                                            fontSize: 13,
                                            color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        StreamBuilder<double>(
                                          stream: _voicesBalanceStream(),
                                          initialData: user.vBalance,
                                          builder: (context, snap) {
                                            final val = snap.data ?? user.vBalance;
                                            return Text(
                                              _formatVoices(val),
                                              style: TextStyle(
                                                fontFamily: 'CormorantGaramond',
                                                fontSize: isSmallScreen ? 24 : 28,
                                                fontWeight: FontWeight.w700,
                                                color: TitanicTheme.raptureGold,
                                                letterSpacing: 1.0,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    Container(
                                      width: 1.5,
                                      height: 45,
                                      color: TitanicTheme.raptureGold.withOpacity(0.25),
                                    ),
                                    Column(
                                      children: [
                                        Text(
                                          'Майнды',
                                          style: TextStyle(
                                            fontFamily: 'Cinzel',
                                            fontSize: 13,
                                            color: TitanicTheme.ivoryCream.withOpacity(0.7),
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        StreamBuilder<double>(
                                          stream: _mindsBalanceStream(),
                                          initialData: user.mBalance,
                                          builder: (context, snap) {
                                            final val = snap.data ?? user.mBalance;
                                            return Text(
                                              _formatMinds(val),
                                              style: TextStyle(
                                                fontFamily: 'CormorantGaramond',
                                                fontSize: isSmallScreen ? 24 : 28,
                                                fontWeight: FontWeight.w700,
                                                color: TitanicTheme.seaFoamGreen,
                                                letterSpacing: 1.0,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ✅ Блок действий: теперь кнопки только из RoleButtons, и все в ArtDecoButton-стиле
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RoleButtons(
  user: user,
  onTransfer: _openTransferScreen,
  onOpenInventory: _openInventoryScreen,
  onBuyTurn: _openBuyTurnFlow,
  onPurchaseEnterprise: _openPurchaseEnterprise,
  onOpenDebates: _openDebates,
  onOpenResolution: _onOpenResolutionPressed,
  onStartSpeech: _onStartSpeechPressed,
  speechButtonEnabled: _isSpeechButtonEnabled,
  replaceSpeechButtonWithListen: replaceSpeechButtonWithListen,
  listenWidget: listenWidget,
  hasActiveDebate: _hasActiveDebate,
  alreadyVotedInActiveDebate: _alreadyVotedInActiveDebate,
  hasActiveResolution: _hasActiveResolution,
  alreadyBetInActiveResolution: _alreadyBetInActiveResolution,

  honorAlreadyUsed: _honorUsedLocal ?? false,
  onHonorArticle: () async {
    await journalist_block.showHonorArticleDialog(
      context,
      user.id,
      onPublished: () async {
        await _refreshProfile();
        await _loadJournal();
        await _loadHonorLocalState();
      },
    );
  },

  // ✅ ДОБАВЬ ВОТ ЭТО:
  onInvestInColor: () async {
    await home_dialogs.showInvestInColorDialog(
      context: context,
      supabase: supabase,
      userId: user.id,
      onCompleted: () async {
        await _refreshProfile();
        await _loadJournal();
      },
      showMessage: _showMessage,
    );
  },
),



                              // ниже — блоки (они уже используют ArtDecoButton внутри)
                              if (_isRole('мафия')) ...[
                                const SizedBox(height: 12),
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
                                const SizedBox(height: 12),
                                Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.casino),
                                    title: const Text('Покер на крови'),
                                    subtitle: const Text(
                                      'Открыть экран ставок',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: _openBloodPokerScreen,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 12),
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
                      ),

                      const SizedBox(height: 24),
                      _buildJournalBlock(isSmallScreen),

                      const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------
  // Верхние кристальные кнопки
  // -----------------------
  Widget _buildCrystalButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = TitanicTheme.raptureGold,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Transform.rotate(
          angle: 45 * 3.1415926535 / 180,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TitanicTheme.surfaceNavy.withOpacity(0.9),
                  TitanicTheme.abyssalBlue.withOpacity(0.8),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 8,
                  offset: const Offset(3, 3),
                ),
                BoxShadow(
                  color: TitanicTheme.raptureGold.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(-2, -2),
                ),
              ],
              border: Border.all(
                color: TitanicTheme.raptureGold.withOpacity(0.3),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Transform.rotate(
                angle: -45 * 3.1415926535 / 180,
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------
  // Avatar
  // -----------------------
  String _getRoleImagePath(String role) {
    final roleLower = role.toLowerCase();

    if (roleLower.contains('мафия') || roleLower.contains('mafia')) {
      return 'assets/mafia.png';
    } else if (roleLower.contains('голливуд') || roleLower.contains('hollywood')) {
      return 'assets/hollywood.png';
    } else if (roleLower.contains('экономист') || roleLower.contains('economist')) {
      return 'assets/economist.png';
    } else if (roleLower.contains('журналист') || roleLower.contains('journalist')) {
      return 'assets/journalist.png';
    } else if (roleLower.contains('общественный') ||
        roleLower.contains('public') ||
        roleLower.contains('деятель')) {
      return 'assets/public_figure.png';
    } else if (roleLower.contains('политик') || roleLower.contains('politician')) {
      return 'assets/politic.png';
    } else {
      return 'assets/default_role.png';
    }
  }

  Widget _buildRoleAvatar(String role) {
    final imagePath = _getRoleImagePath(role);

    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TitanicTheme.abyssalBlue,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: TitanicTheme.raptureGold.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: TitanicTheme.raptureGold.withOpacity(0.5),
          width: 2.5,
        ),
      ),
      child: Center(
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            TitanicTheme.raptureGold,
            BlendMode.srcIn,
          ),
          child: Image.asset(
            imagePath,
            width: 56,
            height: 56,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.person,
                size: 56,
                color: TitanicTheme.raptureGold,
              );
            },
          ),
        ),
      ),
    );
  }

  // -----------------------
  // Journal block
  // -----------------------
  Widget _buildJournalBlock(bool isSmallScreen) {
    return GestureDetector(
      onTap: _markJournalSeen,
      child: Container(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Журнал событий',
                      style: TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: isSmallScreen ? 22 : 24,
                        fontWeight: FontWeight.w700,
                        color: TitanicTheme.ivoryCream,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (_newJournalEntriesCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: TitanicTheme.raptureGold.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: TitanicTheme.raptureGold.withOpacity(0.65),
                        ),
                      ),
                      child: Text(
                        'Новых: $_newJournalEntriesCount',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: TitanicTheme.raptureGold,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Офферы, изменения вашего баланса и старт речи жизни.',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: 11,
                  color: TitanicTheme.ivoryCream.withOpacity(0.58),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 20),
              if (_journalEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 60,
                        color: TitanicTheme.ivoryCream.withOpacity(0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'История событий пуста',
                        style: TextStyle(
                          fontFamily: 'Cinzel',
                          fontSize: 15,
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
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: TitanicTheme.surfaceNavy.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: TitanicTheme.raptureGold.withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['title']?.toString() ?? 'Событие',
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: TitanicTheme.ivoryCream,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            entry['message']?.toString() ?? '',
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 14,
                              color: TitanicTheme.ivoryCream.withOpacity(0.85),
                              letterSpacing: 0.3,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: TitanicTheme.ivoryCream.withOpacity(0.5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatJournalDate(entry['created_at']?.toString()),
                                style: TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 12,
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
    );
  }

  // -----------------------
  // Color helpers + date
  // -----------------------
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
        return '${date.day.toString().padLeft(2, "0")}.${date.month.toString().padLeft(2, "0")}';
      }
    } catch (e) {
      return dateString;
    }
  }
}

Future<void> openBuyTurnFlow({
  required BuildContext context,
  required SupabaseClient supabase,
  required GameService svc,
  required AppUser currentUser,
  required Future<void> Function() onRefreshProfile,
  required void Function(String) showMessage,
}) async {
  List<Map<String, dynamic>> econs = [];
  try {
    final res = await supabase
        .from('user_credentials')
        .select('id, first_name, last_name, telegram_username')
        .eq('role', 'economist')
        .order('first_name');
    if (res is List) {
      econs = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (e) {
    showMessage('Не удалось загрузить список экономистов: $e');
    return;
  }

  if (econs.isEmpty) {
    showMessage('Нет доступных экономистов для покупки хода.');
    return;
  }

  final Map<String, dynamic>? chosen =
      await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Поиск экономиста',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (q) {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Отмена')),
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: ListView.separated(
                  itemCount: econs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, index) {
                    final row = econs[index];
                    final first = (row['first_name'] ?? '').toString();
                    final last = (row['last_name'] ?? '').toString();
                    final displayName = ('$first $last').trim().isEmpty
                        ? (row['telegram_username'] ?? 'Без имени')
                        : '$first $last';
                    return ListTile(
                      title: Text(displayName),
                      onTap: () => Navigator.of(context).pop(row),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (chosen == null) return;

  final first = (chosen['first_name'] ?? '').toString();
  final last = (chosen['last_name'] ?? '').toString();
  final displayName = ('$first $last').trim().isEmpty
      ? (chosen['telegram_username'] ?? 'Без имени')
      : '$first $last';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Купить ход экономисту'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Стоимость: 40 войсов'),
          const SizedBox(height: 8),
          Text('Получатель: $displayName'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена')),
        ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Купить')),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final rpcRes = await svc.rpcBuyEconomistTurn(
      fromUser: currentUser.id,
      toUser: chosen['id'].toString(),
      cost: 40,
    );

    Navigator.of(context).pop();

    if (rpcRes == null) {
      showMessage('Неожиданный ответ сервера');
      return;
    }

    final status =
        (rpcRes['status'] ?? rpcRes['result'] ?? '').toString().toLowerCase();
    if (status.contains('ok') || status.contains('success') || status == 'ok') {
      showMessage('Покупка успешна: у экономиста добавлен предмет "Дополнительный ход"');

      try {
        await onRefreshProfile();
      } catch (_) {}
    } else {
      final msg = rpcRes['message']?.toString() ?? rpcRes.toString();
      showMessage('Ошибка: $msg');
    }
  } catch (e) {
    try {
      Navigator.of(context).pop();
    } 
    catch (_) {}
    if('$e' == "PostgrestException(message: insufficient_balance, code: P0001, details: Bad Request, hint: null)") {
      showMessage('Ошибка при покупке: недостаточно войсов');
    } else {
      showMessage('Ошибка при покупке: $e');
    }
  }
}
