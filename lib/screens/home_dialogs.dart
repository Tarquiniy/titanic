// lib/screens/home_dialogs.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/services/game_service.dart';
import 'package:titanic/services/shared_balance_service.dart';
import 'package:titanic/models/app_user.dart';

/// showInvestInColorDialog: вынес диалог в отдельную функцию.
/// Принимает supabase, userId, onCompleted, showMessage.
Future<void> showInvestInColorDialog({
  required BuildContext context,
  required SupabaseClient supabase,
  required String userId,
  Future<void> Function()? onCompleted,
  required void Function(String) showMessage,
}) async {
  final sharedBalance = SharedBalanceService();
  const colors = ['красный', 'зелёный', 'жёлтый', 'синий', 'малиновый'];

  double mBalance = 0.0;
  try {
    await sharedBalance.normalizeLinkedBalanceForSpend(
      userId: userId,
      balanceKey: 'm_balance',
    );
    final row = await supabase.from('user_credentials').select('m_balance').eq('id', userId).maybeSingle();
    if (row is Map<String, dynamic>) {
      final mb = row['m_balance'];
      if (mb is num) mBalance = mb.toDouble();
      else if (mb is String) mBalance = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
    }
  } catch (_) {}

  String? selectedColor = colors.first;
  final TextEditingController amtCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Вложиться в цвет'),
      content: StatefulBuilder(builder: (ctx2, setStateDialog) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: selectedColor,
            items: colors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setStateDialog(() => selectedColor = v),
            decoration: const InputDecoration(labelText: 'Выберите цвет'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: const InputDecoration(labelText: 'Сумма', hintText: '0', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 14.0),
              child: Text('Майндов'),
            )
          ]),
          const SizedBox(height: 8),
          Text('Ваш баланс: ${mBalance.toStringAsFixed(0)}'),
        ]);
      }),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Вложиться')),
      ],
    ),
  );

  try {
    amtCtrl.dispose();
  } catch (_) {}

  if (confirmed != true) return;

  final raw = amtCtrl.text.trim().replaceAll(',', '.');
  final n = int.tryParse(raw);
  if (n == null || n <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите положительное целое число')));
    return;
  }
  if (n > mBalance.floor()) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Недостаточно майндов')));
    return;
  }
  if (selectedColor == null || selectedColor!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите цвет')));
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Отправка...')));
  try {
    final res = await supabase.rpc('invest_in_color', params: {'p_user': userId, 'p_color': selectedColor, 'p_amount': n});
    await sharedBalance.syncLinkedBalancesForUser(
      userId: userId,
      sourceUserId: userId,
    );
    Map<String, dynamic>? parsed;
    if (res is Map<String, dynamic>) parsed = res;
    else if (res is List && res.isNotEmpty && res[0] is Map) parsed = Map<String, dynamic>.from(res[0]);
    else if (res is String) {
      try {
        parsed = Map<String, dynamic>.from(jsonDecode(res) as Map);
      } catch (_) {
        parsed = null;
      }
    }

    if (parsed != null && (parsed['status'] == 'ok' || parsed['status'] == 'OK')) {
      showMessage('Вложено $n в банк цвета $selectedColor');
      if (onCompleted != null) await onCompleted();
    } else {
      final msg = parsed != null ? (parsed['message'] ?? parsed.toString()) : 'Неожиданный ответ от сервера';
      showMessage('Ошибка: $msg');
    }
  } catch (e) {
    showMessage('Ошибка RPC: $e');
  }
}

/// openBuyTurnFlow вынесен отсюда — вызывайте эту функцию из HomeScreen.
/// Принимает контекст, supabase, svc, currentUser, onRefreshProfile(), showMessage().
Future<void> openBuyTurnFlow({
  required BuildContext context,
  required SupabaseClient supabase,
  required GameService svc,
  required AppUser currentUser,
  required Future<void> Function() onRefreshProfile,
  required void Function(String) showMessage,
}) async {
  List<Map<String, dynamic>> econs = [];
try {
  final res = await supabase
      .from('user_credentials')
      .select('id, first_name, last_name, telegram_username, role')
      // ловим и англ, и рус, и смешанные варианты
      .or('role.ilike.%economist%,role.ilike.%экономист%')
      .order('first_name');

  if (res is List) {
    econs = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
} catch (e) {
  showMessage('Не удалось загрузить список экономистов: $e');
  return;
}

  if (econs.isEmpty) {
    showMessage('Нет доступных экономистов для покупки хода.');
    return;
  }

  final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Поиск экономиста',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (q) {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
                  ],
                ),
              ),
              const Divider(height: 0),
              Expanded(
                child: ListView.separated(
                  itemCount: econs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, index) {
                    final row = econs[index];
                    final first = (row['first_name'] ?? '').toString();
                    final last = (row['last_name'] ?? '').toString();
                    final displayName = ('\$first \$last').trim().isEmpty ? (row['telegram_username'] ?? 'Без имени') : '\$first \$last';
                    return ListTile(
                      title: Text(displayName),
                      onTap: () => Navigator.of(context).pop(row),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (chosen == null) return;

  final first = (chosen['first_name'] ?? '').toString();
  final last = (chosen['last_name'] ?? '').toString();
  final displayName = ('\$first \$last').trim().isEmpty ? (chosen['telegram_username'] ?? 'Без имени') : '\$first \$last';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Купить ход экономисту'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Стоимость: 10 войсов'),
          const SizedBox(height: 8),
          Text('Получатель: \$displayName'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
        ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Купить')),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final rpcRes = await svc.rpcBuyEconomistTurn(fromUser: currentUser.id, toUser: chosen['id'].toString(), cost: 10);
    Navigator.of(context).pop();

    if (rpcRes == null) {
      showMessage('Неожиданный ответ сервера');
      return;
    }

    final status = (rpcRes['status'] ?? rpcRes['result'] ?? '').toString().toLowerCase();
    if (status.contains('ok') || status.contains('success') || status == 'ok') {
      showMessage('Покупка успешна: у экономиста добавлен предмет "Дополнительный ход"');

      // best-effort: refresh profile & journal
      try {
        await onRefreshProfile();
      } catch (_) {}
    } else {
      final msg = rpcRes['message']?.toString() ?? rpcRes.toString();
      showMessage('Ошибка: $msg');
    }
  } catch (e) {
    try {
      Navigator.of(context).pop();
    } catch (_) {}
    showMessage('Ошибка при покупке: $e');
  }
}
