// lib/speech_widgets.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpeechService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getActiveSpeech() async {
    try {
      final res = await supabase
          .from('life_speeches')
          .select('id, politician_id, started_at, expires_at')
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> startSpeech({
    required String actorId,
    required int durationSeconds,
  }) async {
    try {
      final res = await supabase.rpc('start_speech', params: {
        'p_actor': actorId,
        'p_duration_seconds': durationSeconds,
      });
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> listenSpeech({
    required int speechId,
    required String userId,
    required bool agree,
    required num n,
  }) async {
    try {
      final res = await supabase.rpc('listen_speech', params: {
        'p_speech_id': speechId,
        'p_user': userId,
        'p_agree': agree,
        'p_n': n,
      });
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final row = await supabase
          .from('user_credentials')
          .select('id, telegram_username, first_name, last_name, role, v_balance, m_balance, color')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      rethrow;
    }
  }
}

class PoliticianStartSpeechWidget extends StatefulWidget {
  final String currentUserId;
  final VoidCallback? onSpeechStarted;
  const PoliticianStartSpeechWidget({required this.currentUserId, this.onSpeechStarted, Key? key}) : super(key: key);

  @override
  State<PoliticianStartSpeechWidget> createState() => _PoliticianStartSpeechWidgetState();
}

class _PoliticianStartSpeechWidgetState extends State<PoliticianStartSpeechWidget> {
  final _durationController = TextEditingController(text: '3600');
  final _service = SpeechService();
  bool _loading = false;

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _startSpeech() async {
    final raw = _durationController.text.trim();
    final secs = int.tryParse(raw);
    if (secs == null || secs <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите корректную длительность в секундах (>0)')));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _service.startSpeech(actorId: widget.currentUserId, durationSeconds: secs);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Речь запущена, expires_at: ${res['expires_at'] ?? res['expires']}')));
      widget.onSpeechStarted?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось запустить речь: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Речь жизни (политикам)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Длительность (секунды)', hintText: '3600 = 1 час'),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _loading ? null : _startSpeech,
              child: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Запустить'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class ListenSpeechWidget extends StatefulWidget {
  final String currentUserId;
  const ListenSpeechWidget({required this.currentUserId, Key? key}) : super(key: key);

  @override
  State<ListenSpeechWidget> createState() => _ListenSpeechWidgetState();
}

class _ListenSpeechWidgetState extends State<ListenSpeechWidget> {
  final _service = SpeechService();
  Map<String, dynamic>? _activeSpeech;
  bool _loading = false;
  bool _sessionPressed = false;
  Map<String, dynamic>? _profile;
  bool _checkingListened = false;
  bool _hasListenedToCurrentSpeech = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _activeSpeech = await _service.getActiveSpeech();
      _profile = await _service.getUserProfile(widget.currentUserId);
      _hasListenedToCurrentSpeech = false;
      if (_activeSpeech != null) {
        final speechId = _activeSpeech!['id'] as int?;
        if (speechId != null) {
          final res = await Supabase.instance.client.from('life_speech_listeners').select().eq('speech_id', speechId).eq('user_id', widget.currentUserId).limit(1).maybeSingle();
          _hasListenedToCurrentSpeech = res != null;
        }
      }
    } catch (e) {
      debugPrint('ListenSpeechWidget refresh error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _onPressedListen() async {
    if (_activeSpeech == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Активная речь не найдена')));
      return;
    }
    if (_hasListenedToCurrentSpeech) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы уже прослушали эту речь')));
      return;
    }
    if (_sessionPressed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Кнопка уже нажималась в этой сессии')));
      return;
    }

    final speechId = _activeSpeech!['id'] as int;

    final result = await showDialog<_ListenDialogResult>(
      context: context,
      builder: (_) => _ListenDialog(defaultN: 1),
    );

    if (result == null) return;

    setState(() => _checkingListened = true);
    try {
      final rpcRes = await _service.listenSpeech(speechId: speechId, userId: widget.currentUserId, agree: result.agree, n: result.n);
      final status = rpcRes['status']?.toString() ?? '';
      String message = 'OK';
      if (status == 'changed_color') {
        final newColor = rpcRes['new_color']?.toString() ?? '';
        final addedM = rpcRes['added_m']?.toString() ?? '';
        message = 'Ваш цвет изменён на $newColor. В банк цвета добавлено $addedM майндов.';
      } else if (status == 'kept_color') {
        final addedV = rpcRes['added_v']?.toString() ?? '';
        message = 'Спасибо, вы остались верны цвету. Вам добавлено $addedV войсов.';
      } else {
        message = rpcRes.toString();
      }

      setState(() {
        _sessionPressed = true;
      });

      await _refresh();

      await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Спасибо за участие в речи'), content: Text(message), actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ОК')),
          ]));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка операции: $e')));
    } finally {
      setState(() => _checkingListened = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_activeSpeech == null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Прослушал речь жизни', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Активных речей нет сейчас.'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _refresh, child: const Text('Обновить')),
          ]),
        ),
      );
    }

    final startedAt = _activeSpeech!['started_at']?.toString() ?? '-';
    final expiresAt = _activeSpeech!['expires_at']?.toString() ?? '-';
    final actorId = _activeSpeech!['politician_id']?.toString() ?? '-';

    final disabled = _hasListenedToCurrentSpeech || _sessionPressed;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Прослушал речь жизни', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Спикер: $actorId'),
          Text('Начало: $startedAt'),
          Text('Окончание: $expiresAt'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: disabled || _checkingListened ? null : _onPressedListen,
            child: _checkingListened
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(disabled ? 'Уже прослушал' : 'Прослушал речь жизни'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _refresh, child: const Text('Обновить')),
        ]),
      ),
    );
  }
}

class _ListenDialogResult {
  final bool agree;
  final num n;
  _ListenDialogResult(this.agree, this.n);
}

class _ListenDialog extends StatefulWidget {
  final num defaultN;
  const _ListenDialog({this.defaultN = 1, Key? key}) : super(key: key);

  @override
  State<_ListenDialog> createState() => _ListenDialogState();
}

class _ListenDialogState extends State<_ListenDialog> {
  bool _agree = false;
  final _nCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nCtrl.text = widget.defaultN.toString();
  }

  @override
  void dispose() {
    _nCtrl.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final n = num.tryParse(_nCtrl.text.trim());
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите корректное положительное число n')));
      return;
    }
    Navigator.of(context).pop(_ListenDialogResult(_agree, n));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Прослушал речь жизни'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Expanded(child: Text('Согласны сменить цвет?')),
          const SizedBox(width: 8),
          Switch(value: _agree, onChanged: (v) => setState(() => _agree = v)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _nCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'n (количество базовой награды)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        ElevatedButton(onPressed: _submitting ? null : _onSubmit, child: const Text('Подтвердить')),
      ],
    );
  }
}
