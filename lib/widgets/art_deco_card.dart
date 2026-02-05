// lib/widgets/art_deco_card.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ArtDecoCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const ArtDecoCard({
    Key? key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool header =
        (title != null || subtitle != null || leading != null || trailing != null);
    final bool interactive = onTap != null;

    // Единый радиус как у кнопок (и чтобы ripple всегда совпадал с формой)
    final BorderRadius borderRadius = BorderRadius.circular(12);

    // Базовая декорация карты (берём из темы, только унифицируем радиус)
    final BoxDecoration decoration =
        TitanicTheme.cardDecoration.copyWith(borderRadius: borderRadius);

    final Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header)
            Row(
              children: [
                if (leading != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: leading,
                  ),
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: TitanicTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      subtitle!,
                      style: TitanicTheme.subtitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: trailing,
                  ),
              ],
            ),
          if (header && child != null) const SizedBox(height: 10),
          if (child != null) child!,
        ],
      ),
    );

    // ВАЖНО для PWA/web/mobile: ripple должен рисоваться поверх декорации.
    // Поэтому используем Material -> Ink (decoration) -> InkWell.
    final Widget card = Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          mouseCursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
          // Тонкая "взрослая" реакция на нажатие/тап (без кричащего блика)
          splashColor: interactive
              ? TitanicTheme.raptureGold.withOpacity(0.10)
              : Colors.transparent,
          highlightColor: interactive
              ? Colors.white.withOpacity(0.03)
              : Colors.transparent,
          child: content,
        ),
      ),
    );

    return Container(
      margin: margin,
      child: Semantics(
        // Если карта кликабельная — ведём себя как кнопка для доступности
        button: interactive,
        enabled: interactive,
        label: title ?? subtitle ?? 'card',
        child: card,
      ),
    );
  }
}
