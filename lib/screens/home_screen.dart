// lib/screens/home_screen.dart
//
// NOTE: This file was updated to:
//  - Poll offer-related events via RPC `pull_offer_events`
//  - Feed new events into existing `handleIncomingEvent` (which already plays sound and shows UI)

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:titanic/models/app_user.dart';
import 'package:titanic/screens/debates_screen.dart';
import 'package:titanic/services/game_service.dart';

import 'login_screen.dart';
import 'transfer_v_screen.dart';
import 'inventory_screen.dart';
import 'package:titanic/widgets/listen_button.dart';

class HomeScreen extends StatefulWidget {
  final AppUser user;

  const HomeScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late AppUser user;

  final supabase = Supabase.instance.client;
  final GameService svc = GameService();

  RealtimeChannel? eventsChannel;

  final List<Map<String, dynamic>> userEvents = [];

  html.AudioElement? notifyAudio;
  bool audioUnlocked = false;

  // Speech state
  bool speechActive = false;
  String? speechActorId;
  DateTime? speechExpiresAt; // UTC - client lock/unlock time
  int? activeSpeechId; // Active lifespeech record id needed for listen RPC

  // color usercredentials
  String? userColor;

  // Polling
  Timer? pollTimer;

  // RPC loading flags
  bool rpcLoading = false;

  // Waiting for server confirm after startSpeech
  bool waitingForServerConfirm = false;

  // Listen historical flag
  bool listenedToThisSpeech = false;

  // ---- Debates state ----
  bool hasActiveDebate = false;
  int? activeDebateId;
  bool alreadyVotedInActiveDebate = false;
  Timer? debatePollTimer;

  // ---- Political resolutions state ----
  bool hasActiveResolution = false;
  int? activeResolutionId;
  bool alreadyBetInActiveResolution = false;
  Timer? resolutionPollTimer;

  // Pending client-side inventory additions list of owner_id, name, count, created_at, metadata
  final List<Map<String, dynamic>> pendingInventoryItems = [];

  // === NEW: Offer events polling ===
  Timer? offerPollTimer;
  final Set<String> _seenOfferEventIds = <String>{};

  @override
  void initState() {
    super.initState();
    user = widget.user;

    refreshProfile();
    fetchSpeechState();

    startPollingSpeechState();
    loadDebateState();
    startDebatePolling();
    loadResolutionState();
    startResolutionPolling();

    initWebAudio();
    requestBrowserPermission();
    subscribeToUserEvents();
    loadUserEvents();

    // NEW: start polling offer events (in addition to realtime channel)
    startOfferPolling(4);
  }

  @override
  void dispose() {
    stopPollingSpeechState();
    debatePollTimerCancel();
    resolutionPollTimerCancel();

    // NEW
    stopOfferPolling();

    eventsChannel?.unsubscribe();
    super.dispose();
  }

  // ----------------------- WEB AUDIO -----------------------
  void initWebAudio() {
    notifyAudio = html.AudioElement('assets/notify.mp3');
  }

  void unlockAudio() {
    if (audioUnlocked) return;
    audioUnlocked = true;
    notifyAudio?.play().catchError((_) {});
  }

  void playNotifySound() {
    if (!audioUnlocked) return;
    notifyAudio?.currentTime = 0;
    notifyAudio?.play().catchError((_) {});
  }

  // ----------------------- BROWSER NOTIFICATIONS -----------------------
  void requestBrowserPermission() {
    if (html.Notification.supported) {
      if (html.Notification.permission == 'default') {
        html.Notification.requestPermission();
      }
    }
  }

  void showBrowserNotification(String title, String body) {
    if (!html.Notification.supported) return;
    if (html.Notification.permission != 'granted') return;
    html.Notification(title, body: body);
  }

  // ----------------------- REALTIME EVENTS -----------------------
  void subscribeToUserEvents() {
    eventsChannel = supabase.channel('user-events-${user.id}');

    eventsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            handleIncomingEvent(Map<String, dynamic>.from(data));
          },
        )
        .subscribe();
  }

  Future<void> loadUserEvents() async {
    try {
      final res = await supabase
          .from('user_events')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      if (res is List) {
        setState(() => userEvents.addAll(res.cast<Map<String, dynamic>>()));
      }
    } catch (_) {}
  }

  void handleIncomingEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() => userEvents.insert(0, event));
    playNotifySound();
    showBrowserNotification(event['title'] ?? '', event['message'] ?? '');
    showEventPopup(event);
  }

  void showEventPopup(Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(event['title'] ?? ''),
        content: Text(event['message'] ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ----------------------- NEW: OFFER EVENTS POLLING -----------------------
  void startOfferPolling([int seconds = 4]) {
    offerPollTimer?.cancel();
    offerPollTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      _pollOfferEvents();
    });
  }

  void stopOfferPolling() {
    offerPollTimer?.cancel();
    offerPollTimer = null;
  }

  Future<void> _pollOfferEvents() async {
    if (!mounted) return;

    try {
      final res = await supabase.rpc('pull_offer_events', params: {
        'p_user_id': user.id,
        'p_limit': 20,
      });

      final List<Map<String, dynamic>> rows = [];
      if (res is List) {
        for (final r in res) {
          if (r is Map) rows.add(Map<String, dynamic>.from(r as Map));
        }
      } else if (res is Map) {
        rows.add(Map<String, dynamic>.from(res as Map));
      }

      for (final e in rows) {
        final id = e['id']?.toString();
        if (id == null || id.isEmpty) continue;

        if (_seenOfferEventIds.contains(id)) continue;
        _seenOfferEventIds.add(id);

        // Reuse existing behavior: sound + popup + event list
        handleIncomingEvent(e);
      }
    } catch (_) {
      // silent: polling should not spam UI
    }
  }

  // Small helpers to keep analyzer happy (no-op placeholders)
  void debatePollTimerCancel() => debatePollTimer?.cancel();
  void resolutionPollTimerCancel() => resolutionPollTimer?.cancel();

  // ----------------------- Profile balance refresh now also loads color and region -----------------------
  Future<void> refreshProfile() async {
    try {
      final profileRaw = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance, first_name, last_name, telegram_username, role, color, region')
          .eq('id', user.id)
          .maybeSingle();

      final profile = profileRaw is Map<String, dynamic> ? profileRaw : null;
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
            vBalance: v is num ? v.toDouble() : user.vBalance,
            mBalance: m is num ? m.toDouble() : user.mBalance,
            color: color is String ? color : user.color,
            region: region is String ? region : user.region,
          );
          userColor = color is String ? color : null;
        });
      }
    } catch (_) {
      // ignore refresh errors
    }
  }

  // ----------------------- Debates load active state and whether current user already voted -----------------------
  Future<void> loadDebateState() async {
    try {
      final active = await supabase
          .from('debates')
          .select('id')
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (active is Map<String, dynamic> && active['id'] != null) {
        final int id = active['id'] is int ? active['id'] as int : int.parse(active['id'].toString());
        bool already = false;

        try {
          final vote = await supabase
              .from('debate_votes')
              .select('id')
              .eq('debate_id', id)
              .eq('user_id', user.id)
              .limit(1)
              .maybeSingle();
          already = vote != null;
        } catch (_) {
          already = false;
        }

        if (!mounted) return;
        setState(() {
          hasActiveDebate = true;
          activeDebateId = id;
          alreadyVotedInActiveDebate = already;
        });
      } else {
        if (!mounted) return;
        setState(() {
          hasActiveDebate = false;
          activeDebateId = null;
          alreadyVotedInActiveDebate = false;
        });
      }
    } catch (_) {
      // ignore errors, leave previous state
    }
  }

  void startDebatePolling([int seconds = 5]) {
    debatePollTimer?.cancel();
    debatePollTimer = Timer.periodic(Duration(seconds: seconds), (_) => loadDebateState());
  }

  // ----------------------- Resolutions load active resolution and whether user already bet -----------------------
  Future<void> loadResolutionState() async {
    try {
      final active = await supabase
          .from('political_resolutions')
          .select('id')
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (active is Map<String, dynamic> && active['id'] != null) {
        final int id = active['id'] is int ? active['id'] as int : int.parse(active['id'].toString());
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
          hasActiveResolution = true;
          activeResolutionId = id;
          alreadyBetInActiveResolution = already;
        });
      } else {
        if (!mounted) return;
        setState(() {
          hasActiveResolution = false;
          activeResolutionId = null;
          alreadyBetInActiveResolution = false;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  void startResolutionPolling([int seconds = 5]) {
    resolutionPollTimer?.cancel();
    resolutionPollTimer = Timer.periodic(Duration(seconds: seconds), (_) => loadResolutionState());
  }

  void stopResolutionPolling() {
    resolutionPollTimer?.cancel();
    resolutionPollTimer = null;
  }

  // ----------------------- Polling speech state -----------------------
  void startPollingSpeechState([int seconds = 3]) {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => fetchSpeechState());
  }

  void stopPollingSpeechState() {
    pollTimer?.cancel();
    pollTimer = null;
  }

  Future<void> fetchSpeechState() async {
    try {
      final res = await svc.fetchSpeechState();
      if (res is Map<String, dynamic>) {
        final active = res['active'] as bool? ?? false;
        final actor = res['actor_id']?.toString();
        final expiresRaw = res['expires_at'];
        final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw.toString()) : null;

        final nowUtc = DateTime.now().toUtc();
        final expired = expires != null ? nowUtc.isAfter(expires) : false;

        if (expired) {
          if (!mounted) return;
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
            waitingForServerConfirm = false;
            activeSpeechId = null;
            listenedToThisSpeech = false;
          });
          return;
        }

        if (waitingForServerConfirm) {
          if (active) {
            final life = await svc.getActiveLifeSpeech();
            int? speechId;
            DateTime? serverExpires;

            if (life is Map<String, dynamic>) {
              speechId = life['id'] is int ? life['id'] as int : int.tryParse(life['id']?.toString() ?? '');
              serverExpires =
                  life['expires_at'] != null ? DateTime.tryParse(life['expires_at'].toString()) : null;
            }

            final clientNextSlotUtc = nextYekaterinburg12or20Utc;
            DateTime applyExpires = serverExpires ?? clientNextSlotUtc;
            if (clientNextSlotUtc.isAfter(applyExpires)) applyExpires = clientNextSlotUtc;

            if (!mounted) return;
            setState(() {
              speechActive = true;
              speechActorId = actor;
              speechExpiresAt = applyExpires;
              waitingForServerConfirm = false;
              activeSpeechId = speechId;
            });

            await checkIfListened();
            return;
          } else {
            if (!mounted) return;
            setState(() {
              speechActive = false;
              speechActorId = null;
              speechExpiresAt = null;
              waitingForServerConfirm = false;
              activeSpeechId = null;
              listenedToThisSpeech = false;
            });
            return;
          }
        }

        if (!active) {
          if (!mounted) return;
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
            activeSpeechId = null;
            listenedToThisSpeech = false;
          });
          return;
        }

        int? speechId;
        DateTime? serverExpires;
        try {
          final life = await svc.getActiveLifeSpeech();
          if (life is Map<String, dynamic>) {
            speechId = life['id'] is int ? life['id'] as int : int.tryParse(life['id']?.toString() ?? '');
            serverExpires =
                life['expires_at'] != null ? DateTime.tryParse(life['expires_at'].toString()) : expires;
          }
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          speechActive = true;
          speechActorId = actor;
          speechExpiresAt = serverExpires ?? expires;
          activeSpeechId = speechId;
        });

        await checkIfListened();
      }
    } catch (_) {
      // ignore errors
    }
  }

  // ----------------------- Check if current user already listened to current active speech -----------------------
  Future<void> checkIfListened() async {
    final sid = activeSpeechId;
    if (sid == null) {
      if (!mounted) return;
      setState(() => listenedToThisSpeech = false);
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
      if (!mounted) return;
      setState(() => listenedToThisSpeech = listened);
    } catch (_) {
      // ignore
    }
  }

  // ----------------------- YEKT helpers -----------------------
  DateTime get nextYekaterinburg20Utc {
    final nowUtc = DateTime.now().toUtc();
    final nowYe = nowUtc.add(const Duration(hours: 5)); // YEKT UTC+5

    DateTime targetYe = DateTime(nowYe.year, nowYe.month, nowYe.day, 20, 0);
    if (!nowYe.isBefore(targetYe)) {
      final tomorrow = nowYe.add(const Duration(days: 1));
      targetYe = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0);
    }
    return targetYe.subtract(const Duration(hours: 5));
  }

  DateTime get nextYekaterinburg12or20Utc {
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

  int secondsUntilUtc(DateTime targetUtc) {
    final nowUtc = DateTime.now().toUtc();
    final diff = targetUtc.difference(nowUtc);
    final secs = diff.inSeconds;
    return secs > 0 ? secs : 0;
  }

  bool get isSpeechButtonEnabled {
    if (user.role != 'politician') return false;
    if (rpcLoading) return false;

    final nowUtc = DateTime.now().toUtc();
    if (speechExpiresAt != null) {
      if (nowUtc.isBefore(speechExpiresAt!)) return false;
    }

    if (speechActive) {
      if (speechExpiresAt != null) return nowUtc.isAfter(speechExpiresAt!);
      final next20 = nextYekaterinburg20Utc;
      return nowUtc.isAfter(next20);
    }

    if (waitingForServerConfirm) return false;
    return true;
  }

  // ----------------------- start speech -----------------------
  Future<void> onStartSpeechPressed() async {
    if (user.role != 'politician') return;
    if (!isSpeechButtonEnabled) return;

    final target20Utc = nextYekaterinburg20Utc;
    final secondsForRpc = secondsUntilUtc(target20Utc);
    if (secondsForRpc == 0) {
      showMessage('2000 YEKT');
      return;
    }

    final clientNextSlotUtc = nextYekaterinburg12or20Utc;

    if (!mounted) return;
    setState(() {
      rpcLoading = true;
      speechActive = true;
      speechActorId = user.id;
      speechExpiresAt = clientNextSlotUtc;
      waitingForServerConfirm = true;
    });

    DateTime? applyExpires = clientNextSlotUtc;

    try {
      final dynamic rpcRes = await svc.rpcStartSpeech(actorId: user.id, durationSeconds: secondsForRpc);

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
      }

      if (parsed != null) {
        final serverExpiresRaw = parsed['expires_at'];
        final serverExpires =
            serverExpiresRaw != null ? DateTime.tryParse(serverExpiresRaw.toString()) : null;

        DateTime chosen = serverExpires ?? clientNextSlotUtc;
        if (clientNextSlotUtc.isAfter(chosen)) chosen = clientNextSlotUtc;
        applyExpires = chosen;

        if (!mounted) return;
        setState(() {
          speechActive = parsed?['active'] as bool? ?? true;
          speechActorId = parsed?['actor_id']?.toString();
          speechExpiresAt = applyExpires;
          waitingForServerConfirm = false;
        });
      } else {
        await fetchSpeechState();
        if (!mounted) return;
        setState(() {
          if (speechExpiresAt == null || clientNextSlotUtc.isAfter(speechExpiresAt!)) {
            speechExpiresAt = clientNextSlotUtc;
          }
          waitingForServerConfirm = false;
        });
      }

      // Persist state into speech_state upsert id=1 (kept as in your original flow)
      try {
        final upsertObj = {
          'id': 1,
          'active': true,
          'actor_id': user.id,
          'expires_at': applyExpires!.toUtc().toIso8601String(),
        };
        await svc.upsertSpeechState(obj: upsertObj);
      } catch (_) {}

      showMessage('Речь запущена до ${formatYe(applyExpires)} (YEKT)');
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg.contains('Speech already active')) {
        await fetchSpeechState();
      } else {
        showMessage(msg);
      }
      if (!mounted) return;
      setState(() {
        speechActive = false;
        speechActorId = null;
        waitingForServerConfirm = false;
        speechExpiresAt = null;
      });
    } catch (e) {
      showMessage(e.toString());
      if (!mounted) return;
      setState(() {
        speechActive = false;
        speechActorId = null;
        waitingForServerConfirm = false;
        speechExpiresAt = null;
      });
    } finally {
      if (!mounted) return;
      setState(() => rpcLoading = false);
    }
  }

  String formatYe(DateTime? utc) {
    if (utc == null) return '';
    final ye = utc.toUtc().add(const Duration(hours: 5));
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(ye.day)}.${z(ye.month)} ${z(ye.hour)}:${z(ye.minute)}';
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------- Transfer navigation open transfer_v_screen and refresh profile on success -----------------------
  Future<void> openTransferScreen() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransferVScreen(user: user)),
    );
    if (res == true) await refreshProfile();
  }

  // ----------------------- Open resolution political betting dialog for politicians -----------------------
  Future<void> onOpenResolutionPressed() async {
    if (activeResolutionId == null) return;
    final resolutionId = activeResolutionId!;

    List<Map<String, dynamic>> options = [];
    try {
      final res = await supabase
          .from('resolution_options')
          .select('id,label')
          .eq('resolution_id', resolutionId)
          .order('id');

      if (res is List) options = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      showMessage(e.toString());
      return;
    }

    if (options.isEmpty) {
      showMessage('Нет вариантов для голосования.');
      return;
    }

    int? selectedOptionId;
    final TextEditingController amtCtrl = TextEditingController();

    final resDialogResult = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDialog) {
          return AlertDialog(
            title: const Text('Ставка'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Выберите вариант и сумму ставки.'),
                  const SizedBox(height: 8),
                  ...options.map((opt) {
                    final oid = opt['id'] is int ? opt['id'] as int : int.parse(opt['id'].toString());
                    return RadioListTile<int>(
                      value: oid,
                      groupValue: selectedOptionId,
                      onChanged: (v) => setStateDialog(() => selectedOptionId = v),
                      title: Text(opt['label'] ?? '-'),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Сумма (до ${user.mBalance.toStringAsFixed(2)} M)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  if (selectedOptionId == null) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Выберите вариант.')));
                    return;
                  }
                  final txt = amtCtrl.text.trim();
                  final n = int.tryParse(txt);
                  if (n == null || n <= 0) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Введите сумму.')));
                    return;
                  }
                  if (n > user.mBalance) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      SnackBar(content: Text('Недостаточно M. Доступно: ${user.mBalance.toStringAsFixed(2)}')),
                    );
                    return;
                  }
                  Navigator.of(ctx2).pop(true);
                },
                child: const Text('Поставить'),
              ),
            ],
          );
        },
      ),
    );

    if (resDialogResult != true) {
      try {
        amtCtrl.dispose();
      } catch (_) {}
      return;
    }

    // perform bet
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await svc.placeBetInResolution(
        resolutionId: resolutionId,
        optionId: selectedOptionId!,
        userId: user.id,
        amount: int.parse(amtCtrl.text.trim()),
      );

      await refreshProfile();
      await loadResolutionState();

      if (mounted) Navigator.of(context).pop(); // close progress dialog

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо!'),
          content: const Text('Ставка принята.'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );

      if (!mounted) return;
      setState(() => alreadyBetInActiveResolution = true);
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
      }
      final msg = e is PostgrestException ? (e.message) : e.toString();
      showMessage(msg);
    } finally {
      try {
        amtCtrl.dispose();
      } catch (_) {}
    }
  }

  // ----------------------- BUY ECONOMIST TURN FLOW new button client-side immediate inventory update -----------------------
  Future<void> openBuyTurnFlow() async {
    // kept as in your file (unchanged)
    List<Map<String, dynamic>> econs = [];
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, first_name, last_name, telegram_username')
          .eq('role', 'economist')
          .neq('id', user.id)
          .order('first_name');

      if (res is List) {
        econs = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      showMessage(e.toString());
      return;
    }

    if (econs.isEmpty) {
      showMessage('Нет экономистов.');
      return;
    }

    final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Поиск',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) {
                            // no-op (kept simple)
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Закрыть')),
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
                      final first = row['first_name']?.toString() ?? '';
                      final last = row['last_name']?.toString() ?? '';
                      final displayName =
                          ('$first $last').trim().isEmpty ? (row['telegram_username']?.toString() ?? '') : ('$first $last');
                      return ListTile(
                        title: Text(displayName),
                        onTap: () => Navigator.of(ctx).pop(row),
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

    final first = chosen['first_name']?.toString() ?? '';
    final last = chosen['last_name']?.toString() ?? '';
    final displayName =
        ('$first $last').trim().isEmpty ? (chosen['telegram_username']?.toString() ?? '') : ('$first $last');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покупка хода'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Стоимость: 10 V'),
            const SizedBox(height: 8),
            Text(displayName),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Купить')),
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
        fromUser: user.id,
        toUser: chosen['id']?.toString() ?? '',
        cost: 10,
      );

      Navigator.of(context).pop(); // close progress

      if (rpcRes == null) {
        showMessage('Ошибка RPC.');
        return;
      }

      final status = (rpcRes['status'] ?? rpcRes['result'] ?? '').toString().toLowerCase();
      if (status.contains('ok') || status.contains('success')) {
        showMessage('Успешно!');

        final item = <String, dynamic>{
          'owner_id': chosen['id']?.toString() ?? chosen['id'].toString(),
          'name': rpcRes['item_name'] ?? 'Ход экономиста',
          'count': 1,
          'metadata': rpcRes['item_meta'] ?? {'from': user.id, 'cost': 10},
          'created_at': rpcRes['created_at'] ?? DateTime.now().toIso8601String(),
        };

        if (!mounted) return;
        setState(() => pendingInventoryItems.insert(0, item));

        try {
          await refreshProfile();
        } catch (_) {}
      } else {
        final msg = rpcRes['message']?.toString() ?? rpcRes.toString();
        showMessage(msg);
      }
    } catch (e) {
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      showMessage(e.toString());
    }
  }

  // ----------------------- NEW Open Purchase Enterprise screen visible only to economists -----------------------
  Future<void> openPurchaseEnterprise() async {
    if (user.role != 'economist') return;
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseEnterpriseScreen(currentUser: user)),
    );
    if (res == true) {
      await refreshProfile();
      showMessage('Предприятие куплено.');
    }
  }

  // ----------------------- UI rendering -----------------------
  Widget renderSpeechButton() {
  if (user.role != 'politician') return const SizedBox.shrink();

  final enabled = isSpeechButtonEnabled;
  final actorLabel = (speechActorId == user.id) ? 'Вы' : (speechActorId ?? '');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ElevatedButton(
        onPressed: enabled ? onStartSpeechPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? Colors.orange : Colors.grey,
        ),
        child: Text(enabled ? 'Начать речь' : 'Недоступно'),
      ),
      if (speechActive && speechExpiresAt != null && DateTime.now().toUtc().isBefore(speechExpiresAt!))
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            actorLabel,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      if (speechExpiresAt != null && DateTime.now().toUtc().isBefore(speechExpiresAt!))
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            'До ${formatYe(speechExpiresAt)} YEKT.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
    ],
  );
}

  Widget renderListenWidget() {
    return ListenButton(
      userId: user.id,
      activeSpeechId: activeSpeechId,
      speechActorId: speechActorId,
      speechActive: speechActive,
      alreadyListened: listenedToThisSpeech,
      onListenComplete: (Map<String, dynamic>? rpcResult) async {
        if (rpcResult != null) {
          final status = rpcResult['status']?.toString() ?? '';
          if (status == 'changed_color') {
            final newColor = rpcResult['new_color']?.toString();
            final addedM = rpcResult['added_m'];
            if (newColor != null) {
              if (!mounted) return;
              setState(() {
                userColor = newColor;
                user = AppUser(
                  id: user.id,
                  username: user.username,
                  role: user.role,
                  firstName: user.firstName,
                  lastName: user.lastName,
                  vBalance: user.vBalance,
                  mBalance: addedM is num ? addedM.toDouble() : user.mBalance,
                  color: newColor,
                  region: user.region,
                );
              });
            }
          } else if (status == 'kept_color') {
            final addedV = rpcResult['added_v'];
            if (addedV is num) {
              if (!mounted) return;
              setState(() {
                user = AppUser(
                  id: user.id,
                  username: user.username,
                  role: user.role,
                  firstName: user.firstName,
                  lastName: user.lastName,
                  vBalance: addedV.toDouble(),
                  mBalance: user.mBalance,
                  color: user.color,
                  region: user.region,
                );
              });
            }
          }
        }

        try {
          await refreshProfile();
          await fetchSpeechState();
        } catch (_) {}

        if (!mounted) return;
        setState(() => listenedToThisSpeech = true);
      },
    );
  }

  Color? parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);

    if (hex.length == 6) {
      hex = 'FF$hex';
    } else if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF$r$r$g$g$b$b';
    } else if (hex.length == 8) {
      // AARRGGBB
    } else {
      return null;
    }

    final intVal = int.tryParse(hex, radix: 16);
    if (intVal == null) return null;
    return Color(intVal);
  }

  Widget get balanceCard {
    final parsedColor = parseHexColor(userColor);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${user.firstName} ${user.lastName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text(user.role),
              if (userColor != null && userColor!.isNotEmpty) const SizedBox(width: 12),
              if (parsedColor != null)
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: parsedColor,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
              if (parsedColor != null) const SizedBox(width: 6),
              if (userColor != null && userColor!.isNotEmpty)
                Text(userColor!, style: const TextStyle(color: Colors.black)),
            ]),
            const SizedBox(height: 4),
            if (user.role == 'economist' && user.region != null && user.region!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  user.region!,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              'V ${user.vBalance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('M ${user.mBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
          ]),
        ]),
      ),
    );
  }

  List<Widget> get roleButtons {
    final role = user.role;
    final List<Widget> buttons = [];

    void add(String title, VoidCallback onTap, {Color? color}) {
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: onTap,
              child: Text(title),
            ),
          ),
        ),
      );
    }

    add('Перевод V/M', openTransferScreen);
    add('Купить ход экономиста', openBuyTurnFlow);

    if (role == 'economist') {
      add('Купить предприятие (200 V)', openPurchaseEnterprise);
    }

    // Debates button only show if user is NOT politician, there is an active debate and user hasn't voted
    if (role != 'politician' && hasActiveDebate && !alreadyVotedInActiveDebate) {
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final res = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => DebatesScreen(currentUserId: user.id, service: svc)),
                );
                if (res == true) {
                  if (!mounted) return;
                  setState(() => alreadyVotedInActiveDebate = true);
                  await refreshProfile();
                  await loadDebateState();
                } else {
                  await loadDebateState();
                }
              },
              child: const Text('Голосование'),
            ),
          ),
        ),
      );
    }

    // Political resolution button only for politicians, only if there's an active resolution and user hasn't bet
    if (role == 'politician' && hasActiveResolution && !alreadyBetInActiveResolution) {
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onOpenResolutionPressed,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Политическая ставка'),
            ),
          ),
        ),
      );
    }

    // For politicians render start speech button
    if (role == 'politician') {
      buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: renderSpeechButton()));
    }

    // Listen widget visible to all
    buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: renderListenWidget()));

    return buttons;
  }

  void logout() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // ----------------------- Inventory navigation open inventory screen that also shows pending local additions -----------------------
  Future<void> openInventoryScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InventoryScreen(user: user)),
    );

    if (!mounted) return;
    setState(() {
      pendingInventoryItems.removeWhere((it) => it['owner_id']?.toString() == user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: unlockAudio, // WEB
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Titanic'),
          actions: [
            IconButton(
              tooltip: 'Инвентарь',
              icon: const Icon(Icons.inventory_2),
              onPressed: openInventoryScreen,
            ),
            IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              balanceCard,
              const SizedBox(height: 12),
              ...roleButtons,
              const SizedBox(height: 20),
              const Text(
                'События',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              userEvents.isEmpty
                  ? const Text('Пока нет событий.', style: TextStyle(color: Colors.grey))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: userEvents.length,
                      itemBuilder: (context, index) {
                        final e = userEvents[index];
                        final createdAt = e['created_at']?.toString();
                        final time = (createdAt != null && createdAt.length >= 16) ? createdAt.substring(11, 16) : '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(e['title'] ?? ''),
                            subtitle: Text(e['message'] ?? ''),
                            trailing: Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------- PurchaseEnterpriseScreen ---------------------------
// Form for economists to buy an enterprise cost 200 V. On success returns true to caller.

class PurchaseEnterpriseScreen extends StatefulWidget {
  final AppUser currentUser;

  const PurchaseEnterpriseScreen({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<PurchaseEnterpriseScreen> createState() => PurchaseEnterpriseScreenState();
}

class PurchaseEnterpriseScreenState extends State<PurchaseEnterpriseScreen> {
  final supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();
  final TextEditingController nameCtrl = TextEditingController();

  String? selectedColor; // hex string
  String? selectedRegion;
  String? otherRegionText;

  // investors entries
  List<InvestorRow> investors = [];

  // players list for choosing investors
  List<Map<String, dynamic>> players = [];

  // regions fixed list as requested
  final List<String> fixedRegions = [
    'Свердловская область',
    'Челябинская область',
    'Тюменская область',
    'Пермский край',
    'ХМАО',
    'ЯНАО',
  ];

  // color options mapping name->hex
  final Map<String, String> colorOptions = {
    'Красный': '#F44336',
    'Зелёный': '#4CAF50',
    'Синий': '#2196F3',
    'Розовый': '#E91E63',
    'Жёлтый': '#FFC107',
  };

  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    investors.add(InvestorRow()); // start with one investor row can be empty
    loadPlayers();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    for (final r in investors) {
      r.controllerAmount.dispose();
    }
    super.dispose();
  }

  Future<void> loadPlayers() async {
    try {
      final res = await supabase.from('user_credentials').select('id, telegram_username, first_name, last_name').order('first_name');
      if (res is List) {
        players = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() {});
    }
  }

  void addInvestorRow() {
    if (investors.length >= 10) return;
    setState(() => investors.add(InvestorRow()));
  }

  void removeInvestorRow(int idx) {
    if (idx < 0 || idx >= investors.length) return;
    setState(() => investors.removeAt(idx));
  }

  Future<void> onSubmit() async {
    if (!formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      error = null;
    });

    final name = nameCtrl.text.trim();
    final colorHex = selectedColor ?? '';
    final region = selectedRegion ?? widget.currentUser.region ?? '';

    // assemble investors log text only
    final List<Map<String, dynamic>> investorsLog = [];
    for (final row in investors) {
      final pid = row.selectedPlayerId;
      final amt = row.controllerAmount.text.trim();
      if (pid == null || pid.toString().isEmpty || amt.isEmpty) continue;

      final player = players.firstWhere((p) => p['id']?.toString() == pid, orElse: () => {});
      final playerName = player.isNotEmpty
          ? ((player['first_name']?.toString().trim().isEmpty ?? true)
              ? (player['telegram_username']?.toString() ?? '')
              : '${player['first_name'] ?? ''} ${player['last_name'] ?? ''}')
          : pid;

      investorsLog.add({'player_id': pid, 'player_name': playerName, 'minds': amt});
    }

    try {
      // refresh user profile to get current balance inventory
      final fresh = await supabase.from('user_credentials').select('v_balance, inventory').eq('id', widget.currentUser.id).maybeSingle();
      if (fresh is! Map<String, dynamic>) throw Exception('Не удалось загрузить профиль');

      final vbalRaw = fresh['v_balance'];
      final currentBalance =
          vbalRaw is num ? vbalRaw.toDouble() : (double.tryParse(vbalRaw?.toString() ?? '') ?? 0.0);

      if (currentBalance < 200.0) {
        setState(() => loading = false);
        showError('Нужно 200 V. Доступно: ${currentBalance.toStringAsFixed(2)}');
        return;
      }

      // normalize inventory to a list
      dynamic inv = fresh['inventory'];
      List<dynamic> invList = [];
      if (inv == null) {
        invList = [];
      } else if (inv is String) {
        try {
          final d = jsonDecode(inv);
          if (d is List) invList = List.from(d);
        } catch (_) {}
      } else if (inv is List) {
        invList = List.from(inv);
      } else if (inv is Map) {
        invList = [inv];
      }

      final enterpriseItem = <String, dynamic>{
        'name': name,
        'count': 0,
        'meta': {'color': colorHex, 'region': region, 'investors': investorsLog},
        'created_at': DateTime.now().toIso8601String(),
      };

      invList.add(enterpriseItem);

      final newBalance = currentBalance - 200.0;
      final updateObj = {'v_balance': newBalance, 'inventory': invList};

      final upd = await supabase.from('user_credentials').update(updateObj).eq('id', widget.currentUser.id).select().maybeSingle();
      if (upd == null) throw Exception('Ошибка обновления');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      showError(e.toString());
      setState(() => loading = false);
    }
  }

  void showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<String?> showPlayerPicker(int index) async {
    String query = '';
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        List<Map<String, dynamic>> filtered = List.from(players);

        return StatefulBuilder(
          builder: (ctx2, setStateSheet) {
            void doFilter(String q) {
              query = q;
              final ql = q.trim().toLowerCase();
              if (ql.isEmpty) {
                filtered = List.from(players);
              } else {
                filtered = players.where((p) {
                  final fn = (p['first_name'] ?? '').toString().toLowerCase();
                  final ln = (p['last_name'] ?? '').toString().toLowerCase();
                  final un = (p['telegram_username'] ?? '').toString().toLowerCase();
                  return fn.contains(ql) || ln.contains(ql) || un.contains(ql);
                }).toList();
              }
              setStateSheet(() {});
            }

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Поиск игрока',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: doFilter,
                      ),
                    ),
                    const Divider(height: 0),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length + 1,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (context, idx) {
                          if (idx == 0) {
                            return ListTile(
                              title: const Text('Не выбирать'),
                              onTap: () => Navigator.of(ctx).pop(null),
                            );
                          }
                          final p = filtered[idx - 1];
                          final id = p['id']?.toString();
                          final name = (p['first_name']?.toString().trim().isEmpty ?? true)
                              ? (p['telegram_username']?.toString() ?? '')
                              : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}';
                          return ListTile(
                            title: Text(name),
                            onTap: () => Navigator.of(ctx).pop(id),
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
      },
    );
  }

  List<Widget> buildInvestorRows() {
    final List<Widget> rows = [];
    for (var i = 0; i < investors.length; i++) {
      final r = investors[i];

      String? selectedName;
      if (r.selectedPlayerId != null) {
        final p = players.firstWhere((p) => p['id']?.toString() == r.selectedPlayerId, orElse: () => {});
        if (p.isNotEmpty) {
          selectedName = (p['first_name']?.toString().trim().isEmpty ?? true)
              ? (p['telegram_username']?.toString() ?? '')
              : '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}';
        }
      }

      rows.add(
        Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final selected = await showPlayerPicker(i);
                          setState(() => r.selectedPlayerId = selected);
                        },
                        child: AbsorbPointer(
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Инвестор',
                              hintText: 'Выбрать игрока',
                              suffixIcon: Icon(Icons.search),
                            ),
                            controller: TextEditingController(text: selectedName ?? ''),
                            readOnly: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: r.controllerAmount,
                        decoration: const InputDecoration(labelText: 'Minds'),
                        keyboardType: TextInputType.text,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => removeInvestorRow(i),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Покупка предприятия')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Название предприятия'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                    ),
                    const SizedBox(height: 12),

                    // Color selection
                    Row(
                      children: [
                        const Text('Цвет:'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedColor,
                            items: colorOptions.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.value,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 18,
                                          height: 18,
                                          color: Color(int.parse(e.value.substring(1), radix: 16) + 0xFF000000),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(e.key),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => selectedColor = v),
                            decoration: const InputDecoration(hintText: 'Выберите цвет'),
                            validator: (v) => (v == null || v.isEmpty) ? 'Выберите цвет' : null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Region selection fixed dropdown
                    Row(
                      children: [
                        const Text('Регион:'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedRegion ?? widget.currentUser.region,
                            items: fixedRegions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                            onChanged: (v) => setState(() => selectedRegion = v),
                            decoration: const InputDecoration(hintText: 'Выберите регион'),
                            validator: (v) => (v == null || v.isEmpty) ? 'Выберите регион' : null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Investors block
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Инвесторы (до 10)', style: TextStyle(fontWeight: FontWeight.w600)),
                        TextButton(onPressed: investors.length >= 10 ? null : addInvestorRow, child: const Text('Добавить')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...buildInvestorRows(),
                    const SizedBox(height: 20),

                    ElevatedButton(onPressed: onSubmit, child: const Text('Купить за 200 V')),
                    const SizedBox(height: 12),

                    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
    );
  }
}

class InvestorRow {
  String? selectedPlayerId;
  final TextEditingController controllerAmount = TextEditingController();

  InvestorRow({this.selectedPlayerId});
}
