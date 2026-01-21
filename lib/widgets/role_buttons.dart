// lib/widgets/role_buttons.dart
import 'package:flutter/material.dart';
import 'package:titanic/models/app_user.dart';

typedef VoidCallbackAsync = Future<void> Function();

class RoleButtons extends StatelessWidget {
  final AppUser user;
  final bool hasActiveDebate;
  final bool alreadyVotedInActiveDebate;
  final bool hasActiveResolution;
  final bool alreadyBetInActiveResolution;

  // callbacks
  final VoidCallback onTransfer;
  final VoidCallbackAsync onBuyTurn;
  final VoidCallback onPurchaseEnterprise;
  final VoidCallbackAsync onOpenDebates;
  final VoidCallback onOpenResolution;
  final VoidCallback onStartSpeech;
  final Widget listenWidget;

  const RoleButtons({
    Key? key,
    required this.user,
    required this.onTransfer,
    required this.onBuyTurn,
    required this.onPurchaseEnterprise,
    required this.onOpenDebates,
    required this.onOpenResolution,
    required this.onStartSpeech,
    required this.listenWidget,
    this.hasActiveDebate = false,
    this.alreadyVotedInActiveDebate = false,
    this.hasActiveResolution = false,
    this.alreadyBetInActiveResolution = false,
  }) : super(key: key);

  void _add(BuildContext ctx, String title, VoidCallback action, {Color? color}) {
    final btn = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: action,
          child: Text(title),
        ),
      ),
    );
    // Directly show button by calling action - used in list building.
  }

  @override
  Widget build(BuildContext context) {
    final role = user.role;
    final List<Widget> buttons = [];

    Widget btn(String title, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: onTap,
              child: Text(title),
            ),
          ),
        );

    buttons.add(btn('Перевести Войсы', onTransfer));
    buttons.add(btn('Купить ход экономисту', () => onBuyTurn()));

    if (role == 'economist') {
      buttons.add(btn('Купить предприятие', onPurchaseEnterprise));
    }

    if (role != 'politician' && hasActiveDebate && !alreadyVotedInActiveDebate) {
      buttons.add(btn('Дебаты', () => onOpenDebates()));
    }

    if (role == 'politician' && hasActiveResolution && !alreadyBetInActiveResolution) {
      buttons.add(btn('Выбрать политрешение', onOpenResolution, color: Colors.blueAccent));
    }

    if (role == 'politician') {
      buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: ElevatedButton(onPressed: onStartSpeech, child: const Text('Речь жизни (старт)'))));
    }

    // Listen widget delegated (already a widget)
    buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: listenWidget));

    // role-specific extras
    if (role == 'economist') {
      buttons.add(btn('Аналитика / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аналитика')))));
    } else if (role == 'hollywood') {
      buttons.add(btn('Контент / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hollywood')))));
    } else if (role == 'mafia') {
      buttons.add(btn('Управление предприятиями', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятия')))));
    } else if (role == 'journalist') {
      buttons.add(btn('Дебаты / Публикации', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Дебаты')))));
    } else if (role == 'public_figure') {
      buttons.add(btn('События / Прослушал', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('События')))));
    } else if (role == 'admin') {
      buttons.add(btn('Админ-панель', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Админ-панель'))), color: Colors.black87));
      buttons.add(btn('Пополнить V/M', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пополнение')))));
      buttons.add(btn('Создать опрос', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создать опрос')))));
      buttons.add(btn('Создать аукцион', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создание аукциона')))));
      buttons.add(btn('Статистика цветов', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Статистика')))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}
