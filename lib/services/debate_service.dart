// lib/services/debate_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class DebateService {
  final SupabaseClient supabase;
  Timer? _pollTimer;

  DebateService(this.supabase);

  Future<int?> loadActiveDebateId() async {
    try {
      final active = await supabase.from('debates').select('id').eq('is_closed', false).order('created_at', ascending: false).limit(1).maybeSingle();
      if (active is Map && active!['id'] != null) {
        return (active['id'] is int) ? active!['id'] as int : int.tryParse(active['id'].toString());
      }
    } catch (_) {}
    return null;
  }

  Future<bool> userAlreadyVoted(String userId, int debateId) async {
    try {
      final vote = await supabase.from('debate_votes').select('id').eq('debate_id', debateId).eq('user_id', userId).limit(1).maybeSingle();
      return vote != null;
    } catch (_) {}
    return false;
  }

  void startPolling(void Function() callback, {int seconds = 5}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) => callback());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() => stopPolling();
}
