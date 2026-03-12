// lib/widgets/decorative_elements.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DecorativeBackground с КРУПНЫМИ стильными узорами ар-деко
/// Узоры занимают ВЕСЬ ЭКРАН, создавая роскошный фон
class DecorativeBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool showBars;
  final bool showCorners;
  final bool showEmblem;
  final double patternIntensity;

  const DecorativeBackground({
    Key? key,
    required this.child,
    this.padding,
    this.showBars = true,
    this.showCorners = true,
    this.showEmblem = false,
    this.patternIntensity = 0.55, // УВЕЛИЧЕНО для максимальной видимости
  })  : assert(patternIntensity >= 0 && patternIntensity <= 1),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return TitanicTheme.grandArtDecoBackground(
      patternOpacity: patternIntensity,
      intricateDetails: true,
      showLightEffects: true,
      child: Stack(
        children: [
          // Дополнительная виньетка для глубины
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.25 * patternIntensity),
                  ],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
          ),
          
          // Свечение из центра
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.6,
                  colors: [
                    TitanicTheme.raptureGold.withOpacity(0.03 * patternIntensity),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Золотые акцентные полосы (если нужно)
          if (showBars) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 50,
              child: _goldBar(height: 8, radius: 4, opacity: 0.7),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 50,
              child: _goldBar(height: 8, radius: 4, opacity: 0.7),
            ),
          ],
          
          // КРУПНЫЕ угловые акценты
          if (showCorners) ...[
            Positioned(top: 40, left: 40, child: _grandCornerAccent()),
            Positioned(top: 40, right: 40, child: _grandCornerAccent()),
            Positioned(bottom: 40, left: 40, child: _grandCornerAccent()),
            Positioned(bottom: 40, right: 40, child: _grandCornerAccent()),
          ],
          
          // БОЛЬШАЯ стильная эмблема
          if (showEmblem)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        TitanicTheme.raptureGold.withOpacity(0.95),
                        TitanicTheme.brassAccent.withOpacity(0.85),
                        TitanicTheme.copperDetail.withOpacity(0.75),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.6),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: TitanicTheme.raptureGold.withOpacity(0.4),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.black.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    'TITANIC',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: TitanicTheme.abyssalBlue,
                      letterSpacing: 6.0,
                      shadows: [
                        Shadow(
                          color: Colors.white.withOpacity(0.3),
                          offset: const Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          
          // Дополнительные декоративные элементы
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.05 * patternIntensity,
                child: CustomPaint(
                  painter: _DecorativeOverlayPainter(),
                ),
              ),
            ),
          ),
          
          // Контент с безопасной зоной
          SafeArea(
            child: Padding(
              padding: padding ?? const EdgeInsets.all(24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _goldBar({double height = 6, double radius = 4, double opacity = 1.0}) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                TitanicTheme.raptureGold.withOpacity(0.9 * opacity),
                TitanicTheme.brassAccent.withOpacity(0.8 * opacity),
                TitanicTheme.raptureGold.withOpacity(0.9 * opacity),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6 * opacity),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: TitanicTheme.raptureGold.withOpacity(0.3 * opacity),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grandCornerAccent() {
    return Transform.rotate(
      angle: -math.pi / 4,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              TitanicTheme.raptureGold.withOpacity(0.95),
              TitanicTheme.brassAccent.withOpacity(0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: TitanicTheme.raptureGold.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(
            color: Colors.black.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.diamond,
            size: 24,
            color: TitanicTheme.abyssalBlue,
          ),
        ),
      ),
    );
  }
}

/// Дополнительный декоративный слой для мелких деталей
class _DecorativeOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = TitanicTheme.raptureGold.withOpacity(0.1);

    // Сетка
    final gridSpacing = 60.0;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Точки на пересечениях
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = TitanicTheme.seaFoamGreen.withOpacity(0.05);

    for (double x = gridSpacing; x < size.width; x += gridSpacing * 2) {
      for (double y = gridSpacing; y < size.height; y += gridSpacing * 2) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// GlassPanel — improved glass effect using BackdropFilter + inner gradient + gilded rim.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final BoxConstraints? constraints;
  final bool elevated;
  final double opacity;

  const GlassPanel({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
    this.constraints,
    this.elevated = false,
    this.opacity = 0.12, // Уменьшено для лучшей видимости фона
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sigma = elevated ? 12.0 : 8.0;
    final borderAlpha = elevated ? 0.3 : 0.2;
    final shadowOpacity = elevated ? 0.7 : 0.5;

    return ConstrainedBox(
      constraints: constraints ?? const BoxConstraints(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: TitanicTheme.panelDark.withOpacity(opacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: TitanicTheme.panelDark.withOpacity(borderAlpha),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(shadowOpacity),
                  blurRadius: elevated ? 30 : 20,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: TitanicTheme.raptureGold.withOpacity(0.04),
                  blurRadius: elevated ? 35 : 25,
                  spreadRadius: 1,
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TitanicTheme.panelDark.withOpacity(0.15),
                  TitanicTheme.panelDark.withOpacity(0.05),
                ],
              ),
            ),
            child: DefaultTextStyle.merge(
              style: TitanicTheme.body,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
