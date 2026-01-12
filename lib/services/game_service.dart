// lib/services/game_service.dart
// Универсальный сервис-обёртка для операций, упоминаемых в экранах.
// Реализован на базе Supabase client. Подстройте имена таблиц / RPC
// под вашу БД при необходимости.
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class GameService {
  final SupabaseClient client = Supabase.instance.client;

  GameService();

  // ---------------------------
  // Speech helpers / RPCs
  // ---------------------------
  Future<Map<String, dynamic>?> fetchSpeechState() async {
    try {
      final res = await client.from('speech_state').select('active, actor_id, expires_at').eq('id', 1).maybeSingle();
      if (res is Map<String, dynamic>) return res;
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getActiveLifeSpeech() async {
    try {
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
    } catch (e) {
      rethrow;
    }
  }

  /// Calls RPC start_speech and returns parsed result (Map) or throws.
  Future<Map<String, dynamic>?> rpcStartSpeech({required String actorId, required int durationSeconds}) async {
    try {
      final res = await client.rpc('start_speech', params: {'p_actor': actorId, 'p_duration_seconds': durationSeconds});

      if (res is Map<String, dynamic>) return res;
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      if (res is String) {
        try {
          return Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          return {'raw': res};
        }
      }
      return null;
    } on PostgrestException catch (e) {
      throw Exception('start_speech RPC error: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('start_speech error: ${e.toString()}');
    }
  }

  /// Calls RPC listen_speech. Returns parsed Map (if possible) or raw response.
  /// Throws exception on RPC failure.
  Future<dynamic> rpcListenSpeech({
    required int speechId,
    required String userId,
    required bool agree,
    required num n,
  }) async {
    try {
      final params = {
        'p_speech_id': speechId,
        'p_user': userId,
        'p_agree': agree,
        'p_n': n,
      };

      final res = await client.rpc('listen_speech', params: params);

      // Normalize response
      if (res is Map<String, dynamic>) return res;
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      if (res is String) {
        try {
          return Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          return res;
        }
      }
      return res;
    } on PostgrestException catch (e) {
      throw Exception('listen_speech RPC error: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('listen_speech error: ${e.toString()}');
    }
  }

  Future<dynamic> rpcPublishArticle({required String userId, required num amount}) async {
    try {
      final res = await client.rpc('publish_article', params: {'p_user': userId, 'p_amount': amount});
      return res;
    } on PostgrestException catch (e) {
      throw Exception('publish_article RPC error: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('publish_article error: ${e.toString()}');
    }
  }

  Future<bool> checkIfListened({required int speechId, required String userId}) async {
    try {
      final res = await client
          .from('life_speech_listeners')
          .select('id')
          .eq('speech_id', speechId)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      return res != null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> upsertSpeechState({required Map<String, dynamic> obj}) async {
    try {
      await client.from('speech_state').upsert(obj).select().maybeSingle();
    } catch (e) {
      rethrow;
    }
  }

  // ---------------------------
  // Debates helpers
  // ---------------------------
  /// Возвращает активные дебаты (null если нет)
  Future<Map<String, dynamic>?> getActiveDebate() async {
    final now = DateTime.now().toIso8601String();
    try {
      final res1 = await client.from('debates').select('*').eq('is_closed', false).order('created_at', ascending: false).limit(1).maybeSingle();
      if (res1 is Map<String, dynamic>) return res1;
    } catch (_) {}
    try {
      final res2 = await client.from('debates').select('*').gte('ends_at', now).order('created_at', ascending: false).limit(1).maybeSingle();
      if (res2 is Map<String, dynamic>) return res2;
    } catch (_) {}
    return null;
  }

  /// Голос за дебаты — реализован как RPC wrapper, если нет — пытаемся вставить в таблицу votes
  Future<void> rpcVoteInDebate({required int debateId, required String userId, required int optionId, required int voices}) async {
    try {
      await client.rpc('vote_in_debate', params: {
        'p_debate_id': debateId,
        'p_user_id': userId,
        'p_option_id': optionId,
        'p_voices': voices,
      });
      return;
    } catch (_) {
      // fallthrough -> attempt insert
    }

    try {
      await client.from('debate_votes').insert({
        'debate_id': debateId,
        'user_id': userId,
        'option_id': optionId,
        'voices': voices,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> rpcCloseDebate({required int debateId}) async {
    try {
      await client.rpc('close_debate', params: {'p_debate_id': debateId});
      return;
    } catch (_) {}
    try {
      await client.from('debates').update({'is_closed': true}).eq('id', debateId);
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
      final res = await client.rpc('place_political_bid', params: {
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
}
