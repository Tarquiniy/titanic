// lib/widgets/art_deco_button.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ArtDecoButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final IconData? icon;
  final double height;
  final double? width;

  const ArtDecoButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.primary = false,
    this.loading = false,
    this.icon,
    this.height = 48,
    this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final decoration = primary
        ? TitanicTheme.primaryAccentButtonDecoration
        : BoxDecoration(
            color: TitanicTheme.nearBlack.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TitanicTheme.warmGold.withOpacity(0.12)),
          );

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        width: width,
        height: height,
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(TitanicTheme.gold),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) Icon(icon, color: primary ? TitanicTheme.nearBlack : TitanicTheme.warmGold, size: 18),
                        if (icon != null) const SizedBox(width: 8),
                        Text(text, style: primary ? TitanicTheme.buttonText : TitanicTheme.body.copyWith(color: TitanicTheme.warmGold)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
