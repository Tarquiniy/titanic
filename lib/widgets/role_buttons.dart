// Изменённый файл: lib/widgets/role_buttons.dart
// + Добавлен callback onInventoryItemAdded для мгновенного клиентского апдейта инвентаря

// lib/widgets/role_buttons.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../blocks/politician_block.dart';
import '../blocks/economist_block.dart';
import '../blocks/hollywood_block.dart';
import '../blocks/mafia_block.dart';
import '../blocks/journalist_block.dart';
import '../blocks/public_figure_block.dart';
import '../blocks/admin_block.dart';
import '../services/game_service.dart';

class RoleButtons extends StatefulWidget {
  final AppUser user;
  final bool isListenEnabled;
  final VoidCallback onListenPressed;
  final bool isSpeechEnabled;
  final bool speechActive;
  final DateTime? speechExpiresAt;
  final String? speechActorId;
  final Future<void> Function()? onStartSpeech;
  final VoidCallback onOpenTransfer;
  final Future<void> Function()? onRefreshProfile;
  /// NEW: callback for immediate client-side inventory update
  final Future<void> Function(Map<String, dynamic> item)? onInventoryItemAdded;

  const RoleButtons({
    super.key,
    required this.user,
    required this.isListenEnabled,
    required this.onListenPressed,
    required this.isSpeechEnabled,
    required this.speechActive,
    required this.speechExpiresAt,
    required this.speechActorId,
    this.onStartSpeech,
    required this.onOpenTransfer,
    this.onRefreshProfile,
    this.onInventoryItemAdded,
  });

  @override
  State<RoleButtons> createState() => _RoleButtonsState();
}

class _RoleButtonsState extends State<RoleButtons> {
  final supabase = Supabase.instance.client;
  final GameService _svc = GameService();

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openBuyTurnFlow() async {
    List<Map<String, dynamic>> econs = [];
    try {
      final res = await supabase
          .from('user_credentials')
          .select('id, first_name, last_name, telegram_username')
          .eq('role', 'economist')
          .neq('id', widget.user.id)
          .order('first_name');
      if (res is List) {
        econs = res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      _showSnack('Не удалось загрузить список экономистов: $e');
      return;
    }

    if (econs.isEmpty) {
      _showSnack('Нет доступных экономистов для покупки хода.');
      return;
    }

    final Map<String, dynamic>? chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _EconomistPickerSheet(economists: econs);
      },
    );

    if (chosen == null) return;

    final first = (chosen['first_name'] ?? '').toString();
    final last = (chosen['last_name'] ?? '').toString();
    final displayName = ('$first $last').trim().isEmpty ? (chosen['telegram_username'] ?? 'Без имени') : '$first $last';

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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Купить')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

      final rpcRes = await _svc.rpcBuyEconomistTurn(
        fromUser: widget.user.id,
        toUser: chosen['id'].toString(),
        cost: 10,
      );

      Navigator.of(context).pop();

      if (rpcRes == null) {
        _showSnack('Неожиданный ответ сервера');
        return;
      }

      final status = (rpcRes['status'] ?? rpcRes['result'] ?? '').toString().toLowerCase();
      if (status.contains('ok') || status.contains('success') || status == 'ok') {
        _showSnack('Покупка успешна: у экономиста добавлен предмет "Дополнительный ход"');

        // CLIENT-SIDE IMMEDIATE UPDATE: construct a minimal inventory item
        final Map<String, dynamic> item = {
          'id': rpcRes['item_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'owner_id': chosen['id']?.toString() ?? chosen['id'].toString(),
          'name': rpcRes['item_name'] ?? 'Дополнительный ход',
          'metadata': rpcRes['item_meta'] ?? {'from': widget.user.id, 'cost': 10},
          'created_at': rpcRes['created_at'] ?? DateTime.now().toIso8601String(),
        };

        try {
          if (widget.onInventoryItemAdded != null) {
            await widget.onInventoryItemAdded!(item);
          }
        } catch (_) {}

        try {
          if (widget.onRefreshProfile != null) await widget.onRefreshProfile!();
        } catch (_) {}
      } else {
        final msg = rpcRes['message']?.toString() ?? rpcRes.toString();
        _showSnack('Ошибка: $msg');
      }
    } catch (e) {
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      _showSnack('Ошибка при покупке: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user.role;
    final List<Widget> buttons = [];

    Widget fullWidth(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: SizedBox(width: double.infinity, child: child));

    buttons.add(fullWidth(ElevatedButton(onPressed: widget.onOpenTransfer, child: const Text('Перевести V/M'))));
    buttons.add(fullWidth(ElevatedButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Опросы/Аукционы'))), child: const Text('Опросы / Аукционы'))));

    buttons.add(fullWidth(ElevatedButton(
      onPressed: _openBuyTurnFlow,
      child: const Text('Купить ход экономисту'),
    )));

    if (role == 'politician') {
      buttons.add(fullWidth(PoliticianBlock(
        isEnabled: widget.isSpeechEnabled,
        speechActive: widget.speechActive,
        speechExpiresAt: widget.speechExpiresAt,
        speechActorId: widget.speechActorId,
        onStartSpeech: widget.onStartSpeech,
      )));
    }

    buttons.add(fullWidth(ElevatedButton(
      onPressed: widget.isListenEnabled ? widget.onListenPressed : null,
      style: ElevatedButton.styleFrom(backgroundColor: widget.isListenEnabled ? Colors.blueAccent : Colors.grey),
      child: Text(widget.isListenEnabled ? 'Прослушал речь жизни' : 'Уже прослушал'),
    )));

    if (role == 'economist') buttons.add(fullWidth(EconomistBlock(onAnalytics: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аналитика'))))));
    if (role == 'hollywood') buttons.add(fullWidth(HollywoodBlock(onOpen: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hollywood'))))));
    if (role == 'mafia') buttons.add(fullWidth(MafiaBlock(onManage: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятия'))))));
    if (role == 'journalist') buttons.add(fullWidth(JournalistBlock(currentUserId: widget.user.id, onPublished: widget.onRefreshProfile)));
    if (role == 'public_figure') buttons.add(fullWidth(PublicFigureBlock(onOpen: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('События'))))));
    if (role == 'admin') buttons.add(fullWidth(AdminBlock(onRefresh: widget.onRefreshProfile, onAction: (label) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label))))));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}

class _EconomistPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> economists;
  const _EconomistPickerSheet({Key? key, required this.economists}) : super(key: key);

  @override
  State<_EconomistPickerSheet> createState() => _EconomistPickerSheetState();
}

class _EconomistPickerSheetState extends State<_EconomistPickerSheet> {
  late List<Map<String, dynamic>> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.economists);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(widget.economists);
      } else {
        _filtered = widget.economists.where((row) {
          final username = (row['telegram_username'] ?? '').toString().toLowerCase();
          final first = (row['first_name'] ?? '').toString().toLowerCase();
          final last = (row['last_name'] ?? '').toString().toLowerCase();
          return username.contains(q) || first.contains(q) || last.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Поиск экономиста',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      FocusScope.of(context).unfocus();
                    },
                    child: const Text('Очистить'),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(child: Text('Не найдено', style: theme.textTheme.bodyLarge))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        final row = _filtered[index];
                        final first = (row['first_name'] ?? '').toString();
                        final last = (row['last_name'] ?? '').toString();
                        final displayName = ('$first $last').trim().isEmpty ? (row['telegram_username'] ?? 'Без имени') : '$first $last';
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
  }
}

