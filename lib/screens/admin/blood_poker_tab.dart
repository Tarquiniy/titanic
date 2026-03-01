import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/theme/app_theme.dart';
import 'package:titanic/widgets/art_deco_button.dart';

class BloodPokerTab extends StatefulWidget {
  const BloodPokerTab({Key? key}) : super(key: key);

  @override
  State<BloodPokerTab> createState() => _BloodPokerTabState();
}

class _BloodPokerTabState extends State<BloodPokerTab> {
  final supabase = Supabase.instance.client;

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [TextEditingController()];
  bool _creating = false;

  List<Map<String, dynamic>> _activeStages = [];
  List<Map<String, dynamic>> _closedStages = [];
  bool _loading = false;
  RealtimeChannel? _stagesChannel;
  Timer? _stagesReloadDebounce;

  @override
  void initState() {
    super.initState();
    _loadStages();
    _subscribeToStagesRealtime();
  }

  @override
  void dispose() {
    _stagesReloadDebounce?.cancel();
    final channel = _stagesChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    for (final ctrl in _optionCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _addOptionField() {
    if (_optionCtrls.length >= 10) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOptionField(int index) {
    if (_optionCtrls.length <= 1) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
    });
  }

  void _scheduleStagesRefresh() {
    _stagesReloadDebounce?.cancel();
    _stagesReloadDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      await _loadStages();
    });
  }

  void _subscribeToStagesRealtime() {
    try {
      _stagesChannel = supabase.channel('admin-blood-poker-live');
      _stagesChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'blood_poker_stages',
            callback: (_) => _scheduleStagesRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'blood_poker_options',
            callback: (_) => _scheduleStagesRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'blood_poker_bets',
            callback: (_) => _scheduleStagesRefresh(),
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _loadStages() async {
    setState(() => _loading = true);
    try {
      final activeRes = await supabase
          .from('blood_poker_stages')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false);

      final closedRes = await supabase
          .from('blood_poker_stages')
          .select()
          .eq('is_closed', true)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _activeStages = (activeRes is List)
            ? activeRes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
        _closedStages = (closedRes is List)
            ? closedRes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      });
    } catch (e) {
      debugPrint('BloodPokerTab._loadStages error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createStage() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showMessage('Введите название этапа');
      return;
    }

    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (options.length < 2) {
      _showMessage('Добавьте хотя бы 2 варианта');
      return;
    }

    setState(() => _creating = true);
    try {
      final existing = await supabase
          .from('blood_poker_stages')
          .select('id')
          .eq('is_closed', false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        _showMessage(
            'Уже есть активный этап покера на крови. Завершите его перед созданием нового.');
        setState(() => _creating = false);
        return;
      }

      final stageRes = await supabase
          .from('blood_poker_stages')
          .insert({
            'title': title,
            'description': _descriptionCtrl.text.trim(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'is_closed': false,
          })
          .select()
          .maybeSingle();

      if (stageRes is! Map<String, dynamic>) {
        throw Exception('Не удалось создать этап');
      }

      final stageId = stageRes['id'] is int
          ? stageRes['id'] as int
          : int.parse(stageRes['id'].toString());

      final optionRows = options.map((label) => ({
            'stage_id': stageId,
            'label': label,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })).toList();

      await supabase.from('blood_poker_options').insert(optionRows);

      _titleCtrl.clear();
      _descriptionCtrl.clear();
      for (final ctrl in _optionCtrls) {
        ctrl.clear();
      }
      while (_optionCtrls.length > 1) {
        _optionCtrls.removeLast().dispose();
      }

      _showMessage('Этап покера на крови создан');
      await _loadStages();
    } catch (e) {
      _showMessage('Ошибка при создании: $e');
    } finally {
      setState(() => _creating = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadOptionsForStage(int stageId) async {
    try {
      final res = await supabase
          .from('blood_poker_options')
          .select('id, label, created_at')
          .eq('stage_id', stageId)
          .order('id', ascending: true);

      return (res is List)
          ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadBetsForStage(int stageId) async {
    try {
      final rawRes = await supabase
          .from('blood_poker_bets')
          .select('id, stage_id, option_id, user_id, amount, created_at')
          .eq('stage_id', stageId)
          .order('amount', ascending: false);

      if (rawRes is! List || rawRes.isEmpty) return [];

      final bets = rawRes
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);

      final userIds = bets
          .map((b) => b['user_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      final optionIds = bets
          .map((b) => b['option_id'] is int
              ? b['option_id'] as int
              : int.tryParse(b['option_id']?.toString() ?? ''))
          .whereType<int>()
          .toSet()
          .toList(growable: false);

      final Map<String, Map<String, dynamic>> usersById = {};
      if (userIds.isNotEmpty) {
        final usersRes = await supabase
            .from('user_credentials')
            .select('id, first_name, last_name, telegram_username, color')
            .inFilter('id', userIds);
        if (usersRes is List) {
          for (final row in usersRes) {
            final user = Map<String, dynamic>.from(row as Map);
            final id = user['id']?.toString();
            if (id != null && id.isNotEmpty) {
              usersById[id] = user;
            }
          }
        }
      }

      final Map<int, Map<String, dynamic>> optionsById = {};
      if (optionIds.isNotEmpty) {
        final optionsRes = await supabase
            .from('blood_poker_options')
            .select('id, label')
            .inFilter('id', optionIds);
        if (optionsRes is List) {
          for (final row in optionsRes) {
            final option = Map<String, dynamic>.from(row as Map);
            final optionId = option['id'] is int
                ? option['id'] as int
                : int.tryParse(option['id']?.toString() ?? '');
            if (optionId != null) {
              optionsById[optionId] = option;
            }
          }
        }
      }

      return bets.map((bet) {
        final userId = bet['user_id']?.toString();
        final optionId = bet['option_id'] is int
            ? bet['option_id'] as int
            : int.tryParse(bet['option_id']?.toString() ?? '');
        return {
          ...bet,
          'user_credentials': userId != null ? (usersById[userId] ?? {}) : {},
          'blood_poker_options':
              optionId != null ? (optionsById[optionId] ?? {}) : {},
        };
      }).toList(growable: false);
    } catch (e) {
      return [];
    }
  }

  Future<void> _closeStage(int stageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Завершить покер на крови?',
          style: TitanicTheme.titleLarge,
        ),
        backgroundColor: TitanicTheme.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: TitanicTheme.raptureGold.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        content: Text(
          'Будут определены 3 победителя по максимальной ставке. '
          'Все майнды будут распределены на счета цветов мафиози.',
          style: TitanicTheme.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final bets = await _loadBetsForStage(stageId);

      int totalMinds = 0;
      final Map<String, Map<String, int>> userStats = {};
      for (final bet in bets) {
        final userId = bet['user_id']?.toString();
        final amount = bet['amount'] is int
            ? bet['amount'] as int
            : int.tryParse(bet['amount'].toString()) ?? 0;
        if (userId == null || amount <= 0) continue;

        totalMinds += amount;
        final stat = userStats.putIfAbsent(
          userId,
          () => {'max_bet': 0, 'total_amount': 0, 'bets_count': 0},
        );
        if (amount > (stat['max_bet'] ?? 0)) {
          stat['max_bet'] = amount;
        }
        stat['total_amount'] = (stat['total_amount'] ?? 0) + amount;
        stat['bets_count'] = (stat['bets_count'] ?? 0) + 1;
      }

      final sortedUsers = userStats.entries.toList()
        ..sort((a, b) {
          final aMax = a.value['max_bet'] ?? 0;
          final bMax = b.value['max_bet'] ?? 0;
          if (aMax != bMax) return bMax.compareTo(aMax);
          final aTotal = a.value['total_amount'] ?? 0;
          final bTotal = b.value['total_amount'] ?? 0;
          return bTotal.compareTo(aTotal);
        });

      final List<Map<String, dynamic>> winners = [];
      for (var i = 0; i < sortedUsers.length && i < 3; i++) {
        final entry = sortedUsers[i];
        final userId = entry.key;
        final stat = entry.value;

        winners.add({
          'user_id': userId,
          'max_bet': stat['max_bet'] ?? 0,
          'total_amount': stat['total_amount'] ?? 0,
          'bets_count': stat['bets_count'] ?? 0,
          'position': i + 1,
        });
      }

      if (bets.isNotEmpty && userStats.isNotEmpty) {
        final userRows = await supabase
            .from('user_credentials')
            .select('id, color')
            .inFilter('id', userStats.keys.toList(growable: false));

        final Map<String, String> colorsByUser = {};
        if (userRows is List) {
          for (final row in userRows) {
            final user = Map<String, dynamic>.from(row as Map);
            final userId = user['id']?.toString();
            final color = user['color']?.toString();
            if (userId != null &&
                userId.isNotEmpty &&
                color != null &&
                color.isNotEmpty) {
              colorsByUser[userId] = color;
            }
          }
        }

        final Map<String, int> colorTotals = {};
        for (final bet in bets) {
          final userId = bet['user_id']?.toString();
          final color = userId == null ? null : colorsByUser[userId];
          if (color == null || color.isEmpty) continue;

          final amount = bet['amount'] is int
              ? bet['amount'] as int
              : int.tryParse(bet['amount'].toString()) ?? 0;
          if (amount <= 0) continue;
          colorTotals[color] = (colorTotals[color] ?? 0) + amount;
        }

        for (final entry in colorTotals.entries) {
          if (entry.value > 0) {
            await _updateColorBank(entry.key, entry.value);
          }
        }
      }

      await supabase
          .from('blood_poker_stages')
          .update({
            'is_closed': true,
            'closed_at': DateTime.now().toUtc().toIso8601String(),
            'winners': winners,
          })
          .eq('id', stageId);

      final actorId = supabase.auth.currentUser?.id;
      if (actorId != null && actorId.isNotEmpty) {
        await supabase.from('user_journal').insert({
          'user_id': actorId,
          'visible_role': 'all',
          'actor_id': actorId,
          'title': 'Покер на крови завершен',
          'message':
              'Этап покера завершен. Определены победители по максимальной ставке. '
              'Все майнды распределены на счета цветов мафиози.',
          'metadata': {
            'stage_id': stageId,
            'winners': winners,
            'type': 'blood_poker_completed'
          },
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        debugPrint(
            'BloodPokerTab._closeStage: skip user_journal insert, current user id is null');
      }

      _showMessage('Покер на крови завершен.');
      await _showCloseResultsDialog(
        stageId: stageId,
        winners: winners,
        betsCount: bets.length,
        totalMinds: totalMinds,
      );
      await _loadStages();
    } catch (e) {
      _showMessage('Ошибка при завершении: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showCloseResultsDialog({
    required int stageId,
    required List<Map<String, dynamic>> winners,
    required int betsCount,
    required int totalMinds,
  }) async {
    if (!mounted) return;

    final userIds = winners
        .map((w) => w['user_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final Map<String, String> namesByUser = {};
    if (userIds.isNotEmpty) {
      try {
        final users = await supabase
            .from('user_credentials')
            .select('id, first_name, last_name, telegram_username')
            .inFilter('id', userIds);
        if (users is List) {
          for (final row in users) {
            final user = Map<String, dynamic>.from(row as Map);
            final id = user['id']?.toString();
            if (id == null || id.isEmpty) continue;
            final fullName =
                '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
            namesByUser[id] = fullName.isNotEmpty
                ? fullName
                : (user['telegram_username']?.toString() ?? id);
          }
        }
      } catch (_) {}
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Результаты покера',
          style: TitanicTheme.titleLarge,
        ),
        backgroundColor: TitanicTheme.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: TitanicTheme.raptureGold.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Этап ID: $stageId', style: TitanicTheme.body),
                Text('Ставок: $betsCount', style: TitanicTheme.body),
                Text(
                  'Распределено майндов: $totalMinds M',
                  style: TitanicTheme.body,
                ),
                const SizedBox(height: 12),
                if (winners.isEmpty)
                  Text('Ставок не было.', style: TitanicTheme.body)
                else
                  ...winners.map((w) {
                    final uid = w['user_id']?.toString() ?? '';
                    final display = namesByUser[uid] ?? uid;
                    final position = w['position'] ?? 0;
                    final maxBet = w['max_bet'] ?? 0;
                    final total = w['total_amount'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '$position. $display - макс. ставка: $maxBet M, всего: $total M',
                        style: TitanicTheme.body,
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateColorBank(String color, int amount) async {
    try {
      final existing = await supabase
          .from('color_banks')
          .select('balance')
          .eq('color', color)
          .maybeSingle();

      if (existing is Map<String, dynamic>) {
        final currentBalance = existing['balance'] is num
            ? (existing['balance'] as num).toDouble()
            : 0.0;
        await supabase
            .from('color_banks')
            .update({'balance': currentBalance + amount})
            .eq('color', color);
      } else {
        await supabase
            .from('color_banks')
            .insert({'color': color, 'balance': amount});
      }

      await supabase.from('color_bank_history').insert({
        'color': color,
        'amount': amount,
        'comment': 'Покер на крови - распределение майндов',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error updating color bank: $e');
    }
  }

  Future<void> _showStageDetails(Map<String, dynamic> stage) async {
    final stageId = stage['id'] is int
        ? stage['id'] as int
        : int.tryParse(stage['id'].toString());
    if (stageId == null) return;

    final options = await _loadOptionsForStage(stageId);
    final bets = await _loadBetsForStage(stageId);

    final Map<String, List<Map<String, dynamic>>> betsByUser = {};
    for (final bet in bets) {
      final userId = bet['user_id']?.toString();
      if (userId != null) {
        betsByUser.putIfAbsent(userId, () => []);
        betsByUser[userId]!.add(bet);
      }
    }

    final Map<int, List<Map<String, dynamic>>> betsByOption = {};
    for (final bet in bets) {
      final optionId = bet['option_id'] is int
          ? bet['option_id'] as int
          : int.tryParse(bet['option_id'].toString());
      if (optionId != null) {
        betsByOption.putIfAbsent(optionId, () => []);
        betsByOption[optionId]!.add(bet);
      }
    }

    final Map<String, int> userTotalAmounts = {};
    for (final entry in betsByUser.entries) {
      final total = entry.value.fold<int>(0, (sum, bet) {
        final amount = bet['amount'] is int
            ? bet['amount'] as int
            : int.tryParse(bet['amount'].toString()) ?? 0;
        return sum + amount;
      });
      userTotalAmounts[entry.key] = total;
    }

    final sortedUserIds = userTotalAmounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          stage['title']?.toString() ?? 'Детали',
          style: TitanicTheme.titleLarge,
        ),
        backgroundColor: TitanicTheme.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: TitanicTheme.raptureGold.withOpacity(0.4),
            width: 1.5,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Описание: ${stage['description'] ?? '—'}',
                  style: TitanicTheme.body,
                ),
                const SizedBox(height: 8),
                Text(
                  'Создан: ${stage['created_at']}',
                  style: TitanicTheme.body,
                ),
                if (stage['is_closed'] == true)
                  Text(
                    'Завершен: ${stage['closed_at']}',
                    style: TitanicTheme.body,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Статистика по пользователям:',
                  style: TitanicTheme.subtitle,
                ),
                ...sortedUserIds.take(10).map((entry) {
                  final userId = entry.key;
                  final totalAmount = entry.value;
                  final userBets = betsByUser[userId] ?? [];
                  final user = userBets.isNotEmpty &&
                          userBets[0]['user_credentials'] is Map
                      ? Map<String, dynamic>.from(
                          userBets[0]['user_credentials'] as Map)
                      : {};

                  final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                      .trim();
                  final displayName = name.isNotEmpty
                      ? name
                      : (user['telegram_username'] ?? 'Unknown');
                  final color = user['color']?.toString() ?? '—';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: TitanicTheme.surfaceNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: TitanicTheme.raptureGold.withOpacity(0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$displayName (цвет: $color)',
                            style: TitanicTheme.subtitle.copyWith(fontSize: 14),
                          ),
                          Text(
                            'Всего ставок: ${userBets.length}, Общая сумма: $totalAmount M',
                            style: TitanicTheme.body,
                          ),
                          ...userBets.map((bet) {
                            final optionInfo = bet['blood_poker_options'] is Map
                                ? Map<String, dynamic>.from(
                                    bet['blood_poker_options'] as Map)
                                : {};
                            final optionLabel =
                                optionInfo['label']?.toString() ?? '—';
                            final amount = bet['amount']?.toString() ?? '0';

                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 4),
                              child: Text(
                                '• $optionLabel: $amount M',
                                style: TitanicTheme.body.copyWith(fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                Text(
                  'Варианты ставок:',
                  style: TitanicTheme.subtitle,
                ),
                ...options.map((option) {
                  final optionId = option['id'] is int
                      ? option['id'] as int
                      : int.tryParse(option['id'].toString());
                  final optionBets = optionId != null
                      ? betsByOption[optionId] ?? []
                      : [];
                  final totalForOption = optionBets.fold<int>(
                      0, (sum, bet) {
                    final amount = bet['amount'] is int
                        ? bet['amount'] as int
                        : int.tryParse(bet['amount'].toString()) ?? 0;
                    return sum + amount;
                  });

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: TitanicTheme.surfaceNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: TitanicTheme.raptureGold.withOpacity(0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${option['label']} (всего ставок: ${optionBets.length}, сумма: $totalForOption M)',
                            style: TitanicTheme.subtitle.copyWith(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                if (sortedUserIds.isNotEmpty) ...[
                  Text(
                    'Топ игроков по общей сумме ставок:',
                    style: TitanicTheme.subtitle,
                  ),
                  ...sortedUserIds.take(3).map((entry) {
                    final userId = entry.key;
                    final totalAmount = entry.value;
                    final userBets = betsByUser[userId] ?? [];
                    final user = userBets.isNotEmpty &&
                            userBets[0]['user_credentials'] is Map
                        ? Map<String, dynamic>.from(
                            userBets[0]['user_credentials'] as Map)
                        : {};

                    final name =
                        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'
                            .trim();
                    final displayName = name.isNotEmpty
                        ? name
                        : (user['telegram_username'] ?? 'Unknown');
                    final color = user['color']?.toString() ?? '—';

                    final position = sortedUserIds.indexOf(entry) + 1;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '$position. $displayName: $totalAmount M (цвет: $color, ставок: ${userBets.length})',
                        style: TitanicTheme.body,
                      ),
                    );
                  }).toList(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: TitanicTheme.copperDetail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return RefreshIndicator(
      onRefresh: _loadStages,
      color: TitanicTheme.raptureGold,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isSmall ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: TitanicTheme.raptureGold.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Создать новый этап покера на крови',
                      style: TitanicTheme.titleLarge.copyWith(
                        fontSize: isSmall ? 18 : 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleCtrl,
                      decoration: TitanicTheme.inputDecoration.copyWith(
                        labelText: 'Название этапа',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionCtrl,
                      decoration: TitanicTheme.inputDecoration.copyWith(
                        labelText: 'Описание (необязательно)',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Варианты ставок (минимум 2):',
                      style: TitanicTheme.subtitle,
                    ),
                    const SizedBox(height: 12),
                    ..._optionCtrls.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctrl,
                                decoration:
                                    TitanicTheme.inputDecoration.copyWith(
                                  labelText: 'Вариант ${idx + 1}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_optionCtrls.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove),
                                color: TitanicTheme.copperDetail,
                                iconSize: isSmall ? 22 : 26,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                onPressed: () => _removeOptionField(idx),
                                tooltip: 'Удалить вариант',
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ArtDecoButton(
                          text: 'Добавить вариант',
                          icon: Icons.add,
                          onPressed: _addOptionField,
                          primary: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ArtDecoButton(
                      text: 'Создать этап',
                      onPressed: _creating ? null : _createStage,
                      loading: _creating,
                      primary: true,
                      expanded: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: TitanicTheme.seaFoamGreen.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Активные этапы',
                      style: TitanicTheme.titleLarge.copyWith(
                        fontSize: isSmall ? 18 : 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _activeStages.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет активных этапов',
                                  style: TitanicTheme.body,
                                ),
                              )
                            : Column(
                                children: _activeStages.map((stage) {
                                  final stageId = stage['id'] is int
                                      ? stage['id'] as int
                                      : int.parse(stage['id'].toString());
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: TitanicTheme.raptureGold
                                            .withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: isSmall ? 12 : 16,
                                        vertical: 8,
                                      ),
                                      title: Text(
                                        stage['title']?.toString() ?? '—',
                                        style: TitanicTheme.subtitle,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (stage['description'] != null)
                                            Text(
                                              '${stage['description']}',
                                              style: TitanicTheme.body,
                                            ),
                                          Text(
                                            'Создан: ${stage['created_at']}',
                                            style: TitanicTheme.body.copyWith(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility),
                                            color: TitanicTheme.seaFoamGreen,
                                            iconSize: isSmall ? 22 : 26,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 44,
                                              minHeight: 44,
                                            ),
                                            onPressed: () =>
                                                _showStageDetails(stage),
                                            tooltip: 'Детали',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.done_all),
                                            color: Colors.redAccent,
                                            iconSize: isSmall ? 22 : 26,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 44,
                                              minHeight: 44,
                                            ),
                                            onPressed: () =>
                                                _closeStage(stageId),
                                            tooltip: 'Завершить',
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: TitanicTheme.copperDetail.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmall ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Завершенные этапы',
                      style: TitanicTheme.titleLarge.copyWith(
                        fontSize: isSmall ? 18 : 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _closedStages.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет завершенных этапов',
                                  style: TitanicTheme.body,
                                ),
                              )
                            : Column(
                                children: _closedStages.map((stage) {
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: TitanicTheme.raptureGold
                                            .withOpacity(0.1),
                                        width: 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: isSmall ? 12 : 16,
                                        vertical: 8,
                                      ),
                                      title: Text(
                                        stage['title']?.toString() ?? '—',
                                        style: TitanicTheme.subtitle,
                                      ),
                                      subtitle: Text(
                                        'Завершен: ${stage['closed_at']}',
                                        style: TitanicTheme.body.copyWith(
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.visibility),
                                        color: TitanicTheme.seaFoamGreen,
                                        iconSize: isSmall ? 22 : 26,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 44,
                                          minHeight: 44,
                                        ),
                                        onPressed: () =>
                                            _showStageDetails(stage),
                                        tooltip: 'Детали',
                                      ),
                                      onTap: () => _showStageDetails(stage),
                                    ),
                                  );
                                }).toList(),
                              ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
