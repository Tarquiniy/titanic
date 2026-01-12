// lib/services/supabase_service.dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient client;
  SupabaseService(this.client);

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final res = await client
        .from('user_credentials')
        .select('id, telegram_username, role, first_name, last_name, v_balance, m_balance, color, used_honor_article')
        .eq('id', userId)
        .maybeSingle();
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  Future<Map<String, dynamic>?> fetchSpeechState() async {
    final res = await client.from('speech_state').select('active, actor_id, expires_at').eq('id', 1).maybeSingle();
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  Future<Map<String, dynamic>?> getActiveLifeSpeech() async {
    final now = DateTime.now().toIso8601String();
    final res = await client
        .from('life_speeches')
        .select('id, politician_id, started_at, expires_at')
        .gte('expires_at', now)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res is Map<String, dynamic>) return res;
    return null;
  }

  Future<dynamic> rpcStartSpeech({required String actorId, required int durationSeconds}) async {
    return client.rpc('start_speech', params: {'p_actor': actorId, 'p_duration_seconds': durationSeconds});
  }

  Future<dynamic> rpcListenSpeech({required int speechId, required String userId, required bool agree, required num n}) async {
    return client.rpc('listen_speech', params: {'p_speech_id': speechId, 'p_user': userId, 'p_agree': agree, 'p_n': n});
  }

  Future<dynamic> rpcPublishArticle({required String userId, required num amount}) async {
    return client.rpc('publish_article', params: {'p_user': userId, 'p_amount': amount});
  }

  Future<bool> checkIfListened({required int speechId, required String userId}) async {
    final res = await client
        .from('life_speech_listeners')
        .select('id')
        .eq('speech_id', speechId)
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle();
    return res != null;
  }

  Future<void> upsertSpeechState({required Map<String, dynamic> obj}) async {
    await client.from('speech_state').upsert(obj).select().maybeSingle();
  }
}
