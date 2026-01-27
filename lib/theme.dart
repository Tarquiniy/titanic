// lib/theme.dart
//
// Centralized black-and-white newspaper (1930s) theme and reusable UI primitives.
// Use at app root: MaterialApp(theme: AppTheme.vintageTheme, ...)
//
// Fonts (in pubspec.yaml):
// - PlayfairDisplay (headlines)
// - LibreBaskerville (body / buttons)

import 'dart:math';
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Primary grayscale newspaper palette (no colored turquoise/sepia)
  static const Color paper = Color(0xFFFAF7EE); // warm off-white paper
  static const Color paperCard = Color(0xFFF4F1E6); // slightly shaded card
  static const Color ink = Color(0xFF1C1C1C); // near-black "ink"
  static const Color inkMuted = Color(0xFF6F6F6F); // muted grey ink
  static const Color frame = Color(0xFFBFB5A6); // light border tone
  static const Color deepGrey = Color(0xFF2E2E2E); // dark grey for strong accents
  static const Color softGrey = Color(0xFFDAD6C6); // softer background accents

  // Backwards-compatible aliases used in screens
  static const Color filmBlack = ink;
  static const Color filmDark = deepGrey;
  static const Color filmLight = paperCard;
  static const Color filmGrey = inkMuted;
  static const Color filmAccent = deepGrey;

  // Public accessor to the ThemeData
  static ThemeData get vintageTheme {
    final base = ThemeData.light();

    final textTheme = TextTheme(
      headlineLarge: const TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        height: 1.08,
        color: ink,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: ink,
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'LibreBaskerville',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'LibreBaskerville',
        fontSize: 15,
        color: ink,
        height: 1.35,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'LibreBaskerville',
        fontSize: 14,
        color: ink,
        height: 1.35,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: paper,
      ),
    );

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: filmAccent,
      onPrimary: paper,
      secondary: inkMuted,
      onSecondary: paper,
      error: Colors.red.shade700,
      onError: paper,
      background: paper,
      onBackground: ink,
      surface: paperCard,
      onSurface: ink,
    );

    return base.copyWith(
      useMaterial3: false,
      scaffoldBackgroundColor: paper,
      primaryColor: filmAccent,
      colorScheme: colorScheme,
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: paperCard,
        elevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: ink),
        iconTheme: const IconThemeData(color: ink),
        toolbarTextStyle: textTheme.bodyMedium?.copyWith(color: ink),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(const Size(88, 44)),
          padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          textStyle: MaterialStateProperty.all(const TextStyle(fontFamily: 'LibreBaskerville', fontWeight: FontWeight.w600)),
          backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
            if (states.contains(MaterialState.disabled)) return softGrey;
            if (states.contains(MaterialState.pressed)) return deepGrey.withOpacity(0.9);
            return deepGrey;
          }),
          foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
            if (states.contains(MaterialState.disabled)) return inkMuted;
            return paper;
          }),
          elevation: MaterialStateProperty.all(0),
          shape: MaterialStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: frame.withOpacity(0.9)),
          )),
          overlayColor: MaterialStateProperty.resolveWith((states) => ink.withOpacity(0.06)),
          shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.08)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(ink),
          textStyle: MaterialStateProperty.all(const TextStyle(fontFamily: 'LibreBaskerville')),
          overlayColor: MaterialStateProperty.all(deepGrey.withOpacity(0.08)),
          shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        ),
      ),

      cardTheme: CardThemeData(
        color: paperCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: frame.withOpacity(0.9), width: 1.0),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paperCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: frame.withOpacity(0.6))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: frame.withOpacity(0.5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: deepGrey.withOpacity(0.9), width: 1.2)),
        hintStyle: TextStyle(color: inkMuted),
      ),

      iconTheme: const IconThemeData(color: ink),
      dividerTheme: DividerThemeData(color: frame.withOpacity(0.6), thickness: 1),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: deepGrey,
        foregroundColor: paper,
      ),
    );
  }

  // Small helper to produce a re-usable ButtonStyle for custom buttons (no black)
  static ButtonStyle vintageButtonStyle({bool disabled = false, double radius = 8}) {
    return ButtonStyle(
      minimumSize: MaterialStateProperty.all(const Size(88, 44)),
      padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      textStyle: MaterialStateProperty.all(const TextStyle(fontFamily: 'LibreBaskerville', fontWeight: FontWeight.w600)),
      backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (disabled) return softGrey;
        return deepGrey;
      }),
      foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (disabled) return inkMuted;
        return paper;
      }),
      elevation: MaterialStateProperty.all(0),
      shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: frame.withOpacity(disabled ? 0.2 : 0.9)))),
      overlayColor: MaterialStateProperty.all(ink.withOpacity(0.06)),
    );
  }
}

// Reusable VintageCard widget that follows theme styles and can be used across screens.
class VintageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? color;
  const VintageCard({Key? key, required this.child, this.padding = const EdgeInsets.all(12), this.margin = const EdgeInsets.symmetric(vertical: 6), this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = color ?? theme.cardTheme.color ?? AppTheme.paperCard;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.frame.withOpacity(0.9), width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      padding: padding,
      child: DefaultTextStyle(style: theme.textTheme.bodyMedium ?? const TextStyle(), child: child),
    );
  }
}

// Reusable VintageButton to use where you want buttons consistent with theme.
class VintageButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool disabled;
  final double radius;
  const VintageButton({Key? key, required this.onPressed, required this.child, this.disabled = false, this.radius = 8}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: AppTheme.vintageButtonStyle(disabled: disabled, radius: radius),
      child: child,
    );
  }
}

// VintageAction: standardized icon+label action button used by screens.
class VintageAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool disabled;
  final double? fixedWidth;
  const VintageAction({Key? key, required this.label, required this.icon, required this.onPressed, this.disabled = false, this.fixedWidth}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final btn = ElevatedButton.icon(
      onPressed: disabled ? null : onPressed,
      icon: Icon(icon, size: 18, color: AppTheme.paper),
      label: Text(label, style: const TextStyle(fontFamily: 'LibreBaskerville')),
      style: AppTheme.vintageButtonStyle(disabled: disabled),
    );

    if (fixedWidth != null) return SizedBox(width: fixedWidth, height: 48, child: btn);
    return SizedBox(height: 48, child: btn);
  }
}

// VintageSection: titled paper card with consistent heading style
class VintageSection extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets? padding;
  const VintageSection({Key? key, required this.title, required this.child, this.padding}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return VintageCard(
      padding: padding ?? const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title.toUpperCase(), style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.ink)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

// Optional: lightweight film grain painter. Use as top overlay in a Stack when you want a subtle grain.
class FilmGrainPainter extends CustomPainter {
  final double opacity;
  final int seed;
  const FilmGrainPainter({this.opacity = 0.03, this.seed = 42});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(opacity);
    final rnd = Random(seed);
    final count = (size.width * size.height * 0.00012).round();
    for (int i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant FilmGrainPainter oldDelegate) => false;
}
