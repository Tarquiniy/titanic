// lib/widgets/decorative_elements.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DecorativeBackground
/// - art-deco inspired layered background (gradient base + vignette + stripes)
/// - extra ornaments: diamonds grid, corner rings, floating particles, thin radial flares
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
    this.patternIntensity = 0.22,
  })  : assert(patternIntensity >= 0 && patternIntensity <= 1),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final topBarOffset = MediaQuery.of(context).size.height > 700 ? 96.0 : 72.0;
    final bottomBarOffset = MediaQuery.of(context).size.height > 700 ? 96.0 : 72.0;

    return Container(
      decoration: BoxDecoration(gradient: TitanicTheme.backgroundGradient),
      child: Stack(
        children: [
          // deep vignette
          Positioned.fill(child: _buildVignette()),

          // angled stripes
          Positioned.fill(child: _buildStripedOverlay(patternIntensity)),

          // sweep / metallic sheen
          Positioned.fill(child: _buildSweepOverlay(patternIntensity * 0.9)),

          // diamonds grid — subtle repeating geometric motif
          Positioned.fill(child: _buildDiamondGrid(patternIntensity * 0.9)),

          // floating particle accents (small circles) — decorative, very subtle
          Positioned.fill(child: _buildParticleScatter(patternIntensity * 0.6)),

          // delicate radial flares (top-left / bottom-right)
          Positioned.fill(child: _buildRadialFlares(patternIntensity * 0.6)),

          // golden horizontal bars (top & bottom)
          if (showBars) ...[
            Positioned(
              left: 0,
              right: 0,
              top: topBarOffset - 12,
              child: _goldBar(height: 8, radius: 6),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomBarOffset - 12,
              child: _goldBar(height: 8, radius: 6),
            ),
          ],

          // corner ornaments (use TitanicTheme.cornerOrnament)
          if (showCorners) ...[
            Positioned(top: 20, left: 20, child: TitanicTheme.cornerOrnament(size: 22)),
            Positioned(top: 20, right: 20, child: TitanicTheme.cornerOrnament(size: 22)),
            Positioned(bottom: 20, left: 20, child: TitanicTheme.cornerOrnament(size: 22)),
            Positioned(bottom: 20, right: 20, child: TitanicTheme.cornerOrnament(size: 22)),
          ],

          // corner rings (concentric) for extra art-deco flair
          if (showCorners) ...[
            Positioned(top: 18, left: 72, child: _cornerRing(32, 2.6)),
            Positioned(top: 18, right: 72, child: _cornerRing(32, 2.6)),
            Positioned(bottom: 18, left: 72, child: _cornerRing(32, 2.6)),
            Positioned(bottom: 18, right: 72, child: _cornerRing(32, 2.6)),
          ],

          // optional small emblem (top center)
          if (showEmblem)
            Positioned(
              top: 28,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: TitanicTheme.goldGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.38), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Text('TITANIC', style: TitanicTheme.titleLarge.copyWith(fontSize: 13)),
                ),
              ),
            ),

          // content (safe area + optional padding)
          SafeArea(
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVignette() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.16),
          radius: 1.25,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.50),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
    );
  }

  Widget _buildStripedOverlay(double intensity) {
    final stripe = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TitanicTheme.panelTint.withOpacity(0.006 * intensity * 6),
            Colors.transparent,
            TitanicTheme.panelTint.withOpacity(0.006 * intensity * 9),
            Colors.transparent,
          ],
          stops: const [0.0, 0.06, 0.08, 0.14],
          tileMode: TileMode.repeated,
        ),
      ),
    );

    return IgnorePointer(
      child: Transform.rotate(angle: -0.36, child: Opacity(opacity: (0.40 * intensity).clamp(0.03, 0.6), child: stripe)),
    );
  }

  Widget _buildSweepOverlay(double intensity) {
    return IgnorePointer(
      child: Opacity(
        opacity: (intensity * 0.28).clamp(0.02, 0.45),
        child: Container(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              center: Alignment(-0.6, -0.4),
              startAngle: 0,
              endAngle: 3.14,
              colors: [
                Colors.transparent,
                TitanicTheme.gold.withOpacity(0.06 * intensity),
                Colors.transparent,
              ],
              tileMode: TileMode.clamp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiamondGrid(double intensity) {
    // create a subtle repeating diamond pattern using a rotated repeated linear gradient
    return IgnorePointer(
      child: Opacity(
        opacity: (intensity * 0.26).clamp(0.02, 0.45),
        child: Transform.rotate(
          angle: 0.785398, // 45 degrees to create diamonds
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  TitanicTheme.panelTint.withOpacity(0.004 * intensity * 8),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.03, 0.06],
                tileMode: TileMode.repeated,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticleScatter(double intensity) {
    // a few subtle circular accents placed in corners to add depth
    return IgnorePointer(
      child: Opacity(
        opacity: (intensity * 0.9).clamp(0.02, 0.6),
        child: Stack(
          children: [
            Positioned(left: 40, top: 120, child: _particle(6, 0.12 + intensity * 0.06)),
            Positioned(right: 36, top: 180, child: _particle(8, 0.10 + intensity * 0.06)),
            Positioned(left: 24, bottom: 140, child: _particle(5, 0.08 + intensity * 0.05)),
            Positioned(right: 18, bottom: 96, child: _particle(7, 0.10 + intensity * 0.05)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadialFlares(double intensity) {
    return IgnorePointer(
      child: Opacity(
        opacity: (intensity * 0.18).clamp(0.01, 0.35),
        child: Stack(
          children: [
            Positioned(
              left: -80,
              top: -60,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [TitanicTheme.gold.withOpacity(0.06 * intensity), Colors.transparent],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -70,
              bottom: -60,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [TitanicTheme.gold.withOpacity(0.05 * intensity), Colors.transparent],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goldBar({double height = 6, double radius = 4}) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 1.0,
        child: Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            gradient: TitanicTheme.goldGradient,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 10, offset: const Offset(0, 6)),
              BoxShadow(color: TitanicTheme.gold.withOpacity(0.06), blurRadius: 10, spreadRadius: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cornerRing(double size, double stroke) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: TitanicTheme.warmGold.withOpacity(0.88), width: stroke),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.34), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Center(
        child: Container(
          width: size * 0.52,
          height: size * 0.52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: TitanicTheme.warmGold.withOpacity(0.32), width: stroke * 0.6),
          ),
        ),
      ),
    );
  }

  Widget _particle(double diameter, double opacity) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: TitanicTheme.gold.withOpacity(opacity),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: TitanicTheme.gold.withOpacity(opacity * 0.45), blurRadius: 4, offset: const Offset(0, 1))],
      ),
    );
  }
}

/// GlassPanel — improved glass effect using BackdropFilter + inner gradient + gilded rim.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final BoxConstraints? constraints;
  final bool elevated;

  const GlassPanel({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.constraints,
    this.elevated = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sigma = elevated ? 10.0 : 6.0;
    final borderAlpha = elevated ? 0.26 : 0.14;
    final shadowOpacity = elevated ? 0.68 : 0.48;

    return ConstrainedBox(
      constraints: constraints ?? const BoxConstraints(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: TitanicTheme.panelTint.withOpacity(0.18),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: TitanicTheme.warmGold.withOpacity(borderAlpha), width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(shadowOpacity), blurRadius: elevated ? 24 : 14, offset: const Offset(0, 12)),
                BoxShadow(color: TitanicTheme.gold.withOpacity(0.03), blurRadius: elevated ? 28 : 18, spreadRadius: 1),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TitanicTheme.panelTint.withOpacity(0.26),
                  TitanicTheme.panelTint.withOpacity(0.06),
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
