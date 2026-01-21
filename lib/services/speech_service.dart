// lib/services/speech_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';

typedef SpeechStateCallback = void Function(Map<String, dynamic> state);

class SpeechService {
  final GameService svc;
  final SupabaseClient supabase;
  Timer? _pollTimer;
  SpeechStateCallback? onState;

  SpeechService({required this.svc, required this.supabase});

  void startPolling({int seconds = 3}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => _fetch());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetch() async {
    try {
      final res = await svc.fetchSpeechState();
      if (res is Map<String, dynamic>) {
        onState?.call(res);
      } else {
        onState?.call({'active': false});
      }
    } catch (_) {
      // ignore errors during background polling
    }
  }

  /// Start speech via RPC and return parsed Map result when available.
  /// RPC can return either a Map or a List whose first element is a Map.
  Future<Map<String, dynamic>?> startSpeech({required String actorId, required int durationSeconds}) async {
    try {
      final dynamic rpcRes = await svc.rpcStartSpeech(actorId: actorId, durationSeconds: durationSeconds);

      if (rpcRes is Map<String, dynamic>) {
        return rpcRes;
      }

      if (rpcRes is List && rpcRes.isNotEmpty && rpcRes[0] is Map) {
        return Map<String, dynamic>.from(rpcRes[0] as Map);
      }

      return null;
    } catch (e) {
      rethrow;
    }
  }

  void dispose() {
    stopPolling();
  }
}
