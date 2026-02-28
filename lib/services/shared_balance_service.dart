import 'package:supabase_flutter/supabase_flutter.dart';

class SharedBalanceService {
  SharedBalanceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String firstUsername = 'vernon_eger';
  static const String secondUsername = 'erna_valter';

  static const Set<String> _linkedUsernames = {
    firstUsername,
    secondUsername,
  };

  String _normalize(dynamic value) => value?.toString().trim().toLowerCase() ?? '';

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  bool isLinkedUsername(String? username) =>
      _linkedUsernames.contains(_normalize(username));

  Future<Map<String, dynamic>?> _fetchUserById(
    String userId, {
    String columns = 'id, telegram_username, v_balance, m_balance',
  }) async {
    final row = await _client
        .from('user_credentials')
        .select(columns)
        .eq('id', userId)
        .maybeSingle();
    if (row is Map<String, dynamic>) return row;
    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchLinkedRows({
    String columns = 'id, telegram_username, v_balance, m_balance',
  }) async {
    final rows = await _client
        .from('user_credentials')
        .select(columns)
        .or(
          'telegram_username.eq.$firstUsername,telegram_username.eq.$secondUsername',
        );
    if (rows is! List) return const [];
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>?> _resolveAnchor({
    String? userId,
    String? username,
    String columns = 'id, telegram_username, v_balance, m_balance',
  }) async {
    if (userId != null && userId.isNotEmpty) {
      return _fetchUserById(userId, columns: columns);
    }
    if (username != null && username.isNotEmpty && isLinkedUsername(username)) {
      final rows = await _fetchLinkedRows(columns: columns);
      for (final row in rows) {
        if (_normalize(row['telegram_username']) == _normalize(username)) {
          return row;
        }
      }
    }
    return null;
  }

  Future<double?> normalizeLinkedBalanceForSpend({
    required String userId,
    required String balanceKey,
  }) async {
    if (balanceKey != 'v_balance' && balanceKey != 'm_balance') {
      throw ArgumentError.value(balanceKey, 'balanceKey');
    }

    final anchor = await _resolveAnchor(userId: userId);
    if (anchor == null || !isLinkedUsername(anchor['telegram_username']?.toString())) {
      return null;
    }

    final rows = await _fetchLinkedRows();
    if (rows.length < 2) return _toDouble(anchor[balanceKey]);

    double? target;
    for (final row in rows) {
      final value = _toDouble(row[balanceKey]);
      target = target == null ? value : (value < target ? value : target);
    }

    if (target == null) return null;

    for (final row in rows) {
      final current = _toDouble(row[balanceKey]);
      if ((current - target).abs() < 0.0001) continue;
      await _client
          .from('user_credentials')
          .update({balanceKey: target})
          .eq('id', row['id'].toString());
    }

    return target;
  }

  Future<Map<String, dynamic>?> syncLinkedBalancesForUser({
    String? userId,
    String? username,
    String? sourceUserId,
    String? sourceUsername,
  }) async {
    final anchor = await _resolveAnchor(userId: userId, username: username);
    if (anchor == null || !isLinkedUsername(anchor['telegram_username']?.toString())) {
      return anchor;
    }

    final rows = await _fetchLinkedRows();
    if (rows.isEmpty) return anchor;

    Map<String, dynamic>? source;
    if (sourceUserId != null && sourceUserId.isNotEmpty) {
      for (final row in rows) {
        if (row['id']?.toString() == sourceUserId) {
          source = row;
          break;
        }
      }
    }
    if (source == null && sourceUsername != null && sourceUsername.isNotEmpty) {
      for (final row in rows) {
        if (_normalize(row['telegram_username']) == _normalize(sourceUsername)) {
          source = row;
          break;
        }
      }
    }
    source ??= anchor;

    final targetV = _toDouble(source['v_balance']);
    final targetM = _toDouble(source['m_balance']);

    for (final row in rows) {
      final currentV = _toDouble(row['v_balance']);
      final currentM = _toDouble(row['m_balance']);
      if ((currentV - targetV).abs() < 0.0001 &&
          (currentM - targetM).abs() < 0.0001) {
        continue;
      }

      await _client.from('user_credentials').update({
        'v_balance': targetV,
        'm_balance': targetM,
      }).eq('id', row['id'].toString());
    }

    return {
      ...source,
      'v_balance': targetV,
      'm_balance': targetM,
    };
  }
}
