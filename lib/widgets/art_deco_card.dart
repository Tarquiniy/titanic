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
    final header = (title != null || subtitle != null || leading != null || trailing != null);
    return Container(
      margin: margin,
      decoration: TitanicTheme.cardDecoration.copyWith(borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (header)
                  Row(
                    children: [
                      if (leading != null) Padding(padding: const EdgeInsets.only(right: 12), child: leading),
                      if (title != null)
                        Expanded(
                          child: Text(title!, style: TitanicTheme.titleLarge, overflow: TextOverflow.ellipsis),
                        ),
                      if (subtitle != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(subtitle!, style: TitanicTheme.subtitle)),
                      if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
                    ],
                  ),
                if (header && child != null) const SizedBox(height: 10),
                if (child != null) child!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
