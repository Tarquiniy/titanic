// lib/services/game_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class GameService {
  final supabase = Supabase.instance.client;

  // Debates
  Future<Map<String, dynamic>?> getActiveDebate() async {
    try {
      final res = await supabase
          .from('debates')
          .select('id, title, created_by, is_active, created_at')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDebateOptions(int debateId) async {
    try {
      final res = await supabase.from('debate_options').select('id, color').eq('debate_id', debateId).order('id');
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDebateSpeakers(int debateId) async {
    try {
      final res = await supabase.from('debate_speakers').select('id, color, politician_id').eq('debate_id', debateId);
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rpcVoteInDebate({
    required int debateId,
    required String userId,
    required int optionId,
    required num voices,
  }) async {
    try {
      final res = await supabase.rpc('vote_in_debate', params: {
        'p_debate_id': debateId,
        'p_user': userId,
        'p_option_id': optionId,
        'p_voices': voices,
      });
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rpcCloseDebate({required int debateId}) async {
    try {
      final res = await supabase.rpc('close_debate', params: {'p_debate_id': debateId});
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rpcPlacePoliticalBid({
    required int decisionId,
    required String politicianId,
    required num amount,
  }) async {
    try {
      final res = await supabase.rpc('place_political_bid', params: {
        'p_decision_id': decisionId,
        'p_politician': politicianId,
        'p_amount': amount,
      });
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rpcListenSpeech({
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

  Future<Map<String, dynamic>> rpcStartSpeech({
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

  Future<List<Map<String, dynamic>>> getPoliticians() async {
    try {
      final res = await supabase.from('user_credentials').select('id, telegram_username, first_name, last_name, color').eq('role', 'politician').order('first_name');
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e) {
      rethrow;
    }
  }
}
