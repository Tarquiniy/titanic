// lib/widgets/role_buttons.dart
import 'package:flutter/material.dart';
import 'package:titanic/models/app_user.dart';
import 'package:titanic/widgets/art_deco_button.dart';

typedef VoidCallbackAsync = Future<void> Function();

class RoleButtons extends StatelessWidget {
  final AppUser user;

  // state flags
  final bool hasActiveDebate;
  final bool alreadyVotedInActiveDebate;
  final bool hasActiveResolution;
  final bool alreadyBetInActiveResolution;

  // callbacks
  final VoidCallback onTransfer;
  final VoidCallback onOpenInventory;
  final VoidCallbackAsync onBuyTurn;
  final VoidCallback onPurchaseEnterprise;
  final VoidCallbackAsync onOpenDebates;
  final VoidCallbackAsync onOpenResolution;
  final VoidCallback onStartSpeech;
  final bool speechButtonEnabled;
  final bool replaceSpeechButtonWithListen;

  // listen widget (already styled as ArtDecoButton inside ListenButton)
  final Widget listenWidget;

  /// "Статья Чести"
  final VoidCallbackAsync? onHonorArticle;
  final bool honorAlreadyUsed;

  /// "Вложиться в цвет"
  final VoidCallbackAsync? onInvestInColor;

  /// Mafia offer
  final VoidCallbackAsync? onMafiaOffer;
  final bool mafiaOfferUsed;

  const RoleButtons({
    Key? key,
    required this.user,
    required this.onTransfer,
    required this.onOpenInventory,
    required this.onBuyTurn,
    required this.onPurchaseEnterprise,
    required this.onOpenDebates,
    required this.onOpenResolution,
    required this.onStartSpeech,
    this.speechButtonEnabled = true,
    this.replaceSpeechButtonWithListen = false,
    required this.listenWidget,
    this.onHonorArticle,
    this.honorAlreadyUsed = false,
    this.onInvestInColor,
    this.onMafiaOffer,
    this.mafiaOfferUsed = false,
    this.hasActiveDebate = false,
    this.alreadyVotedInActiveDebate = false,
    this.hasActiveResolution = false,
    this.alreadyBetInActiveResolution = false,
  }) : super(key: key);

  Widget _btn({
    required String text,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: ArtDecoButton(
          text: text,
          icon: icon,
          onPressed: onPressed,
          primary: primary,
          expanded: true,
        ),
      ),
    );
  }

  bool _roleContains(String needle) {
    final r = (user.role ?? '').toString().toLowerCase().trim();
    final n = needle.toLowerCase().trim();
    if (r == n) return true;
    return r.contains(n);
  }

  @override
  Widget build(BuildContext context) {
    final role = (user.role ?? '').toString().toLowerCase().trim();
    final List<Widget> buttons = [];

    // ✅ Общие кнопки (видны всем)
    buttons.add(
      _btn(
        text: 'Купить ход экономисту',
        icon: Icons.shopping_cart,
        onPressed: () => onBuyTurn(),
        primary: true,
      ),
    );

    buttons.add(
      _btn(
        text: 'Перевести Войсы',
        icon: Icons.swap_horiz,
        onPressed: onTransfer,
        primary: true,
      ),
    );

    buttons.add(
      _btn(
        text: 'Инвентарь',
        icon: Icons.inventory_2,
        onPressed: onOpenInventory,
        primary: true,
      ),
    );

    // ✅ Купить предприятие — только экономист
    if (_roleContains('economist') || _roleContains('экономист')) {
      buttons.add(
        _btn(
          text: 'Купить предприятие',
          icon: Icons.business,
          onPressed: onPurchaseEnterprise,
          primary: true,
        ),
      );
    }

    // ✅ Дебаты (для не-политиков и не-журналистов)
    final isPolitician = _roleContains('politician') || _roleContains('политик');
    final isJournalist = _roleContains('journalist') || _roleContains('журналист');

    if (!isPolitician &&
        !isJournalist &&
        hasActiveDebate &&
        !alreadyVotedInActiveDebate) {
      buttons.add(
        _btn(
          text: 'Дебаты',
          icon: Icons.forum,
          onPressed: () => onOpenDebates(),
          primary: true,
        ),
      );
    }

    // ✅ Политрешение — ТОЛЬКО для политиков (фикс бага “видно у экономистов”)
    if (isPolitician && hasActiveResolution && !alreadyBetInActiveResolution) {
      buttons.add(
        _btn(
          text: 'Политрешение',
          icon: Icons.gavel,
          onPressed: () => onOpenResolution(),
          primary: true,
        ),
      );
    }

    // ✅ Речь жизни — только политик
    if (isPolitician) {
      if (replaceSpeechButtonWithListen) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: listenWidget,
          ),
        );
      } else {
        buttons.add(
          _btn(
            text: 'Речь жизни - сказать',
            icon: Icons.campaign,
            onPressed: speechButtonEnabled ? onStartSpeech : null,
            primary: true,
          ),
        );
      }
    }

    // ✅ Listen widget (уже ArtDecoButton внутри listen_button.dart)
    if (!replaceSpeechButtonWithListen) {
      buttons.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: listenWidget));
    }

    // Role extras
    if (_roleContains('mafia') || _roleContains('мафия')) {
      buttons.add(
        _btn(
          text: mafiaOfferUsed
              ? 'Предложение — использовано'
              : 'Предложение от которого нельзя отказаться',
          icon: Icons.local_fire_department,
          onPressed: (mafiaOfferUsed || onMafiaOffer == null)
              ? null
              : () async {
                  try {
                    await onMafiaOffer!();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
          primary: !mafiaOfferUsed,
        ),
      );
    } else if (isJournalist) {
      buttons.add(
        _btn(
          text: honorAlreadyUsed ? 'Статья Чести — использовано' : 'Статья Чести',
          icon: Icons.article,
          onPressed: honorAlreadyUsed
              ? null
              : () async {
                  try {
                    if (onHonorArticle != null) {
                      await onHonorArticle!();
                    } else {
                      await onOpenDebates();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
          primary: !honorAlreadyUsed,
        ),
      );
    } else if (_roleContains('public_figure') || _roleContains('общественный')) {
      buttons.add(
        _btn(
          text: 'Вложиться в цвет',
          icon: Icons.savings,
          onPressed: () async {
            if (onInvestInColor != null) {
              try {
                await onInvestInColor!();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка: $e')),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Функция не реализована')),
              );
            }
          },
          primary: true,
        ),
      );
    }

    // Admin (оставил заглушки, но теперь тоже в ArtDecoButton-стиле)
    if (_roleContains('admin')) {
      buttons.add(
        _btn(
          text: 'Админ-панель',
          icon: Icons.admin_panel_settings,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Админ-панель')),
          ),
          primary: true,
        ),
      );
      buttons.add(
        _btn(
          text: 'Пополнить V/M',
          icon: Icons.add_circle,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пополнение')),
          ),
          primary: true,
        ),
      );
      buttons.add(
        _btn(
          text: 'Создать опрос',
          icon: Icons.poll,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Создать опрос')),
          ),
          primary: true,
        ),
      );
      buttons.add(
        _btn(
          text: 'Создать аукцион',
          icon: Icons.gavel,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Создание аукциона')),
          ),
          primary: true,
        ),
      );
      buttons.add(
        _btn(
          text: 'Статистика цветов',
          icon: Icons.bar_chart,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Статистика')),
          ),
          primary: true,
        ),
      );
    }

    // убираем последний отступ, чтобы блок выглядел аккуратно
    if (buttons.isNotEmpty) {
      final last = buttons.removeLast();
      buttons.add(Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: (last is Padding) ? last.child ?? last : last,
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}

