import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResolutionService {
  final SupabaseClient supabase;
  Timer? _pollTimer;

  ResolutionService(this.supabase);

  Future<int?> loadActiveResolutionId() async {
    try {
      final active = await supabase
          .from('political_resolutions')
          .select('id')
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (active is Map && active!['id'] != null) {
        return (active['id'] is int)
            ? active['id'] as int
            : int.tryParse(active['id'].toString());
      }
    } catch (_) {}
    return null;
  }

  Future<bool> userAlreadyBet(String userId, int resolutionId) async {
    try {
      final bet = await supabase
          .from('resolution_votes')
          .select('id')
          .eq('resolution_id', resolutionId)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();

      return bet != null;
    } catch (_) {}
    return false;
  }

  void startPolling(void Function() callback, {int seconds = 5}) {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(Duration(seconds: seconds), (_) => callback());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() => stopPolling();
}
