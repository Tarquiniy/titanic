// lib/screens/admin/blood_poker_tab.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BloodPokerTab extends StatefulWidget {
  const BloodPokerTab({Key? key}) : super(key: key);

  @override
  State<BloodPokerTab> createState() => _BloodPokerTabState();
}

class _BloodPokerTabState extends State<BloodPokerTab> {
  final supabase = Supabase.instance.client;

  // Для создания нового этапа
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [TextEditingController()];
  bool _creating = false;

  // Списки этапов
  List<Map<String, dynamic>> _activeStages = [];
  List<Map<String, dynamic>> _closedStages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStages();
  }

  @override
  void dispose() {
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

  Future<void> _loadStages() async {
    setState(() => _loading = true);
    try {
      // Загружаем активные этапы
      final activeRes = await supabase
          .from('blood_poker_stages')
          .select()
          .eq('is_closed', false)
          .order('created_at', ascending: false);

      // Загружаем завершенные этапы
      final closedRes = await supabase
          .from('blood_poker_stages')
          .select()
          .eq('is_closed', true)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _activeStages = (activeRes is List) ? activeRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
        _closedStages = (closedRes is List) ? closedRes.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
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

    final options = _optionCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (options.length < 2) {
      _showMessage('Добавьте хотя бы 2 варианта');
      return;
    }

    setState(() => _creating = true);
    try {
      // Проверяем, нет ли уже активного этапа
      final existing = await supabase
          .from('blood_poker_stages')
          .select('id')
          .eq('is_closed', false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        _showMessage('Уже есть активный этап покера на крови. Завершите его перед созданием нового.');
        setState(() => _creating = false);
        return;
      }

      // Создаем новый этап
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

      final stageId = stageRes['id'] is int ? stageRes['id'] as int : int.parse(stageRes['id'].toString());

      // Создаем варианты
      final optionRows = options.map((label) => ({
        'stage_id': stageId,
        'label': label,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      })).toList();

      await supabase.from('blood_poker_options').insert(optionRows);

      // Очищаем форму
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
          .order('id');

      return (res is List) ? res.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadBetsForStage(int stageId) async {
    try {
      final res = await supabase
          .from('blood_poker_bets')
          .select('''
            *,
            user_credentials:user_id(first_name, last_name, telegram_username, color),
            blood_poker_options:option_id(label)
          ''')
          .eq('stage_id', stageId)
          .order('amount', ascending: false);

      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> _closeStage(int stageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить покер на крови?'),
        content: const Text('После завершения будут определены 3 победителя с наибольшими ставками. Все майнды будут распределены на счета цветов мафиози.'),
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
      // 1. Получаем все ставки для этого этапа
      final bets = await _loadBetsForStage(stageId);

      if (bets.isEmpty) {
        _showMessage('Нет ставок для этого этапа');
        setState(() => _loading = false);
        return;
      }

      // 2. Группируем ставки по пользователям для подсчета общей суммы
      final Map<String, int> userTotalBets = {};
      for (final bet in bets) {
        final userId = bet['user_id']?.toString();
        final amount = bet['amount'] is int ? bet['amount'] as int : int.tryParse(bet['amount'].toString()) ?? 0;
        
        if (userId != null) {
          userTotalBets[userId] = (userTotalBets[userId] ?? 0) + amount;
        }
      }

      // 3. Сортируем пользователей по общей сумме ставок
      final sortedUsers = userTotalBets.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // 4. Определяем 3 победителей (или меньше, если ставок меньше)
      final List<Map<String, dynamic>> winners = [];
      for (var i = 0; i < sortedUsers.length && i < 3; i++) {
        final entry = sortedUsers[i];
        final userId = entry.key;
        final totalAmount = entry.value;
        
        // Находим все ставки этого пользователя
        final userBets = bets.where((bet) => bet['user_id']?.toString() == userId).toList();
        
        winners.add({
          'user_id': userId,
          'total_amount': totalAmount,
          'bets_count': userBets.length,
          'position': i + 1
        });
      }

      // 5. Распределяем майнды на счета цветов мафиози
      // Для каждой ставки получаем цвет мафиози и добавляем майнды в банк цвета
      for (final bet in bets) {
        final userId = bet['user_id']?.toString();
        final amount = bet['amount'] is int ? bet['amount'] as int : int.tryParse(bet['amount'].toString()) ?? 0;

        if (userId == null || amount <= 0) continue;

        // Получаем цвет мафиози
        final userRes = await supabase
            .from('user_credentials')
            .select('color')
            .eq('id', userId)
            .maybeSingle();

        if (userRes is Map<String, dynamic>) {
          final color = userRes['color']?.toString();
          if (color != null && color.isNotEmpty) {
            // Обновляем банк цвета
            await _updateColorBank(color, amount);
          }
        }
      }

      // 6. Обновляем этап - помечаем как завершенный
      await supabase
          .from('blood_poker_stages')
          .update({
            'is_closed': true,
            'closed_at': DateTime.now().toUtc().toIso8601String(),
            'winners': winners, // Сохраняем информацию о победителях
          })
          .eq('id', stageId);

      // 7. Добавляем запись в журнал
      await supabase.from('user_journal').insert({
        'user_id': 'system',
        'visible_role': 'all',
        'actor_id': 'system',
        'title': 'Покер на крови завершен',
        'message': 'Этап покера завершен. Определены победители по общей сумме ставок. Все майнды распределены на счета цветов мафиози.',
        'metadata': {
          'stage_id': stageId,
          'winners': winners,
          'type': 'blood_poker_completed'
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showMessage('Покер на крови завершен. Определены победители по общей сумме ставок. Майнды распределены.');
      await _loadStages();
    } catch (e) {
      _showMessage('Ошибка при завершении: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateColorBank(String color, int amount) async {
    try {
      // Проверяем, существует ли запись для этого цвета
      final existing = await supabase
          .from('color_banks')
          .select('balance')
          .eq('color', color)
          .maybeSingle();

      if (existing is Map<String, dynamic>) {
        // Обновляем существующую запись
        final currentBalance = existing['balance'] is num ? (existing['balance'] as num).toDouble() : 0.0;
        await supabase
            .from('color_banks')
            .update({'balance': currentBalance + amount})
            .eq('color', color);
      } else {
        // Создаем новую запись
        await supabase
            .from('color_banks')
            .insert({'color': color, 'balance': amount});
      }

      // Добавляем запись в историю банка цвета
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
    final stageId = stage['id'] is int ? stage['id'] as int : int.tryParse(stage['id'].toString());
    if (stageId == null) return;

    final options = await _loadOptionsForStage(stageId);
    final bets = await _loadBetsForStage(stageId);

    // Группируем ставки по пользователям
    final Map<String, List<Map<String, dynamic>>> betsByUser = {};
    for (final bet in bets) {
      final userId = bet['user_id']?.toString();
      if (userId != null) {
        betsByUser.putIfAbsent(userId, () => []);
        betsByUser[userId]!.add(bet);
      }
    }

    // Группируем ставки по вариантам для отображения
    final Map<int, List<Map<String, dynamic>>> betsByOption = {};
    for (final bet in bets) {
      final optionId = bet['option_id'] is int ? bet['option_id'] as int : int.tryParse(bet['option_id'].toString());
      if (optionId != null) {
        betsByOption.putIfAbsent(optionId, () => []);
        betsByOption[optionId]!.add(bet);
      }
    }

    // Подсчитываем общую сумму по каждому пользователю
    final Map<String, int> userTotalAmounts = {};
    for (final entry in betsByUser.entries) {
      final total = entry.value.fold<int>(0, (sum, bet) {
        final amount = bet['amount'] is int ? bet['amount'] as int : int.tryParse(bet['amount'].toString()) ?? 0;
        return sum + amount;
      });
      userTotalAmounts[entry.key] = total;
    }

    // Сортируем пользователей по общей сумме ставок
    final sortedUserIds = userTotalAmounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(stage['title']?.toString() ?? 'Детали'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Описание: ${stage['description'] ?? '—'}'),
                const SizedBox(height: 8),
                Text('Создан: ${stage['created_at']}'),
                if (stage['is_closed'] == true)
                  Text('Завершен: ${stage['closed_at']}'),

                const SizedBox(height: 16),
                const Text('Статистика по пользователям:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...sortedUserIds.take(10).map((entry) {
                  final userId = entry.key;
                  final totalAmount = entry.value;
                  final userBets = betsByUser[userId] ?? [];
                  final user = userBets.isNotEmpty && userBets[0]['user_credentials'] is Map
                      ? Map<String, dynamic>.from(userBets[0]['user_credentials'] as Map)
                      : {};
                  
                  final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                  final displayName = name.isNotEmpty ? name : (user['telegram_username'] ?? 'Unknown');
                  final color = user['color']?.toString() ?? '—';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$displayName (цвет: $color)',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Всего ставок: ${userBets.length}, Общая сумма: $totalAmount M'),
                          
                          // Детали ставок пользователя
                          ...userBets.map((bet) {
                            final optionInfo = bet['blood_poker_options'] is Map ?
                              Map<String, dynamic>.from(bet['blood_poker_options'] as Map) : {};
                            final optionLabel = optionInfo['label']?.toString() ?? '—';
                            final amount = bet['amount']?.toString() ?? '0';
                            
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 4),
                              child: Text('• $optionLabel: $amount M'),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 16),
                const Text('Варианты ставок:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...options.map((option) {
                  final optionId = option['id'] is int ? option['id'] as int : int.tryParse(option['id'].toString());
                  final optionBets = optionId != null ? betsByOption[optionId] ?? [] : [];
                  final totalForOption = optionBets.fold<int>(0, (sum, bet) {
                    final amount = bet['amount'] is int ? bet['amount'] as int : int.tryParse(bet['amount'].toString()) ?? 0;
                    return sum + amount;
                  });

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${option['label']} (всего ставок: ${optionBets.length}, сумма: $totalForOption M)',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 16),
                if (sortedUserIds.isNotEmpty) ...[
                  const Text('Топ игроков по общей сумме ставок:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...sortedUserIds.take(3).map((entry) {
                    final userId = entry.key;
                    final totalAmount = entry.value;
                    final userBets = betsByUser[userId] ?? [];
                    final user = userBets.isNotEmpty && userBets[0]['user_credentials'] is Map
                        ? Map<String, dynamic>.from(userBets[0]['user_credentials'] as Map)
                        : {};
                    
                    final name = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                    final displayName = name.isNotEmpty ? name : (user['telegram_username'] ?? 'Unknown');
                    final color = user['color']?.toString() ?? '—';

                    final position = sortedUserIds.indexOf(entry) + 1;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('$position. $displayName: $totalAmount M (цвет: $color, ставок: ${userBets.length})'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStages,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Создание нового этапа
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Создать новый этап покера на крови',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Название этапа',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Описание (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    const Text('Варианты ставок (минимум 2):', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),

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
                                decoration: InputDecoration(
                                  labelText: 'Вариант ${idx + 1}',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_optionCtrls.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove, color: Colors.red),
                                onPressed: () => _removeOptionField(idx),
                                tooltip: 'Удалить вариант',
                              ),
                          ],
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _addOptionField,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить вариант'),
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _createStage,
                        child: _creating
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Создать этап'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Активные этапы
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Активные этапы',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _activeStages.isEmpty
                            ? const Text('Нет активных этапов')
                            : Column(
                                children: _activeStages.map((stage) {
                                  final stageId = stage['id'] is int ? stage['id'] as int : int.parse(stage['id'].toString());
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(stage['title']?.toString() ?? '—'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (stage['description'] != null)
                                            Text('${stage['description']}'),
                                          Text('Создан: ${stage['created_at']}'),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility),
                                            onPressed: () => _showStageDetails(stage),
                                            tooltip: 'Детали',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.done_all, color: Colors.red),
                                            onPressed: () => _closeStage(stageId),
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

            // Завершенные этапы
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Завершенные этапы',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _closedStages.isEmpty
                            ? const Text('Нет завершенных этапов')
                            : Column(
                                children: _closedStages.map((stage) {
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(stage['title']?.toString() ?? '—'),
                                      subtitle: Text('Завершен: ${stage['closed_at']}'),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.visibility),
                                        onPressed: () => _showStageDetails(stage),
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