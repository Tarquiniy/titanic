// lib/theme/app_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Titanic — Art Deco theme inspired by the provided references.
/// Dark teal base, black depth, strong gold accents, geometric subtlety.
/// This file preserves original public API (getters) and adds more
/// decorations / utilities for a brighter Art-Deco look.
class TitanicTheme {
  // Palette (original colors preserved + additions)
  static const Color deepTeal = Color(0xFF074E4A);
  static const Color tealShade = Color(0xFF0D6B66);
  static const Color slate = Color(0xFF081518);
  static const Color nearBlack = Color(0xFF050404);
  static const Color gold = Color(0xFFD4AF37);
  static const Color warmGold = Color(0xFFB8912E);
  static const Color softIvory = Color(0xFFF6EFE6);
  static const Color panelTint = Color(0xFF0B2B2A); // slight panel tint
  static const Color richCopper = Color(0xFF9E5B4B); // A new shade for more rich accents
  static const Color darkEmerald = Color(0xFF004B44); // Adding depth with dark emerald green

  // translucents
  static final Color glassTint = Colors.white.withOpacity(0.03);
  static final Color glassBorder = Colors.white.withOpacity(0.06);

  // --- Gradients (enhanced for stronger highlights) ---
  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [nearBlack, deepTeal, tealShade],
        stops: [0.0, 0.45, 1.0],
      );

  static LinearGradient get goldGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          gold.withOpacity(0.98),
          warmGold.withOpacity(0.98),
          gold.withOpacity(0.88)
        ],
        stops: const [0.0, 0.6, 1.0],
      );

  static LinearGradient get copperGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [richCopper.withOpacity(0.98), warmGold.withOpacity(0.9)],
        stops: const [0.0, 1.0],
      );

  // Subtle stepped gradient used for small panels (Art-Deco stepped look)
  static LinearGradient get steppedAccentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          darkEmerald.withOpacity(0.9),
          panelTint.withOpacity(0.9),
          gold.withOpacity(0.06),
        ],
        stops: const [0.0, 0.7, 1.0],
      );

  // --- Decorations (kept original names + added art-deco variants) ---

  /// Original-style panel but intensified with gold inner accent and soft bevel shadow
  static BoxDecoration get panelDecoration => BoxDecoration(
        gradient: LinearGradient(
          colors: [panelTint.withOpacity(0.98), panelTint.withOpacity(0.82)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withOpacity(0.18), width: 1.4),
        boxShadow: [
          // soft elevated shadow
          BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 14, offset: const Offset(0, 8)),
          // subtle gold rim glow
          BoxShadow(color: gold.withOpacity(0.03), blurRadius: 24, spreadRadius: 2),
        ],
      );

  /// Slightly translucent card used across app; now with a faint pattern hint
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: panelTint.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 10, offset: const Offset(0, 6)),
        ],
        // Add a gentle directional sheen using a gradient overlay via boxShadow-like approach.
      );

  /// Primary accent (gold) button decoration — upgraded: stronger depth, slightly beveled
  static BoxDecoration get primaryAccentButtonDecoration => BoxDecoration(
        gradient: goldGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: nearBlack.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 10, offset: const Offset(0, 6)),
          // small highlight
          BoxShadow(color: Colors.white.withOpacity(0.03), blurRadius: 1, offset: const Offset(0, -1)),
        ],
      );

  /// Copper-accent button for variation
  static BoxDecoration get copperAccentButtonDecoration => BoxDecoration(
        gradient: copperGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: richCopper.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.42), blurRadius: 8, offset: const Offset(0, 5)),
        ],
      );

  /// New: outline button with double-line gilded border (Art-Deco marquee)
  static BoxDecoration outlineGildedButton({bool highlighted = false}) => BoxDecoration(
        color: panelTint.withOpacity(highlighted ? 0.06 : 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.fromBorderSide(BorderSide(color: gold.withOpacity(highlighted ? 0.9 : 0.22), width: 1.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 6, offset: const Offset(0, 4)),
        ],
      );

  // Input decoration (kept but slightly intensified)
  static InputDecoration get inputDecoration => InputDecoration(
        filled: true,
        fillColor: panelTint.withOpacity(0.12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: gold.withOpacity(0.08))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: gold.withOpacity(0.06))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: gold.withOpacity(0.95), width: 1.8)),
        labelStyle: TextStyle(color: softIvory.withOpacity(0.95), fontFamily: 'PlayfairDisplay'),
        hintStyle: TextStyle(color: softIvory.withOpacity(0.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  // --- Text styles (preserve names, refine details) ---
  static TextStyle get heading => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: softIvory,
        letterSpacing: 1.2,
        height: 1.02,
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: gold,
        letterSpacing: 1.1,
      );

  static TextStyle get subtitle => TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: softIvory.withOpacity(0.95),
      );

  static TextStyle get body => TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: softIvory.withOpacity(0.95),
        height: 1.4,
      );

  static TextStyle get buttonText => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF04120F),
      );

  // icons
  static IconThemeData get iconTheme => IconThemeData(color: gold, size: 20);

  // --- Utilities & ornaments (new) ---

  /// Decorative Divider with gold dot in the center (Art-Deco separator)
  static Widget decoDivider({double thickness = 1.0, double gap = 8.0}) {
    return Row(
      children: [
        Expanded(child: Container(height: thickness, color: gold.withOpacity(0.26))),
        SizedBox(width: gap),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: gold, shape: BoxShape.circle)),
        SizedBox(width: gap),
        Expanded(child: Container(height: thickness, color: gold.withOpacity(0.26))),
      ],
    );
  }

  /// Corner ornament widget — small geometric accent for corners/headers
  static Widget cornerOrnament({double size = 16}) {
    return Transform.rotate(
      angle: -math.pi / 8,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: goldGradient,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 4, offset: const Offset(0, 2))],
        ),
      ),
    );
  }

  /// A decorative panel with subtle radial/sweep pattern overlay
  /// Use for screens or larger panels where a patterned background is desired.
  static Widget artDecoBackground({required Widget child, bool smallPattern = false}) {
    // We layer a gradient base + an overlay using a SweepGradient (repeating motif).
    final overlay = Container(
      decoration: BoxDecoration(
        gradient: SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: math.pi * (smallPattern ? 0.7 : 1.1),
          tileMode: TileMode.repeated,
          colors: [
            gold.withOpacity(0.02),
            Colors.transparent,
            gold.withOpacity(0.01),
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.12, 0.2],
        ),
        borderRadius: BorderRadius.circular(0),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(decoration: BoxDecoration(gradient: backgroundGradient)),
        Positioned.fill(child: overlay),
        // content over pattern
        child,
      ],
    );
  }

  /// Art-Deco panel decoration with stepped gold rim and inner glow
  static BoxDecoration artDecoPanelDecoration({bool prominent = false}) {
    return BoxDecoration(
      gradient: prominent
          ? LinearGradient(colors: [panelTint.withOpacity(0.98), darkEmerald.withOpacity(0.92)])
          : LinearGradient(colors: [panelTint.withOpacity(0.96), panelTint.withOpacity(0.82)]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: gold.withOpacity(prominent ? 0.5 : 0.18), width: prominent ? 1.6 : 1.2),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.65), blurRadius: prominent ? 20 : 12, offset: const Offset(0, 10)),
        BoxShadow(color: gold.withOpacity(0.03), blurRadius: prominent ? 24 : 18, spreadRadius: 2),
      ],
    );
  }

  /// Decorative small tile used to simulate repeated geometric element inside lists/cards
  static BoxDecoration geometricTileDecoration({bool highlighted = false}) {
    return BoxDecoration(
      gradient: highlighted ? steppedAccentGradient : LinearGradient(colors: [panelTint.withOpacity(0.08), panelTint.withOpacity(0.04)]),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: gold.withOpacity(highlighted ? 0.26 : 0.08)),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(highlighted ? 0.22 : 0.12), blurRadius: 6, offset: const Offset(0, 4)),
      ],
    );
  }

  // --- ThemeData (keeps compatibility, but uses improved defaults) ---
  static ThemeData get themeData {
    final base = ThemeData.dark(useMaterial3: false);
    return base.copyWith(
      scaffoldBackgroundColor: deepTeal,
      primaryColor: gold,
      colorScheme: base.colorScheme.copyWith(
        background: deepTeal,
        surface: slate,
        onSurface: softIvory,
        primary: gold,
        secondary: warmGold,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: nearBlack.withOpacity(0.92),
        titleTextStyle: heading.copyWith(fontSize: 20),
        iconTheme: iconTheme,
        elevation: 2,
        centerTitle: false,
      ),
      textTheme: TextTheme(
        headlineSmall: heading,
        titleLarge: titleLarge,
        bodyLarge: body,
        bodyMedium: body,
        labelLarge: buttonText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelTint.withOpacity(0.12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: gold.withOpacity(0.06))),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: nearBlack,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: buttonText,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 8,
        ),
      ),
      iconTheme: iconTheme,
      splashFactory: InkRipple.splashFactory,
    );
  }
}
