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

  // helper to log PostgrestException details
  void _logPostgrestException(PostgrestException e) {
    try {
      debugPrint(
          'PostgrestException: message=${e.message}, details=${e.details}, hint=${e.hint}, code=${e.code}');
    } catch (err) {
      debugPrint('Failed to print PostgrestException details: $err -- raw: $e');
    }
  }

  // ---------------------------
  // Speech helpers / RPCs
  // ---------------------------
  Future<Map<String, dynamic>?> fetchSpeechState() async {
    try {
      final res = await client
          .from('speech_state')
          .select('active, actor_id, expires_at')
          .eq('id', 1)
          .maybeSingle();
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

  Future<Map<String, dynamic>?> rpcStartSpeech(
      {required String actorId, required int durationSeconds}) async {
    try {
      final params = {'p_actor': actorId, 'p_duration_seconds': durationSeconds};
      debugPrint('GameService.rpcStartSpeech params: $params');
      final res = await client.rpc('start_speech', params: params);
      debugPrint('GameService.rpcStartSpeech raw res: $res');

      if (res is Map<String, dynamic>) return res;
      if (res is List && res.isNotEmpty && res[0] is Map)
        return Map<String, dynamic>.from(res[0] as Map);
      if (res is String) {
        try {
          return Map<String, dynamic>.from(jsonDecode(res) as Map);
        } catch (_) {
          return {'raw': res};
        }
      }
      return null;
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.rpcStartSpeech PostgrestException stack:\n$st');
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
      else if (res is List && res.isNotEmpty && res[0] is Map)
        parsed = Map<String, dynamic>.from(res[0] as Map);
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
      _logPostgrestException(e);
      debugPrint('GameService.rpcListenSpeech PostgrestException stack:\n$st');

      // Detect the ambiguous-overloaded-function error and fallback
      final msg = (e.message ?? '').toString();
      if (msg.contains('Could not choose the best candidate function') ||
          (e.details ?? '').toString().contains('ambiguous')) {
        debugPrint(
            'GameService.rpcListenSpeech: detected overloaded-function ambiguity -> running fallback implementation');
        return await _fallbackListenSpeech(
            speechId: speechId, userId: userId, agree: agree, n: n);
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

      if (expires != null &&
          DateTime.now().toUtc().isAfter(expires.toUtc())) {
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
        final actorCred = await client
            .from('user_credentials')
            .select('color')
            .eq('id', actorId)
            .maybeSingle();
        final actorColor = (actorCred is Map && actorCred!['color'] != null)
            ? actorCred['color'].toString()
            : null;
        if (actorColor == null || actorColor.isEmpty)
          throw Exception('actor color not found');

        // update user color
        await client
            .from('user_credentials')
            .update({'color': actorColor})
            .eq('id', userId);

        // update/insert into color_banks; try to support both 'balance' and 'm_balance' column names
        final bankRow = await client
            .from('color_banks')
            .select('*')
            .eq('color', actorColor)
            .maybeSingle();

        final addAmount = n * 2;
        if (bankRow == null) {
          // try insert with 'balance' column, fallback to 'm_balance'
          try {
            await client
                .from('color_banks')
                .insert({'color': actorColor, 'balance': addAmount});
          } catch (_) {
            await client
                .from('color_banks')
                .insert({'color': actorColor, 'm_balance': addAmount});
          }
        } else {
          if (bankRow.containsKey('balance')) {
            final cur = (bankRow['balance'] is num)
                ? (bankRow['balance'] as num).toInt()
                : int.tryParse(bankRow['balance']?.toString() ?? '0') ?? 0;
            final newVal = cur + addAmount;
            await client
                .from('color_banks')
                .update({'balance': newVal}).eq('color', actorColor);
          } else if (bankRow.containsKey('m_balance')) {
            final cur = (bankRow['m_balance'] is num)
                ? (bankRow['m_balance'] as num)
                : num.tryParse(bankRow['m_balance']?.toString() ?? '0')!;
            final newVal = cur + addAmount;
            await client
                .from('color_banks')
                .update({'m_balance': newVal}).eq('color', actorColor);
          } else {
            try {
              final cur = int.tryParse(
                      bankRow.values.firstWhere((_) => true).toString()) ??
                  0;
              await client
                  .from('color_banks')
                  .update({'balance': cur + addAmount}).eq('color', actorColor);
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
          final uc = await client
              .from('user_credentials')
              .select('v_balance')
              .eq('id', userId)
              .maybeSingle();
          double curV = 0;
          if (uc != null && uc['v_balance'] != null) {
            curV = (uc['v_balance'] is num)
                ? (uc['v_balance'] as num).toDouble()
                : double.tryParse(uc['v_balance'].toString()) ?? 0.0;
          }
          final newV = curV + n;
          await client
              .from('user_credentials')
              .update({'v_balance': newV}).eq('id', userId);
        } catch (e) {
          debugPrint('Fallback: failed to update user v_balance: $e');
          rethrow;
        }

        try {
          final gb = await client
              .from('game_bank')
              .select('m_balance, id')
              .limit(1)
              .maybeSingle();
          if (gb != null) {
            if (gb.containsKey('m_balance')) {
              final cur = (gb['m_balance'] is num)
                  ? (gb['m_balance'] as num).toDouble()
                  : double.tryParse(gb['m_balance']?.toString() ?? '0') ?? 0.0;
              final newVal = cur - n;
              await client
                  .from('game_bank')
                  .update({'m_balance': newVal}).eq('id', gb['id']);
            } else if (gb.containsKey('balance')) {
              final cur = (gb['balance'] is num)
                  ? (gb['balance'] as num).toDouble()
                  : double.tryParse(gb['balance']?.toString() ?? '0') ?? 0.0;
              final newVal = cur - n;
              await client
                  .from('game_bank')
                  .update({'balance': newVal}).eq('id', gb['id']);
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

  Future<dynamic> rpcPublishArticle(
      {required String userId, required num amount}) async {
    try {
      final res =
          await client.rpc('publish_article', params: {'p_user': userId, 'p_amount': amount});
      debugPrint('GameService.rpcPublishArticle -> $res');
      return res;
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.rpcPublishArticle PostgrestException stack:\n$st');
      throw Exception('publish_article RPC error: ${e.message ?? e.toString()}');
    } catch (e, st) {
      debugPrint('GameService.rpcPublishArticle error: $e\n$st');
      throw Exception('publish_article error: ${e.toString()}');
    }
  }

  Future<bool> checkIfListened(
      {required int speechId, required String userId}) async {
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
      final res1 = await client
          .from('debates')
          .select('*')
          .eq('is_closed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      debugPrint('GameService.getActiveDebate (by is_closed) -> $res1');
      if (res1 is Map<String, dynamic>) return res1;
    } catch (e) {
      debugPrint('GameService.getActiveDebate by is_closed error: $e');
    }
    try {
      final res2 = await client
          .from('debates')
          .select('*')
          .gte('ends_at', now)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      debugPrint('GameService.getActiveDebate (by ends_at) -> $res2');
      if (res2 is Map<String, dynamic>) return res2;
    } catch (e) {
      debugPrint('GameService.getActiveDebate by ends_at error: $e');
    }
    return null;
  }

  Future<void> rpcVoteInDebate(
      {required int debateId,
      required String userId,
      required int optionId,
      required int voices}) async {
    debugPrint(
        'GameService.rpcVoteInDebate RPC params: debateId=$debateId userId=$userId optionId=$optionId voices=$voices');

    try {
      // attempt RPC call and log the raw result
      final raw = await client.rpc('vote_in_debate', params: {
        'p_debate_id': debateId,
        'p_user_id': userId,
        'p_option_id': optionId,
        'p_voices': voices,
      });
      debugPrint('GameService.rpcVoteInDebate RPC raw result: $raw');
      return;
    } on PostgrestException catch (e, st) {
      // detailed logging for PostgrestException
      _logPostgrestException(e);
      debugPrint('GameService.rpcVoteInDebate PostgrestException stack:\n$st');

      // If we detect type-mismatch error, give explicit hint to logs
      final msg = (e.message ?? '').toString();
      if (msg.contains('operator does not exist') && msg.contains('uuid = text')) {
        debugPrint(
            'GameService.rpcVoteInDebate detected uuid=text operator error. Likely cause: SQL compares uuid column with text parameter. Check function vote_in_debate for casting id::text or using p_user_id::uuid.');
      }
      debugPrint(
          'GameService.rpcVoteInDebate RPC failed: ${e.message} | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
    } catch (e, st) {
      debugPrint('GameService.rpcVoteInDebate RPC failed (non-Postgrest): $e\n$st');
    }

    debugPrint(
        'GameService.rpcVoteInDebate falling back to client-side insert (best-effort).');

    // Best-effort fallback: check v_balance client-side and then insert vote + try to debit v_balance.
    try {
      // fetch current v_balance (best-effort)
      double vbal = 0.0;
      try {
        final profile = await client
            .from('user_credentials')
            .select('v_balance')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && profile['v_balance'] != null) {
          vbal = (profile['v_balance'] is num)
              ? (profile['v_balance'] as num).toDouble()
              : double.tryParse(profile['v_balance'].toString()) ?? 0.0;
        }
        debugPrint(
            'GameService.rpcVoteInDebate fallback: fetched v_balance=$vbal for userId=$userId');
      } catch (e) {
        debugPrint(
            'GameService.rpcVoteInDebate fallback: failed to fetch v_balance: $e');
      }

      if (vbal < voices) {
        debugPrint(
            'GameService.rpcVoteInDebate fallback: insufficient V balance (client-side): have $vbal need $voices -> aborting fallback insert');
        throw Exception(
            'Insufficient V balance (client-side) have=$vbal need=$voices');
      }

      // perform debit (non-atomic) - best effort
      try {
        await client
            .from('user_credentials')
            .update({'v_balance': (vbal - voices)})
            .eq('id', userId);
        debugPrint(
            'GameService.rpcVoteInDebate fallback: debited v_balance by $voices for userId=$userId, new approx=${vbal - voices}');
      } catch (e) {
        debugPrint(
            'GameService.rpcVoteInDebate fallback: failed to debit v_balance: $e');
        // continue to try inserting vote; server-side will need to reconcile
      }

      // insert vote row
      await client.from('debate_votes').insert({
        'debate_id': debateId,
        'user_id': userId,
        'option_id': optionId,
        'voices': voices,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint(
          'GameService.rpcVoteInDebate fallback: inserted vote row for userId=$userId debateId=$debateId optionId=$optionId voices=$voices');
      return;
    } catch (e, st) {
      debugPrint('GameService.rpcVoteInDebate fallback insert error: $e\n$st');
      rethrow;
    }
  }

  Future<void> rpcCloseDebate({required int debateId}) async {
    debugPrint('GameService.rpcCloseDebate try RPC close_debate for id=$debateId');
    try {
      final raw =
          await client.rpc('close_debate', params: {'p_debate_id': debateId});
      debugPrint('GameService.rpcCloseDebate RPC raw result: $raw');
      return;
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.rpcCloseDebate PostgrestException stack:\n$st');

      final msg = (e.message ?? '').toString();
      if (msg.contains('operator does not exist') && msg.contains('uuid = text')) {
        debugPrint(
            'GameService.rpcCloseDebate detected uuid=text operator error. Likely cause: SQL compares uuid column with text parameter. Check close_debate implementation for proper casting (id::text or p_user_id::uuid).');
      }
      debugPrint(
          'GameService.rpcCloseDebate RPC failed: ${e.message} | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
    } catch (e, st) {
      debugPrint('GameService.rpcCloseDebate RPC failed (non-Postgrest): $e\n$st');
    }

    debugPrint(
        'GameService.rpcCloseDebate falling back to marking debate closed (best-effort).');
    try {
      await client.from('debates').update({'is_closed': true}).eq('id', debateId);
      debugPrint(
          'GameService.rpcCloseDebate fallback: marked debate is_closed=true for id=$debateId');
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
      debugPrint(
          'GameService.rpcPlacePoliticalBid params: decisionId=$decisionId politicianId=$politicianId amount=$amount');
      final res = await client.rpc('place_political_bid', params: {
        'p_decision_id': decisionId,
        'p_politician': politicianId,
        'p_amount': amount,
      });
      debugPrint('GameService.rpcPlacePoliticalBid raw res: $res');
      if (res == null) throw Exception('Empty response');
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map)
        return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.rpcPlacePoliticalBid PostgrestException stack:\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('GameService.rpcPlacePoliticalBid error: $e\n$st');
      rethrow;
    }
  }

  /// Get resolutions. If onlyActive=true, return only not-closed ones.
  Future<List<Map<String, dynamic>>> getResolutions(
      {bool onlyActive = false}) async {
    try {
      final List<dynamic> res;
      if (onlyActive) {
        res = await client
            .from('political_resolutions')
            .select('*')
            .eq('is_closed', false)
            .order('created_at', ascending: false);
      } else {
        res = await client
            .from('political_resolutions')
            .select('*')
            .order('created_at', ascending: false);
      }
      debugPrint('GameService.getResolutions -> $res');
      if (res is List)
        return (res).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e, st) {
      debugPrint('GameService.getResolutions error: $e\n$st');
      rethrow;
    }
  }

  /// Create a new political resolution (admin). Returns created row.
  Future<Map<String, dynamic>?> createResolution({
    required String title,
    String description = '',
    required String color,
    String? createdBy,
  }) async {
    final payload = {
      'title': title,
      'description': description,
      'color': color,
      'created_by': createdBy,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_closed': false,
    };

    try {
      debugPrint('GameService.createResolution payload: $payload');
      final res =
          await client.from('political_resolutions').insert(payload).select().maybeSingle();
      debugPrint('GameService.createResolution -> $res');
      if (res is Map<String, dynamic>) return Map<String, dynamic>.from(res);
      return null;
    } catch (e, st) {
      debugPrint('GameService.createResolution error: $e\n$st');
      rethrow;
    }
  }

  /// Place bet in resolution: uses RPC place_bet_in_resolution (atomic)
  /// If RPC fails, fallback attempts are best-effort (non-atomic).
  ///
  /// IMPORTANT: optionId is required — bets must reference a specific resolution option.
  Future<void> placeBetInResolution({
    required int resolutionId,
    required int optionId,
    required String userId, // text uuid
    required num amount,
  }) async {
    debugPrint(
        'GameService.placeBetInResolution RPC params: resolutionId=$resolutionId optionId=$optionId userId=$userId amount=$amount');

    if (optionId <= 0) {
      throw Exception('optionId is required and must be > 0');
    }
    if (amount <= 0) {
      throw Exception('amount must be > 0');
    }

    try {
      // call RPC (expects p_user_id uuid; supabase will cast string -> uuid if possible)
      final raw = await client.rpc('place_bet_in_resolution', params: {
        'p_resolution_id': resolutionId,
        'p_option_id': optionId,
        'p_user_id': userId,
        'p_amount': amount,
      });
      debugPrint('GameService.placeBetInResolution RPC raw result: $raw');
      return;
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.placeBetInResolution PostgrestException stack:\n$st');
      // detect insufficient balance or other custom exceptions by message
      final msg = (e.message ?? '').toString();
      if (msg.toLowerCase().contains('insufficient')) {
        throw Exception('Недостаточно майндов на счёту');
      }
      // fall through to fallback below
      debugPrint('GameService.placeBetInResolution RPC failed: ${e.message} — falling back');
    } catch (e, st) {
      debugPrint(
          'GameService.placeBetInResolution RPC failed non-Postgrest: $e\n$st — falling back');
    }

    // Fallback: best-effort client-side (not atomic) — we try to debit and insert
    try {
      // fetch current m_balance
      double mBal = 0.0;
      try {
        final prof = await client
            .from('user_credentials')
            .select('m_balance')
            .eq('id', userId)
            .maybeSingle();
        if (prof != null && prof['m_balance'] != null) {
          mBal = (prof['m_balance'] is num)
              ? (prof['m_balance'] as num).toDouble()
              : double.tryParse(prof['m_balance'].toString()) ?? 0.0;
        }
        debugPrint(
            'GameService.placeBetInResolution fallback: fetched m_balance=$mBal for userId=$userId');
      } catch (e) {
        debugPrint(
            'GameService.placeBetInResolution fallback: failed to fetch m_balance: $e');
      }

      if (mBal < amount) {
        throw Exception(
            'Insufficient M balance (client-side): have $mBal need $amount');
      }

      // debit (best-effort)
      try {
        await client
            .from('user_credentials')
            .update({'m_balance': (mBal - amount)})
            .eq('id', userId);
        debugPrint(
            'GameService.placeBetInResolution fallback: debited m_balance by $amount for userId=$userId');
      } catch (e) {
        debugPrint(
            'GameService.placeBetInResolution fallback: failed to debit m_balance: $e');
        // still try to insert bet row
      }

      // insert bet (must include option_id)
      await client.from('political_bets').insert({
        'resolution_id': resolutionId,
        'option_id': optionId,
        'user_id': userId,
        'amount': amount,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint(
          'GameService.placeBetInResolution fallback: inserted bet row (resolution=$resolutionId option=$optionId user=$userId amount=$amount)');
    } catch (e, st) {
      debugPrint('GameService.placeBetInResolution fallback error: $e\n$st');
      rethrow;
    }
  }

  /// Close resolution by admin: calls RPC close_resolution, on failure falls back
  /// to client-side aggregation/distribution logic.
  Future<Map<String, dynamic>?> rpcCloseResolution(
      {required int resolutionId}) async {
    debugPrint(
        'GameService.rpcCloseResolution try RPC close_resolution for id=$resolutionId');
    try {
      final raw =
          await client.rpc('close_resolution', params: {'p_resolution_id': resolutionId});
      debugPrint('GameService.rpcCloseResolution raw: $raw');
      // normalize response (rpc returns jsonb)
      if (raw == null) return null;
      if (raw is Map<String, dynamic>) return raw;
      if (raw is String) {
        try {
          return Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          return {'raw': raw};
        }
      }
      if (raw is List && raw.isNotEmpty && raw[0] is Map)
        return Map<String, dynamic>.from(raw[0] as Map);
      return {'result': raw.toString()};
    } on PostgrestException catch (e, st) {
      _logPostgrestException(e);
      debugPrint('GameService.rpcCloseResolution PostgrestException stack:\n$st');

      final msg = (e.message ?? '').toString();
      if (msg.contains('column reference') ||
          msg.contains('ambiguous') ||
          msg.contains('operator does not exist')) {
        debugPrint(
            'GameService.rpcCloseResolution detected DB-side error -> will run client-side fallback close (best-effort). Error: ${e.message}');
        // proceed to fallback below
      } else {
        debugPrint(
            'GameService.rpcCloseResolution RPC failed: ${e.message} | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
        throw Exception('close_resolution RPC error: ${e.message ?? e.toString()}');
      }
    } catch (e, st) {
      debugPrint(
          'GameService.rpcCloseResolution RPC failed (non-Postgrest): $e\n$st — attempting fallback');
      // continue to fallback
    }

    // ------------------------
    // Fallback implementation (best-effort, non-atomic)
    // ------------------------
    try {
      debugPrint(
          'GameService.rpcCloseResolution: running fallback logic for resolutionId=$resolutionId');

      // 1) load resolution
      final resRow = await client
          .from('political_resolutions')
          .select('id, title, is_closed, created_at')
          .eq('id', resolutionId)
          .maybeSingle();
      if (resRow == null) {
        throw Exception('Resolution not found (id=$resolutionId)');
      }
      if (resRow is Map && (resRow['is_closed'] == true)) {
        debugPrint(
            'GameService.rpcCloseResolution: resolution already closed - returning existing state');
        return Map<String, dynamic>.from(resRow as Map);
      }

      // 2) load options
      final optsRaw = await client
          .from('resolution_options')
          .select('id, label, color')
          .eq('resolution_id', resolutionId);
      final List<Map<String, dynamic>> options = (optsRaw is List)
          ? optsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];

      // 3) load bets
      final betsRaw = await client
          .from('political_bets')
          .select('id, user_id, amount, option_id')
          .eq('resolution_id', resolutionId);
      final List<Map<String, dynamic>> bets = (betsRaw is List)
          ? betsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];

      debugPrint(
          'rpcCloseResolution: loaded ${options.length} options and ${bets.length} bets');

      // 4) aggregate sums per option
      final Map<int, num> sumPerOption = {};
      num totalM = 0;
      for (final b in bets) {
        final opt = (b['option_id'] is int)
            ? b['option_id'] as int
            : int.tryParse(b['option_id']?.toString() ?? '') ?? 0;
        final amt = (b['amount'] is num)
            ? (b['amount'] as num)
            : num.tryParse(b['amount']?.toString() ?? '') ?? 0;
        sumPerOption[opt] = (sumPerOption[opt] ?? 0) + amt;
        totalM += amt;
      }

      debugPrint('rpcCloseResolution: totalM=$totalM sumPerOption=$sumPerOption');

      // 5) determine winning option (highest sum)
      int? winningOptionId;
      num winningSum = -1;
      for (final entry in sumPerOption.entries) {
        if (entry.value > winningSum) {
          winningSum = entry.value;
          winningOptionId = entry.key;
        } else if (entry.value == winningSum && winningOptionId != null) {
          // tie-break: keep existing winner (first max). Could be adjusted.
        }
      }

      // 6) determine winning user (user who placed highest single bet on winning option) if any
      String? winningUserId;
      if (winningOptionId != null) {
        num bestBet = -1;
        for (final b in bets) {
          final opt = (b['option_id'] is int)
              ? b['option_id'] as int
              : int.tryParse(b['option_id']?.toString() ?? '') ?? 0;
          if (opt != winningOptionId) continue;
          final amt = (b['amount'] is num)
              ? (b['amount'] as num)
              : num.tryParse(b['amount']?.toString() ?? '') ?? 0;
          if (amt > bestBet) {
            bestBet = amt;
            winningUserId = b['user_id']?.toString();
          }
        }
      }

      // 7) distribute sums to color_banks per option color
      // Map optionId -> color
      final Map<int, String> optionColor = {};
      for (final o in options) {
        final oid = (o['id'] is int)
            ? o['id'] as int
            : int.tryParse(o['id']?.toString() ?? '') ?? 0;
        final col = (o['color'] ?? '').toString();
        optionColor[oid] = col;
      }

      // For each option, add sumPerOption[opt] to color bank of optionColor[opt]
      for (final entry in sumPerOption.entries) {
        final optId = entry.key;
        final sum = entry.value;
        final col = optionColor[optId];
        if (col == null || col.isEmpty) {
          debugPrint(
              'rpcCloseResolution: option $optId has no color, skipping bank add');
          continue;
        }
        if (sum == 0) {
          debugPrint(
              'rpcCloseResolution: option $optId sum is zero, skipping bank add');
          continue;
        }
        await _addToColorBank(col, sum);
        debugPrint(
            'rpcCloseResolution: added $sum to color bank for color=$col (option=$optId)');
      }

      // 8) update resolution row: mark closed, set totals and winner info
      final upd = {
        'is_closed': true,
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'total_m': totalM, // ensure column exists in DB (numeric)
      };

      if (winningOptionId != null) {
        upd['winning_option_id'] = winningOptionId;
      }
      if (winningUserId != null) {
        upd['winning_user_id'] = winningUserId;
      }

      try {
        await client
            .from('political_resolutions')
            .update(upd)
            .eq('id', resolutionId);
        debugPrint(
            'rpcCloseResolution: updated political_resolutions id=$resolutionId with $upd');
      } catch (e) {
        debugPrint('rpcCloseResolution: failed to update political_resolutions: $e');
      }

      // 9) return summary for caller (useful for UI)
      final winnerLabel = (winningOptionId != null)
          ? (options.firstWhere(
                  (o) =>
                      ((o['id'] is int
                          ? o['id'] as int
                          : int.tryParse(o['id']?.toString() ?? '') ?? 0) ==
                          winningOptionId),
                  orElse: () => {})['label'] ??
              '')
          : null;

      final result = <String, dynamic>{
        'resolution_id': resolutionId,
        'total_m': totalM,
        'winning_option_id': winningOptionId,
        'winning_option_label': winnerLabel,
        'winning_user_id': winningUserId,
        'per_option_sums': sumPerOption,
      };

      debugPrint('rpcCloseResolution fallback result: $result');
      return result;
    } catch (e, st) {
      debugPrint('GameService.rpcCloseResolution fallback error: $e\n$st');
      throw Exception('close_resolution fallback error: ${e.toString()}');
    }
  }

  /// Helper: add amount to color bank. Tries 'm_balance' then 'balance' then inserts.
  Future<void> _addToColorBank(String color, num amount) async {
    if (amount == 0) return;
    try {
      final bank =
          await client.from('color_banks').select('*').eq('color', color).maybeSingle();
      if (bank == null) {
        // try inserting with m_balance first
        try {
          await client.from('color_banks').insert({'color': color, 'm_balance': amount});
          debugPrint('_addToColorBank: inserted new color_banks row with m_balance for $color += $amount');
          return;
        } catch (e) {
          // fallback to balance
          await client.from('color_banks').insert({'color': color, 'balance': amount});
          debugPrint('_addToColorBank: inserted new color_banks row with balance for $color += $amount');
          return;
        }
      } else {
        if (bank.containsKey('m_balance')) {
          final cur = (bank['m_balance'] is num)
              ? (bank['m_balance'] as num)
              : num.tryParse(bank['m_balance']?.toString() ?? '') ?? 0;
          final newVal = cur + amount;
          await client.from('color_banks').update({'m_balance': newVal}).eq('color', color);
          return;
        } else if (bank.containsKey('balance')) {
          final cur = (bank['balance'] is num)
              ? (bank['balance'] as num)
              : num.tryParse(bank['balance']?.toString() ?? '') ?? 0;
          final newVal = cur + amount;
          await client.from('color_banks').update({'balance': newVal}).eq('color', color);
          return;
        } else {
          // unknown schema: attempt to update 'm_balance'
          try {
            await client.from('color_banks').update({'m_balance': amount}).eq('color', color);
            return;
          } catch (_) {
            await client.from('color_banks').update({'balance': amount}).eq('color', color);
            return;
          }
        }
      }
    } catch (e, st) {
      debugPrint('_addToColorBank error for color=$color amount=$amount: $e\n$st');
      rethrow;
    }
  }

  // Additional helper: get bets for a resolution
  Future<List<Map<String, dynamic>>> getBetsForResolution(int resolutionId) async {
    try {
      final res = await client
          .from('political_bets')
          .select('*')
          .eq('resolution_id', resolutionId)
          .order('amount', ascending: false);
      debugPrint('GameService.getBetsForResolution -> $res');
      if (res is List) return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return [];
    } catch (e, st) {
      debugPrint('GameService.getBetsForResolution error: $e\n$st');
      rethrow;
    }
  }


   Future<Map<String, dynamic>?> rpcBuyEconomistTurn({
    required String fromUser,
    required String toUser,
    required int cost,
  }) async {
    try {
      final params = {'p_from': fromUser, 'p_to': toUser, 'p_cost': cost};
      debugPrint('GameService.rpcBuyEconomistTurn params: $params');
      final res = await client.rpc('buy_economist_turn', params: params);
      debugPrint('GameService.rpcBuyEconomistTurn raw res: $res');
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      if (res is List && res.isNotEmpty && res[0] is Map) return Map<String, dynamic>.from(res[0] as Map);
      return {'result': res.toString()};
    } on PostgrestException catch (e) {
      _logPostgrestException(e);
      rethrow;
    } catch (e) {
      debugPrint('rpcBuyEconomistTurn error: $e');
      rethrow;
    }
  }
}
