// lib/screens/home_screen.dart
//
// Главное окно — навигация на transfer_v_screen и логика "Речь жизни".
// Подключаем ListenDialog и используем публичный ListenDialogResult.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/models/app_user.dart';
import 'package:titanic/services/game_service.dart';
import 'login_screen.dart';
import 'transfer_v_screen.dart';
import 'inventory_screen.dart';
import 'package:titanic/widgets/listen_dialog.dart';

class HomeScreen extends StatefulWidget {
  final AppUser user;
  const HomeScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppUser user;
  final supabase = Supabase.instance.client;
  final GameService svc = GameService();

  // Speech state
  bool speechActive = false;
  String? speechActorId;
  DateTime? speechExpiresAt; // UTC - client lock/unlock time

  // Active life_speech record id (needed for listen RPC)
  int? _activeSpeechId;

  // Поле цвета пользователя (из колонки color в user_credentials)
  String? _userColor;

  // Polling
  Timer? _pollTimer;

  // RPC/loading flags
  bool _rpcLoading = false;

  // Waiting for server confirm after start_speech
  bool _waitingForServerConfirm = false;

  // Listen state: whether current user already listened to this active speech
  bool _listenedToThisSpeech = false;

  // Session-level flag: "Нажимал кнопку 'Прослушал речь жизни' в этой сессии" (in-memory)
  bool _sessionListened = false;

  // while checking or performing listen RPC
  bool _checkingListen = false;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _fetchSpeechState();
    _startPollingSpeechState();
    // Подтянем профиль (включая color) при инициализации
    _refreshProfile();
  }

  @override
  void dispose() {
    _stopPollingSpeechState();
    super.dispose();
  }

  // -----------------------
  // Profile / balance refresh (now also loads `color`)
  // -----------------------
  Future<void> _refreshProfile() async {
    try {
      final profile = await supabase
          .from('user_credentials')
          .select('v_balance, m_balance, first_name, last_name, telegram_username, role, color')
          .eq('id', user.id)
          .maybeSingle();

      if (profile is Map<String, dynamic>) {
        final v = profile['v_balance'];
        final m = profile['m_balance'];
        final fn = profile['first_name'];
        final ln = profile['last_name'];
        final uname = profile['telegram_username'];
        final role = profile['role'];
        final color = profile['color'];

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
          );
          _userColor = color is String ? color : null;
        });
      }
    } catch (_) {
      // ignore refresh errors
    }
  }

  // -----------------------
  // Polling speech_state
  // -----------------------
  void _startPollingSpeechState({int seconds = 3}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => _fetchSpeechState());
  }

  void _stopPollingSpeechState() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchSpeechState() async {
    try {
      final res = await svc.fetchSpeechState();

      if (res is Map<String, dynamic>) {
        final active = (res['active'] as bool?) ?? false;
        final actor = res['actor_id']?.toString();
        final expiresRaw = res['expires_at'];
        final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw.toString()) : null;

        final nowUtc = DateTime.now().toUtc();

        // Если сервер сообщает, что expired (expires в прошлом) -> считаем неактивным
        if (expires != null && nowUtc.isAfter(expires)) {
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null; // сбрасываем локальный lock
            _waitingForServerConfirm = false;
            _activeSpeechId = null;
            _listenedToThisSpeech = false;
          });
          return;
        }

        // Если мы ожидаем подтверждение от сервера — обрабатываем отдельной логикой
        if (_waitingForServerConfirm) {
          if (active) {
            final life = await svc.getActiveLifeSpeech();
            int? speechId;
            DateTime? serverExpires;
            if (life is Map<String, dynamic>) {
              speechId = (life['id'] is int) ? (life['id'] as int) : int.tryParse(life['id']?.toString() ?? '');
              serverExpires = life['expires_at'] != null ? DateTime.tryParse(life['expires_at'].toString()) : null;
            }

            final clientNextSlotUtc = _nextYekaterinburg12or20Utc();
            DateTime applyExpires = serverExpires ?? clientNextSlotUtc;
            if (clientNextSlotUtc.isAfter(applyExpires)) applyExpires = clientNextSlotUtc;

            setState(() {
              speechActive = true;
              speechActorId = actor;
              speechExpiresAt = applyExpires;
              _waitingForServerConfirm = false;
              _activeSpeechId = speechId;
            });

            await _checkIfListened();
            return;
          } else {
            setState(() {
              speechActive = false;
              speechActorId = null;
              speechExpiresAt = null;
              _waitingForServerConfirm = false;
              _activeSpeechId = null;
              _listenedToThisSpeech = false;
            });
            return;
          }
        }

        // Обычная ветка: если сервер говорит inactive — сбрасываем локальный lock
        if (!active) {
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null; // **важно** — доверяем серверу и включаем кнопку
            _activeSpeechId = null;
            _listenedToThisSpeech = false;
          });
          return;
        }

        // Если сервер сообщает active = true — применяем значения сервера
        int? speechId;
        DateTime? serverExpires;
        try {
          final life = await svc.getActiveLifeSpeech();

          if (life is Map<String, dynamic>) {
            speechId = (life['id'] is int) ? (life['id'] as int) : int.tryParse(life['id']?.toString() ?? '');
            serverExpires = life['expires_at'] != null ? DateTime.tryParse(life['expires_at'].toString()) : expires;
          }
        } catch (_) {
          // ignore
        }

        setState(() {
          speechActive = true;
          speechActorId = actor;
          speechExpiresAt = serverExpires ?? expires;
          _activeSpeechId = speechId;
        });

        await _checkIfListened();
      } else {
        // ничего нет — считаем inactive и сбрасываем локально
        if (!_waitingForServerConfirm) {
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
            _activeSpeechId = null;
            _listenedToThisSpeech = false;
          });
        }
      }
    } catch (_) {
      // ignore errors — оставляем текущее состояние
    }
  }

  // -----------------------
  // Check if current user already listened to current active speech
  // -----------------------
  Future<void> _checkIfListened() async {
    final sid = _activeSpeechId;
    if (sid == null) {
      setState(() => _listenedToThisSpeech = false);
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
      setState(() {
        _listenedToThisSpeech = res != null;
      });
    } catch (_) {
      // ignore
    }
  }

  // -----------------------
  // YEKT helpers
  // -----------------------
  DateTime _nextYekaterinburg20Utc() {
    final nowUtc = DateTime.now().toUtc();
    final nowYe = nowUtc.add(const Duration(hours: 5)); // YEKT = UTC+5
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

  bool get _isSpeechButtonEnabled {
    if (user.role != 'politician') return false;
    if (_rpcLoading) return false;

    final nowUtc = DateTime.now().toUtc();

    // Если есть локальный expiry — блокируем до этого времени
    if (speechExpiresAt != null) {
      if (nowUtc.isBefore(speechExpiresAt!)) return false;
    }

    // Если сервер сообщает активность (speechActive == true) и её expiry в будущем — блокируем
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

  // -----------------------
  // start_speech
  // -----------------------
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

    setState(() {
      _rpcLoading = true;
      speechActive = true;
      speechActorId = user.id;
      speechExpiresAt = clientNextSlotUtc; // временная локальная блокировка
      _waitingForServerConfirm = true;
    });

    DateTime? applyExpires = clientNextSlotUtc;

    try {
      // Вызов серверного RPC (если есть)
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
      } else {
        parsed = null;
      }

      if (parsed != null) {
        final serverExpiresRaw = parsed['expires_at'];
        final serverExpires = serverExpiresRaw != null ? DateTime.tryParse(serverExpiresRaw.toString()) : null;
        DateTime chosen = serverExpires ?? clientNextSlotUtc;
        if (clientNextSlotUtc.isAfter(chosen)) chosen = clientNextSlotUtc;
        applyExpires = chosen;

        setState(() {
          speechActive = parsed?['active'] as bool? ?? true;
          speechActorId = parsed?['actor_id']?.toString();
          speechExpiresAt = applyExpires;
          _waitingForServerConfirm = false;
        });
      } else {
        // RPC ничего не вернул — продолжаем и сохраняем в таблицу speech_state (upsert)
        await _fetchSpeechState();
        setState(() {
          if (speechExpiresAt == null || clientNextSlotUtc.isAfter(speechExpiresAt!)) {
            speechExpiresAt = clientNextSlotUtc;
          }
          _waitingForServerConfirm = false;
        });
      }

      // Persist state into speech_state (upsert id = 1)
      try {
        final upsertObj = {
          'id': 1,
          'active': true,
          'actor_id': user.id,
          'expires_at': applyExpires!.toUtc().toIso8601String(),
        };
        await svc.upsertSpeechState(obj: upsertObj);
      } catch (e) {
        _showMessage('Не удалось сохранить состояние речи на сервере (права). Кнопка всё равно будет локально заблокирована.');
      }

      _showMessage('Речь запущена. Кнопка будет недоступна до ${_formatYe(applyExpires)} (YEKT)');
    } on PostgrestException catch (e) {
      final msg = e.message;
      if (msg != null && msg.contains('Speech already active')) {
        await _fetchSpeechState();
      } else {
        _showMessage(msg ?? e.toString());
        setState(() {
          speechActive = false;
          speechActorId = null;
          _waitingForServerConfirm = false;
          speechExpiresAt = null;
        });
      }
    } catch (e) {
      _showMessage(e.toString());
      setState(() {
        speechActive = false;
        speechActorId = null;
        _waitingForServerConfirm = false;
        speechExpiresAt = null;
      });
    } finally {
      setState(() => _rpcLoading = false);
    }
  }

  String _formatYe(DateTime utc) {
    final ye = utc.toUtc().add(const Duration(hours: 5));
    String z(int n) => n.toString().padLeft(2, '0');
    return '${z(ye.day)}.${z(ye.month)} ${z(ye.hour)}:${z(ye.minute)}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // -----------------------
  // Listen speech: UI + RPC
  // -----------------------
  bool get _isListenButtonEnabled {
    if (_checkingListen) return false;
    if (_sessionListened) return false;
    if (_listenedToThisSpeech) return false;
    if (_activeSpeechId == null) return false;
    if (speechExpiresAt != null && DateTime.now().toUtc().isAfter(speechExpiresAt!)) return false;
    return true;
  }

  Future<void> _onListenPressed() async {
    if (!_isListenButtonEnabled) return;
    final sid = _activeSpeechId;
    if (sid == null) {
      _showMessage('Нет активной речи.');
      return;
    }

    final result = await showDialog<ListenDialogResult>(
      context: context,
      builder: (_) => const ListenDialog(defaultN: 1),
    );

    if (result == null) return;

    setState(() {
      _checkingListen = true;
    });

    try {
      final res = await svc.rpcListenSpeech(speechId: sid, userId: user.id, agree: result.agree, n: result.n);

      Map<String, dynamic>? parsed;
      if (res is Map<String, dynamic>) parsed = res;
      else if (res is List && res.isNotEmpty && res[0] is Map) parsed = Map<String, dynamic>.from(res[0] as Map);
      else if (res is String) {
        try {
          parsed = Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          parsed = null;
        }
      }

      String message = 'Спасибо за прослушивание.';
      if (parsed != null) {
        final status = parsed['status']?.toString() ?? '';
        if (status == 'changed_color') {
          final newColor = parsed['new_color']?.toString() ?? '';
          final addedM = parsed['added_m']?.toString() ?? '';
          message = 'Ваш цвет изменён на $newColor. В банк цвета добавлено $addedM майндов.';
        } else if (status == 'kept_color') {
          final addedV = parsed['added_v']?.toString() ?? '';
          message = 'Спасибо, вы остались верны своему цвету. Вам добавлено $addedV войсов.';
        } else {
          message = parsed.toString();
        }
      }

      setState(() {
        _sessionListened = true;
        _listenedToThisSpeech = true;
      });

      await _refreshProfile();
      await _fetchSpeechState();

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Спасибо за участие в речи'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК'))],
        ),
      );
    } on PostgrestException catch (e) {
      _showMessage(e.message ?? e.toString());
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      setState(() {
        _checkingListen = false;
      });
    }
  }

  // -----------------------
  // Transfer navigation: open transfer_v_screen and refresh profile on success
  // -----------------------
  Future<void> _openTransferScreen() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransferVScreen(user: user)),
    );

    // If returned true — refresh profile (balances)
    if (res == true) {
      await _refreshProfile();
    }
  }

  // -----------------------
  // UI rendering
  // -----------------------
  Widget _renderSpeechButton() {
    if (user.role != 'politician') return const SizedBox.shrink();

    final enabled = _isSpeechButtonEnabled;
    final actorLabel = speechActorId == user.id ? 'Вы' : (speechActorId ?? '—');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: enabled ? _onStartSpeechPressed : null,
          style: ElevatedButton.styleFrom(backgroundColor: enabled ? Colors.orange : Colors.grey),
          child: Text(enabled ? 'Речь жизни (старт)' : 'Речь жизни (неактивна)'),
        ),
        if (speechActive || (speechExpiresAt != null && DateTime.now().toUtc().isBefore(speechExpiresAt!)))
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              speechActorId == user.id ? 'Вы инициировали речь' : 'Речь активна (инициатор: $actorLabel)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (speechExpiresAt != null && DateTime.now().toUtc().isBefore(speechExpiresAt!))
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              'Кнопка снова станет доступна в ${_formatYe(speechExpiresAt!)} (YEKT).',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _renderListenButton() {
    final enabled = _isListenButtonEnabled;
    final label = _sessionListened || _listenedToThisSpeech ? 'Уже прослушал' : 'Прослушал речь жизни';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: enabled ? _onListenPressed : null,
          style: ElevatedButton.styleFrom(backgroundColor: enabled ? Colors.blueAccent : Colors.grey),
          child: _checkingListen ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
        ),
        if (_sessionListened) Padding(padding: const EdgeInsets.only(top: 6.0), child: Text('Нажималось в этой сессии', style: const TextStyle(fontSize: 12, color: Colors.grey))),
        if (_listenedToThisSpeech && !_sessionListened) Padding(padding: const EdgeInsets.only(top: 6.0), child: Text('Вы уже прослушали текущую речь', style: const TextStyle(fontSize: 12, color: Colors.grey))),
      ],
    );
  }

  Color? _parseHexColor(String? s) {
    if (s == null) return null;
    final str = s.trim();
    if (!str.startsWith('#')) return null;
    String hex = str.substring(1);
    if (hex.length == 6) {
      hex = 'FF' + hex; // add alpha
    } else if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF' + r + r + g + g + b + b;
    } else if (hex.length == 8) {
      // assume AARRGGBB
    } else {
      return null;
    }
    final intVal = int.tryParse(hex, radix: 16);
    if (intVal == null) return null;
    return Color(intVal);
  }

  Widget _balanceCard() {
    final parsedColor = _parseHexColor(_userColor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${user.firstName} ${user.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Роль: ${user.role}'),
                if (_userColor != null && _userColor!.isNotEmpty) const SizedBox(width: 12),
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
                if (_userColor != null && _userColor!.isNotEmpty)
                  Text('Цвет: ${_userColor}', style: const TextStyle(color: Colors.black)),
              ],
            ),
            const SizedBox(height: 4),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('V: ${user.vBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('M: ${user.mBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
          ]),
        ]), 
      ),
    );
  }

  List<Widget> _roleButtons() {
    final role = user.role;
    final List<Widget> buttons = [];

    void add(String title, VoidCallback onTap, {Color? color}) {
      buttons.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color),
            onPressed: onTap,
            child: Text(title),
          ),
        ),
      ));
    }

    add('Перевести V/M', () => _openTransferScreen());

    add('Опросы / Аукционы', () {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Открыть: Опросы/Аукционы')));
    });

    // For politicians render start speech button
    if (role == 'politician') {
      buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: _renderSpeechButton()));
    }

    // Listen button visible to all
    buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: _renderListenButton()));

    if (role == 'economist') {
      add('Аналитика / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аналитика'))));
    }

    if (role == 'hollywood') {
      add('Контент / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hollywood'))));
    }

    if (role == 'mafia') {
      add('Управление предприятиями', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятия'))));
    }

    if (role == 'journalist') {
      add('Дебаты / Публикации', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты'))));
    }

    if (role == 'public_figure') {
      add('События / Прослушал', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('События'))));
    }

    if (role == 'admin') {
      add('Админ-панель', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Админ-панель'))), color: Colors.black87);
      add('Пополнить V/M', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пополнение'))));
      add('Создать опрос', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создать опрос'))));
      add('Создать аукцион', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создание аукциона'))));
      add('Статистика цветов', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Статистика'))));
    }

    return buttons;
  }

  void _logout() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            tooltip: 'Инвентарь',
            icon: const Icon(Icons.inventory_2),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => InventoryScreen(user: user)),
              );
            },
          ),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _balanceCard(),
            const SizedBox(height: 12),
            ..._roleButtons(),
          ],
        ),
      ),
    );
  }
}
