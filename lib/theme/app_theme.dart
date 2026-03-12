// lib/theme/app_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// LuxuryArtDecoPainter — МИНИМАЛИСТИЧНЫЙ И АКЦЕНТИРОВАННЫЙ.
/// Несколько доминирующих, графичных элементов вместо заполняющего узора.
class LuxuryArtDecoPainter extends CustomPainter {
  static const Color _raptureGold = Color(0xFFD4AF37);
  static const Color _seaFoamGreen = Color(0xFF4A9B7F);
  static const Color _brassAccent = Color(0xFFB87333);
  static const Color _abyssalBlue = Color(0xFF0A1A2A);
  static const Color _ivoryCream = Color(0xFFF5E9D8);

  final double opacity;
  final double scale;

  LuxuryArtDecoPainter({this.opacity = 0.5, this.scale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final scaledSize = Size(size.width * scale, size.height * scale);
    final offset = Offset((size.width - scaledSize.width) / 2, (size.height - scaledSize.height) / 2);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    // СЛОЙ 0: ОЧЕНЬ ТОНКАЯ СТРУКТУРНАЯ СЕТКА (ЕДВА ЗАМЕТНАЯ)
    _drawStructuralGrid(canvas, scaledSize);

    // СЛОЙ 1: ГЛАВНЫЙ АКЦЕНТ — ЦЕНТРАЛЬНЫЙ "СОЛНЕЧНЫЙ" УЗОР (SUNBURST)
    _drawDominantSunburst(canvas, scaledSize);

    // СЛОЙ 2: АКЦЕНТИРОВАННЫЕ ЛИНИИ — МОНОЛИТНЫЕ ШЕВРОНЫ
    _drawMonolithicChevrons(canvas, scaledSize);

    // СЛОЙ 3: УГЛОВЫЕ АКЦЕНТЫ — СТУПЕНЧАТЫЕ ПИРАМИДЫ (МИСТИЧЕСКИЙ МОТИВ)
    _drawMysticalCornerPyramids(canvas, scaledSize);

    // СЛОЙ 4: ДЕКОРАТИВНЫЕ ШТРИХИ — МЕТАЛЛИЧЕСКИЕ ИНКРУСТАЦИИ
    _drawMetallicInlays(canvas, scaledSize);

    canvas.restore();
  }

  void _drawStructuralGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3
      ..color = _raptureGold.withOpacity(0.03 * opacity);

    // Крупная модульная сетка
    final majorSpacing = 120.0;
    for (double x = 0; x < size.width; x += majorSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += majorSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDominantSunburst(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.28;

    // ВНЕШНИЙ КОНТУР — ТОЛСТЫЙ И ЯРКИЙ
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..color = _raptureGold.withOpacity(0.9 * opacity)
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(center, radius, outlinePaint);

    // ВНУТРЕННИЙ КОНТУР — ТОНКИЙ, СОЗДАЕТ ОБЪЕМ
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _ivoryCream.withOpacity(0.6 * opacity);
    canvas.drawCircle(center, radius * 0.92, innerPaint);

    // ГЛАВНЫЕ ЛУЧИ — МОЩНЫЕ И НАПРАВЛЕННЫЕ
    final mainRayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..color = _raptureGold.withOpacity(0.8 * opacity)
      ..strokeCap = StrokeCap.round;

    final mainRayCount = 8;
    for (int i = 0; i < mainRayCount; i++) {
      final angle = i * (2 * math.pi / mainRayCount);
      final rayLength = radius * 1.4;
      final endPoint = Offset(
        center.dx + rayLength * math.cos(angle),
        center.dy + rayLength * math.sin(angle),
      );
      canvas.drawLine(center, endPoint, mainRayPaint);

      // АКЦЕНТНАЯ ТОЧКА НА КОНЦЕ КАЖДОГО ЛУЧА
      canvas.drawCircle(
        endPoint,
        6.0,
        Paint()
          ..style = PaintingStyle.fill
          ..color = _seaFoamGreen.withOpacity(0.9 * opacity),
      );
    }

    // ВТОРОСТЕПЕННЫЕ ЛУЧИ — КОРОЧЕ И ТОНЬШЕ
    final secondaryRayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = _brassAccent.withOpacity(0.5 * opacity);

    final secondaryRayCount = 16;
    for (int i = 0; i < secondaryRayCount; i++) {
      if (i % 2 == 0) continue; // Пропускаем каждую вторую, где уже есть главный луч
      final angle = i * (2 * math.pi / secondaryRayCount);
      final rayLength = radius * 1.15;
      final endPoint = Offset(
        center.dx + rayLength * math.cos(angle),
        center.dy + rayLength * math.sin(angle),
      );
      canvas.drawLine(center, endPoint, secondaryRayPaint);
    }
  }

  void _drawMonolithicChevrons(Canvas canvas, Size size) {
    final chevronPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = _seaFoamGreen.withOpacity(0.7 * opacity)
      ..strokeCap = StrokeCap.square;

    // ВЕРХНИЙ ГОРИЗОНТАЛЬНЫЙ ШЕВРОН
    final topPath = Path();
    final topAmplitude = size.height * 0.15;
    final topY = size.height * 0.25;
    final segmentWidth = size.width / 6;

    topPath.moveTo(-50, topY);
    for (int i = 0; i <= 7; i++) {
      final x = i * segmentWidth;
      final y = topY + (i.isEven ? topAmplitude : -topAmplitude / 2);
      topPath.lineTo(x, y);
    }
    topPath.lineTo(size.width + 50, topY);
    canvas.drawPath(topPath, chevronPaint);

    // НИЖНИЙ ДИАГОНАЛЬНЫЙ ШЕВРОН (БОЛЕЕ ДРАМАТИЧНЫЙ)
    final bottomPath = Path();
    final bottomAmplitude = size.height * 0.12;
    final startY = size.height * 0.75;
    final startX = -size.width * 0.1;
    final endX = size.width * 1.1;
    final points = 9;

    bottomPath.moveTo(startX, startY);
    for (int i = 0; i <= points; i++) {
      final t = i / points;
      final x = startX + t * (endX - startX);
      // Диагональный тренд + зигзаг
      final y = startY + (t * size.height * 0.1) + (i.isEven ? bottomAmplitude : -bottomAmplitude);
      bottomPath.lineTo(x, y);
    }
    canvas.drawPath(bottomPath, chevronPaint..color = _brassAccent.withOpacity(0.6 * opacity));
  }

  void _drawMysticalCornerPyramids(Canvas canvas, Size size) {
    final pyramidPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _ivoryCream.withOpacity(0.4 * opacity);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _abyssalBlue.withOpacity(0.15);

    // ЛЕВЫЙ ВЕРХНИЙ УГОЛ — СТУПЕНЧАТАЯ ПИРАМИДА
    final leftTopSteps = 5;
    final leftTopSize = size.width * 0.18;
    for (int i = 0; i < leftTopSteps; i++) {
      final stepSize = leftTopSize * (leftTopSteps - i) / leftTopSteps;
      final rect = Rect.fromLTWH(
        20 + i * 8,
        20 + i * 8,
        stepSize,
        stepSize,
      );
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, pyramidPaint);
    }

    // ПРАВЫЙ НИЖНИЙ УГОЛ — ПЕРЕВЕРНУТАЯ ПИРАМИДА (МИСТИЧЕСКИЙ АКЦЕНТ)
    final rightBottomSteps = 4;
    final rightBottomSize = size.width * 0.15;
    for (int i = 0; i < rightBottomSteps; i++) {
      final stepSize = rightBottomSize * (i + 1) / rightBottomSteps;
      final rect = Rect.fromLTWH(
        size.width - 20 - stepSize - i * 6,
        size.height - 20 - stepSize - i * 6,
        stepSize,
        stepSize,
      );
      canvas.drawRect(rect, pyramidPaint..color = _seaFoamGreen.withOpacity(0.3 * opacity));
      // ЗАЛИВКА ГРАДИЕНТОМ (имитация свечения)
      final gradientPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = RadialGradient(
          center: Alignment.center,
          colors: [
            _seaFoamGreen.withOpacity(0.1),
            Colors.transparent,
          ],
        ).createShader(rect);
      canvas.drawRect(rect, gradientPaint);
    }
  }

  void _drawMetallicInlays(Canvas canvas, Size size) {
    // БОЛЬШИЕ "ЗОЛОТЫЕ" ТОЧКИ В УЗЛОВЫХ ТОЧКАХ СЕТКИ
    final majorSpacing = 120.0;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill;

    for (double x = majorSpacing; x < size.width; x += majorSpacing * 2) {
      for (double y = majorSpacing; y < size.height; y += majorSpacing * 2) {
        // Проверяем, не попадает ли точка в центральную область, чтобы не перегружать
        final center = Offset(size.width / 2, size.height / 2);
        if ((center - Offset(x, y)).distance < 150) continue;

        final dotSize = 3.5 + (x + y) % 5; // Небольшая вариация
        dotPaint.color = ((x / majorSpacing + y / majorSpacing) % 3 == 0)
            ? _raptureGold.withOpacity(0.5 * opacity)
            : _brassAccent.withOpacity(0.4 * opacity);

        canvas.drawCircle(Offset(x, y), dotSize, dotPaint);

        // СВЕЧЕНИЕ ВОКРУГ КРУПНЫХ ТОЧЕК
        if (dotSize > 6) {
          canvas.drawCircle(
            Offset(x, y),
            dotSize * 1.8,
            dotPaint..color = _raptureGold.withOpacity(0.08 * opacity),
          );
        }
      }
    }

    // ТОНКИЕ ВЕРТИКАЛЬНЫЕ ЛИНИИ ПО КРАЯМ (КАК ОТБЛЕСКИ НА СТЕНАХ)
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _raptureGold.withOpacity(0.1 * opacity);

    for (double x = 0; x < size.width; x += 70) {
      if (x < size.width * 0.1 || x > size.width * 0.9) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), edgePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! LuxuryArtDecoPainter ||
        oldDelegate.opacity != opacity ||
        oldDelegate.scale != scale;
  }
}

/// Titanic — Art Deco theme inspired by Bioshock 1 and 2
/// Underwater luxury, ornate details, brass/copper accents, geometric patterns
class TitanicTheme {
  // Color palette inspired by Rapture's underwater Art Deco
  static const Color abyssalBlue = Color(0xFF0A1A2A); // Deep ocean blue
  static const Color raptureGold = Color(0xFFD4AF37); // Ornate gold
  static const Color brassAccent = Color(0xFFB87333); // Warm brass
  static const Color copperDetail = Color(0xFF9C5B4B); // Aged copper
  static const Color seaFoamGreen = Color(0xFF4A9B7F); // Underwater green
  static const Color coralAccent = Color(0xFFE57373); // Coral pink
  static const Color deepTeal = Color(0xFF006B6B); // Deep sea teal
  static const Color ivoryCream = Color(0xFFF5E9D8); // Aged ivory
  static const Color panelDark = Color(0xFF15232D); // Dark panel
  static const Color surfaceNavy = Color(0xFF1A2835); // Surface navy
  static const Color darkEmerald = Color(0xFF00834e); // Dark Emerald
  static const Color tealShade = Color(0xFF045D5D); // TealShade

  // Geometric pattern properties
  static const double _patternScale = 1.0;
  static const double _patternDensity = 80.0; // Distance between pattern elements

  // Metallic gradients for that Bioshock feel
  static LinearGradient get backgroundGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [abyssalBlue, Color(0xFF0D2B4A), deepTeal],
        stops: [0.0, 0.5, 1.0],
      );

  static LinearGradient get goldGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          raptureGold.withOpacity(0.95),
          brassAccent.withOpacity(0.9),
          const Color(0xFFF5D76E).withOpacity(0.8)
        ],
        stops: const [0.0, 0.6, 1.0],
      );

  static LinearGradient get copperGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          copperDetail.withOpacity(0.95),
          const Color(0xFFC66B3C).withOpacity(0.9),
          brassAccent.withOpacity(0.8)
        ],
        stops: const [0.0, 0.7, 1.0],
      );

  static LinearGradient get seaGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          seaFoamGreen.withOpacity(0.9),
          deepTeal.withOpacity(0.9),
          const Color(0xFF008080).withOpacity(0.8)
        ],
        stops: const [0.0, 0.5, 1.0],
      );

  // Ornate panel decoration with marine details
  static BoxDecoration get panelDecoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [panelDark.withOpacity(0.95), surfaceNavy.withOpacity(0.9)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: raptureGold.withOpacity(0.4),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: raptureGold.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      );

  // Card with subtle wave pattern suggestion
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surfaceNavy.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: seaFoamGreen.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      );

  // Primary button - ornate gold like Bioshock interfaces
  static BoxDecoration get primaryAccentButtonDecoration => BoxDecoration(
        gradient: goldGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: raptureGold.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      );

  // ✅ NEW: Disabled primary button decoration (без переименований существующего)
  static BoxDecoration get primaryAccentButtonDecorationDisabled => BoxDecoration(
        color: panelDark.withOpacity(0.40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: raptureGold.withOpacity(0.18),
          width: 1.3,
        ),
        boxShadow: const [],
      );

  // Copper button for secondary actions
  static BoxDecoration get copperAccentButtonDecoration => BoxDecoration(
        gradient: copperGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: copperDetail.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      );

  // Outline button with Art Deco flair
  // ✅ UPDATED safely: добавлен enabled (по умолчанию true — старые вызовы не ломаются)
  static BoxDecoration outlineGildedButton({bool highlighted = false, bool enabled = true}) =>
      BoxDecoration(
        color: panelDark.withOpacity(
          enabled ? (highlighted ? 0.15 : 0.08) : 0.05,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? (highlighted ? seaFoamGreen.withOpacity(0.8) : raptureGold.withOpacity(0.3))
              : raptureGold.withOpacity(0.15),
          width: highlighted ? 2.0 : 1.5,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      );

  // Art Deco input decoration
  static InputDecoration get inputDecoration => InputDecoration(
        filled: true,
        fillColor: panelDark.withOpacity(0.15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: raptureGold.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: raptureGold.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: seaFoamGreen.withOpacity(0.9),
            width: 2.0,
          ),
        ),
        labelStyle: TextStyle(
          color: ivoryCream.withOpacity(0.9),
          fontFamily: 'PlayfairDisplay',
          fontSize: 16,
          letterSpacing: 0.5,
        ),
        hintStyle: TextStyle(
          color: ivoryCream.withOpacity(0.6),
          fontFamily: 'PlayfairDisplay',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  // Art Deco typography - ornate, serif fonts
  static TextStyle get heading => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ivoryCream,
        letterSpacing: 1.5,
        height: 1.1,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: raptureGold,
        letterSpacing: 1.2,
      );

  static TextStyle get subtitle => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: ivoryCream.withOpacity(0.9),
        letterSpacing: 0.8,
      );

  static TextStyle get body => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 15,
        color: ivoryCream.withOpacity(0.85),
        height: 1.5,
        letterSpacing: 0.3,
      );

  static TextStyle get buttonText => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF0A0A0A),
        letterSpacing: 1.0,
      );

  // Icons with gold tint
  static IconThemeData get iconTheme =>
      const IconThemeData(color: Color(0xFFD4AF37), size: 24);

  // Art Deco decorative elements
  static Widget decoDivider({double thickness = 1.5, double gap = 12.0}) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: thickness,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  raptureGold.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: seaFoamGreen,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: raptureGold.withOpacity(0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Container(
            height: thickness,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  raptureGold.withOpacity(0.3),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Ornate corner accent
  static Widget cornerOrnament({double size = 20}) {
    return Transform.rotate(
      angle: -math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: goldGradient,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.waves,
            size: size * 0.6,
            color: abyssalBlue,
          ),
        ),
      ),
    );
  }

  // ФОН ЛЮКС-КЛАССА: МИНИМАЛИСТИЧНЫЙ, АКЦЕНТИРОВАННЫЙ, ШИКАРНЫЙ
  static Widget luxuryArtDecoBackground({
    required Widget child,
    double patternOpacity = 0.4, // Оптимальная непрозрачность для акцентов
    bool subtleGlow = true,
    double scale = 1.0,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // БАЗА: ГЛУБОКИЙ ОКЕАНИЧЕСКИЙ ГРАДИЕНТ С ЛЕГКОЙ ТЕКСТУРОЙ
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    abyssalBlue,
                    Color(0xFF0A243D), // Более насыщенный оттенок
                    Color(0xFF003D3D), // Глубокий цвет морской бездны
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),

            // АКЦЕНТИРОВАННЫЕ УЗОРЫ ЛЮКС-КЛАССА
            Positioned.fill(
              child: CustomPaint(
                painter: LuxuryArtDecoPainter(
                  opacity: patternOpacity,
                  scale: scale,
                ),
              ),
            ),

            // ИЗЫСКАННАЯ ВИНЬЕТКА ДЛЯ ФОКУСА
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
            ),

            // ТОНКОЕ ЦЕНТРАЛЬНОЕ СВЕЧЕНИЕ (если включено)
            if (subtleGlow)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.05),
                      radius: 0.5,
                      colors: [
                        raptureGold.withOpacity(0.06),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.8],
                    ),
                  ),
                ),
              ),

            // КОНТЕНТ
            child,
          ],
        );
      },
    );
  }

  // (Оставлен для совместимости) Улучшенный фон с богатыми узорами ар-деко
  static Widget artDecoBackground({
    required Widget child,
    bool smallPattern = false,
    double patternOpacity = 0.25,
    double patternDensity = 60.0,
  }) {
    return luxuryArtDecoBackground(
      child: child,
      patternOpacity: patternOpacity,
      subtleGlow: true,
      scale: smallPattern ? 0.8 : 1.0,
    );
  }

  // (Оставлен для совместимости) Грандиозный фон с крупными узорами
  static Widget grandArtDecoBackground({
    required Widget child,
    double patternOpacity = 0.45,
    bool intricateDetails = true,
    bool showLightEffects = true,
  }) {
    return luxuryArtDecoBackground(
      child: child,
      patternOpacity: patternOpacity,
      subtleGlow: showLightEffects,
      scale: 1.0,
    );
  }

  // Ornate panel for important content
  static BoxDecoration artDecoPanelDecoration({bool prominent = false}) {
    return BoxDecoration(
      gradient: prominent
          ? LinearGradient(
              colors: [panelDark.withOpacity(0.98), abyssalBlue.withOpacity(0.95)],
            )
          : LinearGradient(
              colors: [panelDark.withOpacity(0.95), surfaceNavy.withOpacity(0.9)],
            ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: prominent ? raptureGold.withOpacity(0.6) : raptureGold.withOpacity(0.3),
        width: prominent ? 2.5 : 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.7),
          blurRadius: prominent ? 25 : 15,
          offset: const Offset(0, 12),
          spreadRadius: 1,
        ),
        BoxShadow(
          color: seaFoamGreen.withOpacity(0.05),
          blurRadius: prominent ? 40 : 25,
          spreadRadius: 2,
        ),
      ],
    );
  }

  // Geometric tile pattern with more elaborate design
  static BoxDecoration geometricTileDecoration({bool highlighted = false}) {
    return BoxDecoration(
      gradient: highlighted
          ? seaGradient
          : LinearGradient(
              colors: [
                panelDark.withOpacity(0.15),
                surfaceNavy.withOpacity(0.1),
                panelDark.withOpacity(0.08),
              ],
            ),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: highlighted ? seaFoamGreen.withOpacity(0.7) : raptureGold.withOpacity(0.2),
        width: highlighted ? 2.0 : 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(highlighted ? 0.4 : 0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
          spreadRadius: highlighted ? 1 : 0,
        ),
        if (highlighted)
          BoxShadow(
            color: seaFoamGreen.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 0),
            spreadRadius: 1,
          ),
      ],
    );
  }

  // Complete theme data
  static ThemeData get themeData {
    final base = ThemeData.dark(useMaterial3: false);

    return base.copyWith(
      scaffoldBackgroundColor: abyssalBlue,
      primaryColor: raptureGold,

      // ✅ NEW: более читаемое disabled для всего приложения (PWA/mobile тоже)
      disabledColor: ivoryCream.withOpacity(0.45),

      colorScheme: base.colorScheme.copyWith(
        background: abyssalBlue,
        surface: surfaceNavy,
        onSurface: ivoryCream,
        primary: raptureGold,
        secondary: seaFoamGreen,
        onPrimary: const Color(0xFF0A0A0A),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: abyssalBlue.withOpacity(0.95),
        titleTextStyle: heading.copyWith(fontSize: 22),
        iconTheme: iconTheme,
        elevation: 0,
        centerTitle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      textTheme: base.textTheme.copyWith(
  headlineSmall: heading,
  titleLarge: titleLarge,
  titleMedium: body.copyWith( // ✅ это важно для TextField/EditableText
    fontSize: 16,
    color: const Color.fromARGB(255, 254, 247, 50).withOpacity(0.9),
    fontFamily: 'PlayfairDisplay',
  ),
  bodyLarge: body,
  bodyMedium: body.copyWith(fontSize: 14),
  labelLarge: buttonText,
),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelDark.withOpacity(0.2),
        labelStyle: TextStyle(color: ivoryCream.withOpacity(0.85)),
        hintStyle: TextStyle(color: ivoryCream.withOpacity(0.55)),
        floatingLabelStyle: TextStyle(color: raptureGold.withOpacity(0.9)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: raptureGold.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: raptureGold.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seaFoamGreen.withOpacity(0.8), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // ✅ ВЕРНУТ ОРИГИНАЛЬНЫЙ СТИЛЬ КНОПОК
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(const Size(64, 48)),
          padding: MaterialStateProperty.all(
            const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          textStyle: MaterialStateProperty.all(buttonText),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return panelDark.withOpacity(0.35);
            }
            if (states.contains(MaterialState.pressed)) {
              return brassAccent.withOpacity(0.95);
            }
            return raptureGold;
          }),
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return ivoryCream.withOpacity(0.45);
            }
            return const Color(0xFF0A0A0A);
          }),
          elevation: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) return 0;
            if (states.contains(MaterialState.pressed)) return 2;
            return 6; // более "взрослая" высота, чем 8
          }),
          shadowColor: MaterialStateProperty.all(
            Colors.black.withOpacity(0.5),
          ),
          overlayColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return seaFoamGreen.withOpacity(0.10);
            }
            return null;
          }),
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceNavy.withOpacity(0.8),
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: raptureGold.withOpacity(0.2), width: 1),
        ),
        margin: const EdgeInsets.all(12),
      ),
      iconTheme: iconTheme,
      dialogTheme: DialogThemeData(
        backgroundColor: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: raptureGold.withOpacity(0.4), width: 2),
        ),
        elevation: 20,
        titleTextStyle: titleLarge.copyWith(fontSize: 20),
        contentTextStyle: body,
      ),
      dividerTheme: const DividerThemeData(
        color: Color.fromRGBO(212, 175, 55, 0.2),
        thickness: 1,
        space: 20,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceNavy.withOpacity(0.95),
        contentTextStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 10,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }

  static BoxDecoration artDecoCapsuleButton({Color? primaryColor}) {
  final color = primaryColor ?? raptureGold;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        color.withOpacity(0.9),
        color.withOpacity(0.7),
        color.withOpacity(0.5),
      ],
      stops: const [0.0, 0.5, 1.0],
    ),
    borderRadius: BorderRadius.circular(22),
    border: Border.all(
      color: ivoryCream.withOpacity(0.3),
      width: 1.5,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.5),
        blurRadius: 8,
        offset: const Offset(3, 3),
      ),
      BoxShadow(
        color: color.withOpacity(0.3),
        blurRadius: 4,
        offset: const Offset(-2, -2),
      ),
    ],
  );
}

// Декоративный элемент ар-деко (геометрический узор)
static Widget artDecoPattern({double size = 20, Color? color}) {
  final patternColor = color ?? raptureGold;
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          patternColor.withOpacity(0.8),
          patternColor.withOpacity(0.4),
        ],
      ),
      border: Border.all(
        color: ivoryCream.withOpacity(0.2),
        width: 1,
      ),
    ),
    child: Center(
      child: Container(
        width: size * 0.4,
        height: size * 0.4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: abyssalBlue.withOpacity(0.7),
          border: Border.all(
            color: ivoryCream.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
    ),
  );
}

// Стиль текста в духе ар-деко
static TextStyle artDecoText({double fontSize = 16, Color? color}) {
  return TextStyle(
    fontFamily: 'PlayfairDisplay',
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: color ?? ivoryCream,
    letterSpacing: 1.0,
    shadows: [
      Shadow(
        color: Colors.black.withOpacity(0.4),
        blurRadius: 2,
        offset: const Offset(1, 1),
      ),
    ],
  );
}
}
