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

  /// Callback для "Статья Чести"
  final VoidCallbackAsync? onHonorArticle;
  final bool honorAlreadyUsed;

  /// Callback для "Вложиться в цвет"
  final VoidCallbackAsync? onInvestInColor;

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
    this.onHonorArticle,
    this.honorAlreadyUsed = false,
    this.onInvestInColor,
    this.hasActiveDebate = false,
    this.alreadyVotedInActiveDebate = false,
    this.hasActiveResolution = false,
    this.alreadyBetInActiveResolution = false,
  }) : super(key: key);

  Widget _btn(String title, VoidCallback onTap, {Color? color}) => Padding(
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

  @override
  Widget build(BuildContext context) {
    final role = (user.role ?? '').toString().toLowerCase();
    final List<Widget> buttons = [];

    buttons.add(_btn('Перевести Войсы', onTransfer));
    buttons.add(_btn('Купить ход экономисту', () => onBuyTurn()));

    if (role == 'economist') {
      buttons.add(_btn('Купить предприятие', onPurchaseEnterprise));
    }

    // дебаты для не-политиков и не-журналистов (журналист — Статья Чести)
    if (role != 'politician' && role != 'journalist' && hasActiveDebate && !alreadyVotedInActiveDebate) {
      buttons.add(_btn('Дебаты', () => onOpenDebates()));
    }

    if (role == 'politician' && hasActiveResolution && !alreadyBetInActiveResolution) {
      buttons.add(_btn('Выбрать политрешение', onOpenResolution, color: Colors.blueAccent));
    }

    if (role == 'politician') {
      buttons.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: ElevatedButton(onPressed: onStartSpeech, child: const Text('Речь жизни (старт)')),
      ));
    }

    // Listen widget delegated (already a widget)
    buttons.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6.0), child: listenWidget));

    // role-specific extras
    if (role == 'economist') {
      buttons.add(_btn('Аналитика / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Аналитика')))));
    } else if (role == 'hollywood') {
      buttons.add(_btn('Контент / Ставки', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hollywood')))));
    } else if (role == 'mafia') {
      buttons.add(_btn('Управление предприятиями', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Предприятия')))));
    } else if (role == 'journalist') {
      // Статья Чести
      final disabled = honorAlreadyUsed;
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: disabled ? Colors.grey : Colors.purple),
              onPressed: disabled
                  ? null
                  : () async {
                      if (onHonorArticle != null) {
                        try {
                          await onHonorArticle!();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                        }
                      } else {
                        await onOpenDebates();
                      }
                    },
              child: Text(disabled ? 'Статья Чести — использовано' : 'Статья Чести'),
            ),
          ),
        ),
      );
    } else if (role == 'public_figure') {
      // Вложиться в цвет
      buttons.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                if (onInvestInColor != null) {
                  try {
                    await onInvestInColor!();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Функция не реализована')));
                }
              },
              child: const Text('Вложиться в цвет'),
            ),
          ),
        ),
      );

      // keep old button for events if needed
     if (role == 'admin') {
      buttons.add(_btn('Админ-панель', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Админ-панель'))), color: Colors.black87));
      buttons.add(_btn('Пополнить V/M', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пополнение')))));
      buttons.add(_btn('Создать опрос', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создать опрос')))));
      buttons.add(_btn('Создать аукцион', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Создание аукциона')))));
      buttons.add(_btn('Статистика цветов', () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Статистика')))));
    }}

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}
