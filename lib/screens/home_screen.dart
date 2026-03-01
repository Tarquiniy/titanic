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
      });
    } catch (_) {}
  }

  Future<void> _insertJournalEntry(
    String title,
    String message, {
    String? visibleRole,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
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

    if (mounted) {
      setState(() {
        _journalEntries.insert(0, localRow);
      });
    }

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
    } catch (_) {}
  }

  String _normalizeJournalMessage(String msg) {
    if (msg.isEmpty) return msg;
    var out = msg;
    try {
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

      out = out.replaceAll('Тип: Изменён статус', 'Изменён статус');
      out = out.replaceAll(RegExp(r'\s+'), ' ');
      return out.trim();
    } catch (_) {
      return msg.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }

  Future<void> _loadJournal() async {
    try {
      final role = (user.role ?? '').toString();
      final userId = user.id;
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
        final List<Map<String, dynamic>> rows =
            res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final Map<String, Map<String, dynamic>> uniq = {};
        for (final r in rows) {
          String title = (r['title'] ?? '').toString();
          String message = (r['message'] ?? '').toString();

          if (title.toLowerCase().contains('speech_state') ||
              title.toLowerCase().contains('речь')) {
            title = 'Речь жизни';
          }
          message = _normalizeJournalMessage(message);

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
        if (!mounted) return;
        setState(() => _journalEntries = []);
      }
    } catch (e) {
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
            callback: (payload) {
              final rec = payload.newRecord ?? payload.oldRecord;
              if (rec == null) return;
              final Map<String, dynamic> row = Map<String, dynamic>.from(
                rec as Map,
              );

              final String? vis = row['visible_role']?.toString();
              final String role = (user.role ?? '').toString();
              final bool visibleToUser =
                  (row['user_id']?.toString() == user.id) ||
                      vis == null ||
                      vis == 'all' ||
                      vis == role ||
                      (vis == 'non_politician' && role != 'politician');

              if (!visibleToUser) return;

              String title = (row['title'] ?? '').toString();
              String message = (row['message'] ?? '').toString();

              if (title.toLowerCase().contains('speech_state') ||
                  title.toLowerCase().contains('речь')) {
                title = 'Речь жизни';
              }
              message = _normalizeJournalMessage(message);
              if (title.toLowerCase().contains('изменение профиля') &&
                  !message.toLowerCase().contains('добав')) {
                return;
              }
              if (message.toLowerCase().contains('добавлен') &&
                  title.toLowerCase().contains('изменение профиля')) {
                title = 'Добавлен предмет';
              }

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
      // ignore: avoid_print
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
            usurer: (usurer == true) ||
                (usurer?.toString().toLowerCase() == 'true'),
          );
          _userColor = color is String ? color : null;
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
        if (_speechButtonPreviouslyEnabled == false && newEnabled == true) {
          await _insertJournalEntry(
            'Речь жизни доступна!',
            'Кнопка "Речь жизни" снова доступна для запуска.',
            visibleRole: 'politician',
          );
        }
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
    return Container(
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
                fontSize: isSmallScreen ? 22 : 24,
                fontWeight: FontWeight.w700,
                color: TitanicTheme.ivoryCream,
                letterSpacing: 0.5,
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
