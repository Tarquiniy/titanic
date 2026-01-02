// lib/home_screen.dart
import 'dart:async';
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

  // Speech state
  bool speechActive = false;
  String? speechActorId;
  DateTime? speechExpiresAt;

  // Polling timer
  Timer? _pollTimer;

  // local loading flag for RPC calls
  bool _rpcLoading = false;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _fetchSpeechState(); // initial fetch
    _startPollingSpeechState(); // start periodic poll (fallback to realtime)
  }

  @override
  void dispose() {
    _stopPollingSpeechState();
    super.dispose();
  }

  // Start polling every N seconds
  void _startPollingSpeechState({int seconds = 3}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => _fetchSpeechState());
  }

  void _stopPollingSpeechState() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // Fetch current speech state from DB
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
        final expires = res['expires_at'] != null ? DateTime.tryParse(res['expires_at'].toString()) : null;

        // If expires_at passed, optionally auto-stop on client (server should also clean up)
        if (active && expires != null && DateTime.now().isAfter(expires)) {
          // Try to stop on server (best-effort)
          try {
            await supabase.rpc('stop_speech', params: {'p_actor': actor});
          } catch (_) {
            // ignore
          }
          setState(() {
            speechActive = false;
            speechActorId = null;
            speechExpiresAt = null;
          });
          return;
        }

        setState(() {
          speechActive = active;
          speechActorId = actor;
          speechExpiresAt = expires;
        });
      } else {
        // no row — treat as inactive
        setState(() {
          speechActive = false;
          speechActorId = null;
          speechExpiresAt = null;
        });
      }
    } catch (e) {
      // ignore polling errors silently (could log)
    }
  }

  // Пользователь нажал кнопку "Речь жизни"
  Future<void> _onStartSpeechPressed() async {
    if (user.role != 'politician') return;
    if (speechActive) return;

    const durationSeconds = 3600; // 1 hour, configurable

    setState(() => _rpcLoading = true);
    try {
      await supabase.rpc('start_speech', params: {'p_actor': user.id, 'p_duration_seconds': durationSeconds});

      // update local state immediately for snappy UX — server will reflect in poll shortly
      setState(() {
        speechActive = true;
        speechActorId = user.id;
        speechExpiresAt = DateTime.now().add(Duration(seconds: durationSeconds));
      });
    } on PostgrestException catch (e) {
      _showMessage(e.message ?? e.toString());
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      setState(() => _rpcLoading = false);
    }
  }

  // Пользователь (инициатор) может остановить свою речь
  Future<void> _onStopSpeechPressed() async {
    if (!speechActive) return;
    if (speechActorId != user.id) {
      _showMessage('Только инициатор может остановить речь');
      return;
    }

    setState(() => _rpcLoading = true);
    try {
      await supabase.rpc('stop_speech', params: {'p_actor': user.id});
      setState(() {
        speechActive = false;
        speechActorId = null;
        speechExpiresAt = null;
      });
    } on PostgrestException catch (e) {
      _showMessage(e.message ?? e.toString());
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

  // UI helper: renders the speech button and related info for politicians
  Widget _renderSpeechButton() {
    if (user.role != 'politician') return const SizedBox.shrink();

    final enabled = !speechActive && !_rpcLoading;
    final actorLabel = speechActorId == user.id ? 'Вы' : (speechActorId ?? '—');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: enabled ? _onStartSpeechPressed : null,
          style: ElevatedButton.styleFrom(backgroundColor: enabled ? Colors.orange : Colors.grey),
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
        if (speechActive && speechActorId == user.id)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: ElevatedButton(
              onPressed: _rpcLoading ? null : _onStopSpeechPressed,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: _rpcLoading ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Остановить речь'),
            ),
          ),
      ],
    );
  }

  // Balance card and role buttons
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
