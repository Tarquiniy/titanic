// lib/screens/home_dialogs.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:titanic/models/app_user.dart';
import 'package:titanic/services/game_service.dart';

/// showInvestInColorDialog: вынес диалог в отдельную функцию.
/// Принимает supabase, userId, onCompleted, showMessage.
Future<void> showInvestInColorDialog({
  required BuildContext context,
  required SupabaseClient supabase,
  required String userId,
  Future<void> Function()? onCompleted,
  required void Function(String) showMessage,
}) async {
  const colors = ['красный', 'зелёный', 'жёлтый', 'синий', 'малиновый'];

  double mBalance = 0.0;
  double vBalance = 0.0;
  try {
    final row = await supabase
        .from('user_credentials')
        .select('m_balance, v_balance')
        .eq('id', userId)
        .maybeSingle();
    if (row is Map<String, dynamic>) {
      final mb = row['m_balance'];
      if (mb is num) {
        mBalance = mb.toDouble();
      } else if (mb is String) {
        mBalance = double.tryParse(mb.replaceAll(',', '.')) ?? 0.0;
      }

      final vb = row['v_balance'];
      if (vb is num) {
        vBalance = vb.toDouble();
      } else if (vb is String) {
        vBalance = double.tryParse(vb.replaceAll(',', '.')) ?? 0.0;
      }
    }
  } catch (_) {}

  String? selectedColor = colors.first;
  final mindsCtrl = TextEditingController();
  final voicesCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Вложиться в цвет'),
      content: StatefulBuilder(
        builder: (ctx2, setStateDialog) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedColor,
                items: colors
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedColor = v),
                decoration: const InputDecoration(labelText: 'Выберите цвет'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: mindsCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      decoration: const InputDecoration(
                        labelText: 'Майнды',
                        hintText: '0',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 14.0),
                    child: Text('M'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: voicesCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: false),
                      decoration: const InputDecoration(
                        labelText: 'Войсы',
                        hintText: '0',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 14.0),
                    child: Text('V'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Ваш баланс: ${mBalance.toStringAsFixed(0)} M, ${vBalance.toStringAsFixed(0)} V',
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Вложиться'),
        ),
      ],
    ),
  );

  final minds = int.tryParse(mindsCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  final voices = int.tryParse(voicesCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  mindsCtrl.dispose();
  voicesCtrl.dispose();

  if (confirmed != true) return;

  if (minds <= 0 && voices <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Введите количество майндов, войсов или оба значения'),
      ),
    );
    return;
  }
  if (minds > mBalance.floor()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Недостаточно майндов')),
    );
    return;
  }
  if (voices > vBalance.floor()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Недостаточно войсов')),
    );
    return;
  }
  if (selectedColor == null || selectedColor!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Выберите цвет')),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Отправка...')),
  );

  try {
    final res = await supabase.rpc('invest_in_color', params: {
      'p_user': userId,
      'p_color': selectedColor,
      'p_m_amount': minds,
      'p_v_amount': voices,
    });

    final parsed = res is Map<String, dynamic>
        ? res
        : (res is List && res.isNotEmpty && res.first is Map
            ? Map<String, dynamic>.from(res.first as Map)
            : null);

    if (parsed != null && (parsed['status'] == 'ok' || parsed['status'] == 'OK')) {
      final parts = <String>[];
      final addedM = parsed['added_m'];
      final addedV = parsed['added_v'];
      if (addedM is num && addedM > 0) {
        parts.add('${addedM.toInt()} M');
      }
      if (addedV is num && addedV > 0) {
        parts.add('${addedV.toInt()} V');
      }
      final investedText = parts.isEmpty ? '0' : parts.join(' и ');
      showMessage('Вложено $investedText в банк цвета $selectedColor');
      if (onCompleted != null) {
        await onCompleted();
      }
    } else {
      final msg = parsed != null
          ? (parsed['message'] ?? parsed.toString()).toString()
          : 'Неожиданный ответ от сервера';
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
        .or('role.ilike.%economist%,role.ilike.%СЌРєРѕРЅРѕРјРёСЃС‚%')
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

  final Map<String, dynamic>? chosen =
      await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
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
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Отмена'),
                    ),
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
                    final displayName = ('$first $last').trim().isEmpty
                        ? (row['telegram_username'] ?? 'Без имени')
                        : '$first $last';
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
  final displayName = ('$first $last').trim().isEmpty
      ? (chosen['telegram_username'] ?? 'Без имени')
      : '$first $last';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Купить ход экономисту'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Стоимость: 10 войсов'),
          const SizedBox(height: 8),
          Text('Получатель: $displayName'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Купить'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final rpcRes = await svc.rpcBuyEconomistTurn(
      fromUser: currentUser.id,
      toUser: chosen['id'].toString(),
      cost: 10,
    );
    Navigator.of(context).pop();

    if (rpcRes == null) {
      showMessage('Неожиданный ответ сервера');
      return;
    }

    final status = (rpcRes['status'] ?? rpcRes['result'] ?? '')
        .toString()
        .toLowerCase();
    if (status.contains('ok') || status.contains('success') || status == 'ok') {
      showMessage(
        'Покупка успешна: у экономиста добавлен предмет "Дополнительный ход"',
      );

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
