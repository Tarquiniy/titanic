// lib/services/game_service.dart
// Универсальный сервис-обёртка для операций, упоминаемых в экранах.
// Реализован на базе Supabase client. Подстройте имена таблиц / RPC
// под вашу БД при необходимости.
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
      debugPrint('GameService.fetchSpeechState -> $res');
      if (res is Map<String, dynamic>) return res;
      return null;
    } catch (e, st) {
      debugPrint('GameService.fetchSpeechState error: $e\n$st');
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
      debugPrint('GameService.getActiveLifeSpeech -> $res');
      if (res is Map<String, dynamic>) return res;
      return null;
    } catch (e, st) {
      debugPrint('GameService.getActiveLifeSpeech error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> rpcStartSpeech({required String actorId, required int durationSeconds}) async {
    try {
      final params = {'p_actor': actorId, 'p_duration_seconds': durationSeconds};
      debugPrint('GameService.rpcStartSpeech params: $params');
      final res = await client.rpc('start_speech', params: params);
      debugPrint('GameService.rpcStartSpeech raw res: $res');

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
    } on PostgrestException catch (e, st) {
      debugPrint('GameService.rpcStartSpeech PostgrestException: ${e.message}\n$st');
      throw Exception('start_speech RPC error: ${e.message ?? e.toString()}');
    } catch (e, st) {
      debugPrint('GameService.rpcStartSpeech error: $e\n$st');
      throw Exception('start_speech error: ${e.toString()}');
    }
  }

  /// Calls RPC listen_speech. If RPC fails due to ambiguous overloaded functions,
  /// fallback to performing the equivalent sequence of DB operations client-side.
  /// On success returns a Map with keys:
  ///  - status: 'changed_color' or 'kept_color'
  ///  - new_color (when changed_color)
  ///  - added_m / added_v
  Future<Map<String, dynamic>> rpcListenSpeech({
    required int speechId,
    required String userId,
    required bool agree,
    required int n, // use int here to prefer integer variant
  }) async {
    final params = {
      'p_speech_id': speechId,
      'p_user': userId,
      'p_agree': agree,
      'p_n': n,
    };
    debugPrint('GameService.rpcListenSpeech params: $params');

    try {
      final res = await client.rpc('listen_speech', params: params);
      debugPrint('GameService.rpcListenSpeech raw res: $res');

      // Normalize
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

      if (parsed == null) {
        throw Exception('Empty or unexpected RPC response: $res');
      }
      if (!parsed.containsKey('status')) {
        throw Exception('Unexpected RPC response (missing status): $parsed');
      }
      return parsed;
    } on PostgrestException catch (e, st) {
      debugPrint('GameService.rpcListenSpeech PostgrestException: ${e.message}\n$st');

      // Detect the ambiguous-overloaded-function error and fallback
      final msg = (e.message ?? '').toString();
      if (msg.contains('Could not choose the best candidate function')) {
        debugPrint('GameService.rpcListenSpeech: detected overloaded-function ambiguity -> running fallback implementation');
        return await _fallbackListenSpeech(speechId: speechId, userId: userId, agree: agree, n: n);
      }

      // Other Postgrest errors — rethrow with message
      throw Exception('listen_speech RPC error: ${e.message ?? e.toString()}');
    } catch (e, st) {
      debugPrint('GameService.rpcListenSpeech error: $e\n$st');
      throw Exception('listen_speech error: ${e.toString()}');
    }
  }

  /// Fallback implementation executed when RPC cannot be called due to ambiguity.
  /// Performs same logical steps as server-side listen_speech:
  ///  1) verify life_speeches exists & not expired
  ///  2) check user hasn't already listened
  ///  3) insert into life_speech_listeners
  ///  4) if agree: change user's color to politician's color and add 2n to color_banks
  ///     else: add n to user's v_balance and debit game_bank by n (best-effort)
  Future<Map<String, dynamic>> _fallbackListenSpeech({
    required int speechId,
    required String userId,
    required bool agree,
    required int n,
  }) async {
    try {
      // 1) fetch life_speech
      final life = await client
          .from('life_speeches')
          .select('id, politician_id, started_at, expires_at')
          .eq('id', speechId)
          .maybeSingle();

      if (life == null) {
        throw Exception('speech not found');
      }

      // parse expires_at
      DateTime? expires;
      if (life['expires_at'] != null) {
        try {
          expires = DateTime.tryParse(life['expires_at'].toString());
        } catch (_) {
          expires = null;
        }
      }

      if (expires != null && DateTime.now().toUtc().isAfter(expires.toUtc())) {
        throw Exception('speech expired');
      }

      // 2) check existing listener
      final existed = await client
          .from('life_speech_listeners')
          .select('id')
          .eq('speech_id', speechId)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      if (existed != null) {
        throw Exception('already listened to this speech');
      }

      // 3) insert listener
      await client.from('life_speech_listeners').insert({
        'speech_id': speechId,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 4) branch: agree or not
      if (agree) {
        // change user's color to actor's color and add 2n to color_banks
        final actorId = life['politician_id']?.toString();
        if (actorId == null) throw Exception('speech actor missing');

        // fetch actor color
        final actorCred = await client.from('user_credentials').select('color').eq('id', actorId).maybeSingle();
        final actorColor = (actorCred is Map && actorCred!['color'] != null) ? actorCred['color'].toString() : null;
        if (actorColor == null || actorColor.isEmpty) throw Exception('actor color not found');

        // update user color
        await client.from('user_credentials').update({'color': actorColor}).eq('id', userId);

        // update/insert into color_banks; try to support both 'balance' and 'm_balance' column names
        final bankRow = await client.from('color_banks').select('*').eq('color', actorColor).maybeSingle();

        final addAmount = n * 2;
        if (bankRow == null) {
          // try insert with 'balance' column, fallback to 'm_balance'
          try {
            await client.from('color_banks').insert({'color': actorColor, 'balance': addAmount});
          } catch (_) {
            await client.from('color_banks').insert({'color': actorColor, 'm_balance': addAmount});
          }
        } else {
          if (bankRow.containsKey('balance')) {
            final cur = (bankRow['balance'] is num) ? (bankRow['balance'] as num).toInt() : int.tryParse(bankRow['balance']?.toString() ?? '0') ?? 0;
            final newVal = cur + addAmount;
            await client.from('color_banks').update({'balance': newVal}).eq('color', actorColor);
          } else if (bankRow.containsKey('m_balance')) {
            final cur = (bankRow['m_balance'] is num) ? (bankRow['m_balance'] as num).toInt() : int.tryParse(bankRow['m_balance']?.toString() ?? '0') ?? 0;
            final newVal = cur + addAmount;
            await client.from('color_banks').update({'m_balance': newVal}).eq('color', actorColor);
          } else {
            try {
              final cur = int.tryParse(bankRow.values.firstWhere((_) => true).toString()) ?? 0;
              await client.from('color_banks').update({'balance': cur + addAmount}).eq('color', actorColor);
            } catch (_) {
              // ignore if unknown schema
            }
          }
        }

        return {
          'status': 'changed_color',
          'new_color': actorColor,
          'added_m': addAmount,
        };
      } else {
        // not agree: add n to user's v_balance; try to debit game_bank.m_balance if exists
        try {
          final uc = await client.from('user_credentials').select('v_balance').eq('id', userId).maybeSingle();
          double curV = 0;
          if (uc != null && uc['v_balance'] != null) {
            curV = (uc['v_balance'] is num) ? (uc['v_balance'] as num).toDouble() : double.tryParse(uc['v_balance'].toString()) ?? 0.0;
          }
          final newV = curV + n;
          await client.from('user_credentials').update({'v_balance': newV}).eq('id', userId);
        } catch (e) {
          debugPrint('Fallback: failed to update user v_balance: $e');
          rethrow;
        }

        try {
          final gb = await client.from('game_bank').select('m_balance, id').limit(1).maybeSingle();
          if (gb != null) {
            if (gb.containsKey('m_balance')) {
              final cur = (gb['m_balance'] is num) ? (gb['m_balance'] as num).toDouble() : double.tryParse(gb['m_balance']?.toString() ?? '0') ?? 0.0;
              final newVal = cur - n;
              await client.from('game_bank').update({'m_balance': newVal}).eq('id', gb['id']);
            } else if (gb.containsKey('balance')) {
              final cur = (gb['balance'] is num) ? (gb['balance'] as num).toDouble() : double.tryParse(gb['balance']?.toString() ?? '0') ?? 0.0;
              final newVal = cur - n;
              await client.from('game_bank').update({'balance': newVal}).eq('id', gb['id']);
            }
          }
        } catch (e) {
          debugPrint('Fallback: failed to debit game_bank: $e');
        }

        return {
          'status': 'kept_color',
          'added_v': n,
        };
      }
    } catch (e, st) {
      debugPrint('GameService._fallbackListenSpeech error: $e\n$st');
      rethrow;
    }
  }

  Future<dynamic> rpcPublishArticle({required String userId, required num amount}) async {
    try {
      final res = await client.rpc('publish_article', params: {'p_user': userId, 'p_amount': amount});
      debugPrint('GameService.rpcPublishArticle -> $res');
      return res;
    } on PostgrestException catch (e, st) {
      debugPrint('GameService.rpcPublishArticle PostgrestException: ${e.message}\n$st');
      throw Exception('publish_article RPC error: ${e.message ?? e.toString()}');
    } catch (e, st) {
      debugPrint('GameService.rpcPublishArticle error: $e\n$st');
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
      debugPrint('GameService.checkIfListened -> $res');
      return res != null;
    } catch (e, st) {
      debugPrint('GameService.checkIfListened error: $e\n$st');
      rethrow;
    }
  }

  Future<void> upsertSpeechState({required Map<String, dynamic> obj}) async {
    try {
      debugPrint('GameService.upsertSpeechState obj: $obj');
      await client.from('speech_state').upsert(obj).select().maybeSingle();
    } catch (e, st) {
      debugPrint('GameService.upsertSpeechState error: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------
  // Debates helpers
  // ---------------------------
  Future<Map<String, dynamic>?> getActiveDebate() async {
    final now = DateTime.now().toIso8601String();
    try {
      final res1 = await client.from('debates').select('*').eq('is_closed', false).order('created_at', ascending: false).limit(1).maybeSingle();
      debugPrint('GameService.getActiveDebate (by is_closed) -> $res1');
      if (res1 is Map<String, dynamic>) return res1;
    } catch (e) {
      debugPrint('GameService.getActiveDebate by is_closed error: $e');
    }
    try {
      final res2 = await client.from('debates').select('*').gte('ends_at', now).order('created_at', ascending: false).limit(1).maybeSingle();
      debugPrint('GameService.getActiveDebate (by ends_at) -> $res2');
      if (res2 is Map<String, dynamic>) return res2;
    } catch (e) {
      debugPrint('GameService.getActiveDebate by ends_at error: $e');
    }
    return null;
  }

  Future<void> rpcVoteInDebate({required int debateId, required String userId, required int optionId, required int voices}) async {
    try {
      debugPrint('GameService.rpcVoteInDebate RPC params: debateId=$debateId userId=$userId optionId=$optionId voices=$voices');
      await client.rpc('vote_in_debate', params: {
        'p_debate_id': debateId,
        'p_user_id': userId,
        'p_option_id': optionId,
        'p_voices': voices,
      });
      return;
    } catch (e, st) {
      debugPrint('GameService.rpcVoteInDebate RPC failed: $e\n$st — falling back to insert');
    }

    try {
      await client.from('debate_votes').insert({
        'debate_id': debateId,
        'user_id': userId,
        'option_id': optionId,
        'voices': voices,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e, st) {
      debugPrint('GameService.rpcVoteInDebate insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> rpcCloseDebate({required int debateId}) async {
    try {
      debugPrint('GameService.rpcCloseDebate try RPC close_debate for id=$debateId');
      await client.rpc('close_debate', params: {'p_debate_id': debateId});
      return;
    } catch (e, st) {
      debugPrint('GameService.rpcCloseDebate RPC failed: $e\n$st — falling back to update');
    }
    try {
      await client.from('debates').update({'is_closed': true}).eq('id', debateId);
    } catch (e, st) {
      debugPrint('GameService.rpcCloseDebate update error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> rpcPlacePoliticalBid({
    required int decisionId,
    required String politicianId,
    required num amount,
  }) async {
    try {
      debugPrint('GameService.rpcPlacePoliticalBid params: decisionId=$decisionId politicianId=$politicianId amount=$amount');
      final res = await client.rpc('place_political_bid', params: {
        'p_decision_id': decisionId,
        'p_politician': politicianId,
        'p_amount': amount,
      });
      debugPrint('GameService.rpcPlacePoliticalBid raw res: $res');
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } catch (e, st) {
      debugPrint('GameService.rpcPlacePoliticalBid error: $e\n$st');
      rethrow;
    }
  }
}
