// lib/widgets/art_deco_button.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ArtDecoButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final IconData? icon;
  final double? width;

  const ArtDecoButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.primary = false,
    this.loading = false,
    this.icon,
    this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      decoration: primary
          ? TitanicTheme.primaryAccentButtonDecoration
          : TitanicTheme.outlineGildedButton(highlighted: onPressed != null),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null && !loading) ...[
                  Icon(
                    icon,
                    color: primary
                        ? const Color(0xFF0A0A0A)
                        : TitanicTheme.raptureGold,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                ],
                if (loading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary
                          ? const Color(0xFF0A0A0A)
                          : TitanicTheme.raptureGold,
                    ),
                  )
                else
                  Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: primary
                          ? const Color(0xFF0A0A0A)
                          : TitanicTheme.ivoryCream,
                      letterSpacing: 0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}