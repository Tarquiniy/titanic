// lib/home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/app_user.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppUser user;
  const HomeScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppUser user;
  final supabase = Supabase.instance.client;

  // Состояние речи (серверный флаг)
  bool speechActive = false;
  String? speechActorId;
  DateTime? speechExpiresAt; // в UTC

  // Пуллинг для обновления состояния speech_state
  Timer? _pollTimer;

  // RPC loading
  bool _rpcLoading = false;

  // NEW: ожидаем подтверждения от сервера после RPC старта (чтобы не перезаписать локальный флаг старым poll)
  bool _waitingForServerConfirm = false;
  // Опционально: время, до которого ожидаем подтверждения (защита от вечного ожидания)
  DateTime? _waitingTimeoutUtc;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _fetchSpeechState();
    _startPollingSpeechState();
  }

  @override
  void dispose() {
    _stopPollingSpeechState();
    super.dispose();
  }

  void _startPollingSpeechState({int seconds = 3}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => _fetchSpeechState());
  }

  void _stopPollingSpeechState() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // Получить состояние с сервера и актуализировать локальный флаг.
  Future<void> _fetchSpeechState() async {
    try {
      final res = await supabase
          .from('speech_state')
          .select('active, actor_id, expires_at')
          .eq('id', 1)
          .maybeSingle();

      if (res is Map<String, dynamic>) {
        final active = (res['active'] as bool?) ?? false;
        final actor = res['actor_id']?.toString();
        final expiresRaw = res['expires_at'];
        final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw.toString()) : null;

        final nowUtc = DateTime.now().toUtc();

        // Если есть expires_at и оно в прошлом — считаем неактивным
        if (expires != null && nowUtc.isAfter(expires)) {
          // Очистка состояний
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
            _waitingForServerConfirm = false;
            _waitingTimeoutUtc = null;
          });
          return;
        }

        // NEW: если мы ожидаем подтверждения от сервера, не позволяем poll перезаписать локальный флаг в false,
        // пока сервер не покажет active == true или не закончится timeout.
        if (_waitingForServerConfirm) {
          // если сервер уже вернул active == true => подтверждаем и отключаем ожидание
          if (active) {
            setState(() {
              speechActive = true;
              speechActorId = actor;
              speechExpiresAt = expires;
              _waitingForServerConfirm = false;
              _waitingTimeoutUtc = null;
            });
            return;
          } else {
            // сервер пока ещё не установил active; если вышел timeout, снимем ожидание и применим текущее состояние сервера
            if (_waitingTimeoutUtc != null && nowUtc.isAfter(_waitingTimeoutUtc!)) {
              setState(() {
                speechActive = active;
                speechActorId = actor;
                speechExpiresAt = expires;
                _waitingForServerConfirm = false;
                _waitingTimeoutUtc = null;
              });
              return;
            }
            // Иначе — игнорируем этот poll (оставляем локальный speechActive без изменений)
            return;
          }
        }

        // Обычное поведение (когда мы не ожидаем подтверждения)
        setState(() {
          speechActive = active;
          speechActorId = actor;
          speechExpiresAt = expires;
        });
      } else {
        // Если строки нет — считаем неактивным
        if (!_waitingForServerConfirm) {
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
          });
        }
      }
    } catch (e) {
      // Игнорируем ошибки пуллинга (можно логировать)
    }
  }

  // Вычисляет следующий момент 20:00 по YEKT (UTC+5) в UTC.
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

  // Возвращает количество секунд от nowUtc до targetUtc (>=1)
  int _secondsUntilUtc(DateTime targetUtc) {
    final nowUtc = DateTime.now().toUtc();
    final diff = targetUtc.difference(nowUtc);
    final secs = diff.inSeconds;
    return secs > 0 ? secs : 0;
  }

  // Доступность кнопки "Речь жизни" для текущего пользователя.
  bool get _isSpeechButtonEnabled {
    if (user.role != 'politician') return false;
    if (_rpcLoading) return false;

    // Если мы локально считаем, что речь активна — кнопка неактивна (пока не истечёт expires)
    if (speechActive) {
      final nowUtc = DateTime.now().toUtc();
      if (speechExpiresAt != null) {
        return nowUtc.isAfter(speechExpiresAt!);
      } else {
        // без expires: используем next 20:00 rule
        final next20Utc = _nextYekaterinburg20Utc();
        return nowUtc.isAfter(next20Utc);
      }
    }

    // Если speech не активен и мы ожидаем подтверждение (например, только что нажали) — не позволяем нажать снова
    if (_waitingForServerConfirm) return false;

    return true;
  }

  // Нажатие "Речь жизни": вычисляем секунды до следующего YEKT 20:00 и передаём в RPC.
  Future<void> _onStartSpeechPressed() async {
  if (user.role != 'politician') return;
  if (!_isSpeechButtonEnabled) return;

  // вычисляем секунды до следующего 20:00 YEKT (как у вас ранее)
  final target20Utc = _nextYekaterinburg20Utc(); // ваш helper
  final seconds = _secondsUntilUtc(target20Utc);
  if (seconds <= 0) {
    _showMessage('Невозможно вычислить время до 20:00 YEKT');
    return;
  }

  setState(() {
    _rpcLoading = true;
  });

  try {
    final dynamic rpcRes = await supabase.rpc('start_speech', params: {
      'p_actor': user.id,
      'p_duration_seconds': seconds,
    });

    // Парсим ответ — ожидаем Map с полями active, actor_id, expires_at
    Map<String, dynamic>? parsed;
    if (rpcRes is Map<String, dynamic>) {
      parsed = rpcRes;
    } else if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
      parsed = Map<String, dynamic>.from(rpcRes[0] as Map);
    } else if (rpcRes is String) {
      // Иногда PostgREST возвращает строку JSON
      try {
        parsed = Map<String, dynamic>.from(jsonDecode(rpcRes) as Map);
      } catch (_) {
        parsed = null;
      }
    } else {
      parsed = null;
    }

    if (parsed != null) {
      final active = parsed['active'] as bool? ?? true;
      final actor = parsed['actor_id']?.toString();
      final expiresRaw = parsed['expires_at'];
      final expires = expiresRaw != null ? DateTime.tryParse(expiresRaw.toString()) : target20Utc;

      setState(() {
        speechActive = active;
        speechActorId = actor;
        speechExpiresAt = expires;
        _waitingForServerConfirm = false;
        _waitingTimeoutUtc = null;
      });
    } else {
      // Fallback: сделаем immédiate fetch состояния с сервера
      await _fetchSpeechState();
    }

    _showMessage('Речь запущена до 20:00 YEKT');
  } on PostgrestException catch (e) {
    final msg = e.message ?? e.toString();
    _showMessage(msg);
    // Если ошибка "Speech already active", подтянем актуальное состояние
    if (msg.contains('Speech already active')) {
      await _fetchSpeechState();
    }
  } catch (e) {
    _showMessage(e.toString());
  } finally {
    setState(() => _rpcLoading = false);
  }
}

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _renderSpeechButton() {
    if (user.role != 'politician') return const SizedBox.shrink();

    final enabled = _isSpeechButtonEnabled;
    final actorLabel = speechActorId == user.id ? 'Вы' : (speechActorId ?? '—');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: enabled ? _onStartSpeechPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? Colors.orange : Colors.grey,
          ),
          child: Text(enabled ? 'Речь жизни (старт)' : 'Речь жизни (неактивна)'),
        ),
        if (speechActive)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              speechActorId == user.id ? 'Вы инициировали речь' : 'Речь активна (инициатор: $actorLabel)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (speechActive)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Text(
              'Кнопка снова станет доступна в 20:00 по времени Екатеринбурга.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _balanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${user.firstName} ${user.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Роль: ${user.role}'),
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

    add('Перевести V/M', () {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Открыть: Перевести')));
    });

    add('Опросы / Аукционы', () {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Открыть: Опросы/Аукционы')));
    });

    if (role == 'politician') {
      buttons.add(_renderSpeechButton());
    }

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
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
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
