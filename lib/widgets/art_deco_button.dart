// lib/widgets/art_deco_button.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:titanic/theme/app_theme.dart';

class ArtDecoButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final bool expanded;
  final IconData? icon;
  final Color? customColor;
  final Color? customTextColor;

  const ArtDecoButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.primary = false,
    this.loading = false,
    this.padding,
    this.width,
    this.expanded = false,
    this.icon,
    this.customColor,
    this.customTextColor,
  }) : super(key: key);

  @override
  State<ArtDecoButton> createState() => _ArtDecoButtonState();
}

class _ArtDecoButtonState extends State<ArtDecoButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.onPressed == null || widget.loading;

    final Color baseBg = widget.customColor ??
        (widget.primary ? TitanicTheme.panelDark : TitanicTheme.surfaceNavy);
    final Color bgColor = isDisabled
        ? TitanicTheme.panelDark.withOpacity(0.45)
        : (_pressed ? baseBg.withOpacity(0.92) : baseBg);

    // “Золото” и “латунь” из темы — под референс (арт-деко линии)
    final Color gold = TitanicTheme.raptureGold;
    final Color brass = TitanicTheme.brassAccent;
    final Color ivory = TitanicTheme.ivoryCream;

    final Color border = isDisabled
        ? gold.withOpacity(0.25)
        : (widget.primary ? gold.withOpacity(0.95) : gold.withOpacity(0.55));

    final Color accent = isDisabled
        ? brass.withOpacity(0.15)
        : (widget.primary ? brass.withOpacity(0.55) : brass.withOpacity(0.35));

    final Color textColor = widget.customTextColor ??
        (isDisabled
            ? ivory.withOpacity(0.45)
            : (widget.primary ? gold.withOpacity(0.95) : ivory.withOpacity(0.92)));

    final EdgeInsetsGeometry pad = widget.padding ??
        const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: 18,
            color: textColor,
          ),
          const SizedBox(width: 10),
        ],
        if (widget.loading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: textColor,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: theme.textTheme.labelLarge?.copyWith(
              color: textColor,
              fontSize: 15,
              fontFamily: 'PlayfairDisplay',
              fontWeight: widget.primary ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 1.0,
              height: 1.1,
            ),
          ),
        ),
      ],
    );

    final decorated = RepaintBoundary(
      child: CustomPaint(
        painter: _ArtDecoOrnamentPainter(
          borderColor: border,
          accentColor: accent,
          glowColor: widget.primary ? gold.withOpacity(0.12) : gold.withOpacity(0.06),
          pressed: _pressed,
          disabled: isDisabled,
        ),
        child: Container(
          width: widget.width ?? (widget.expanded ? double.infinity : null),
          padding: pad,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(_pressed ? 0.18 : 0.28),
                      blurRadius: _pressed ? 8 : 14,
                      offset: Offset(0, _pressed ? 2 : 6),
                    ),
                    if (widget.primary)
                      BoxShadow(
                        color: gold.withOpacity(_pressed ? 0.10 : 0.16),
                        blurRadius: _pressed ? 10 : 18,
                        offset: const Offset(0, 0),
                      ),
                  ],
          ),
          child: Center(child: content),
        ),
      ),
    );

    Widget out = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : widget.onPressed,
        onHighlightChanged: (v) {
          if (isDisabled) return;
          setState(() => _pressed = v);
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: widget.primary
            ? TitanicTheme.raptureGold.withOpacity(0.18)
            : TitanicTheme.ivoryCream.withOpacity(0.08),
        highlightColor: Colors.transparent,
        child: decorated,
      ),
    );

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: widget.text,
      child: out,
    );
  }
}

class _ArtDecoOrnamentPainter extends CustomPainter {
  final Color borderColor;
  final Color accentColor;
  final Color glowColor;
  final bool pressed;
  final bool disabled;

  _ArtDecoOrnamentPainter({
    required this.borderColor,
    required this.accentColor,
    required this.glowColor,
    required this.pressed,
    required this.disabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    // Outer stroke
    final pBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = borderColor
      ..strokeJoin = StrokeJoin.round;

    // Inner stroke (тонкая линия как в рефе)
    final pInner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = accentColor.withOpacity(disabled ? 0.5 : 1.0);

    // Glow (очень лёгкое свечение внутри)
    final pGlow = Paint()
      ..style = PaintingStyle.fill
      ..color = glowColor;

    canvas.drawRRect(r, pGlow);
    canvas.drawRRect(r, pBorder);

    final inset = 3.0;
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(10),
    );
    canvas.drawRRect(inner, pInner);

    // Decorative top/bottom lines + center diamond (как на референсе)
    final centerX = size.width / 2;
    final topY = 10.0;
    final botY = size.height - 10.0;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.square
      ..color = borderColor.withOpacity(disabled ? 0.5 : 1.0);

    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.square
      ..color = accentColor.withOpacity(disabled ? 0.45 : 0.9);

    // Top ornament
    _drawOrnamentLine(canvas, size, y: topY, centerX: centerX, line: line, thin: thin, upside: true);

    // Bottom ornament
    _drawOrnamentLine(canvas, size, y: botY, centerX: centerX, line: line, thin: thin, upside: false);

    // Corner ticks (квадратные углы/ступени)
    _drawCornerTicks(canvas, size, line, thin);
  }

  void _drawOrnamentLine(
    Canvas canvas,
    Size size, {
    required double y,
    required double centerX,
    required Paint line,
    required Paint thin,
    required bool upside,
  }) {
    final left = 14.0;
    final right = size.width - 14.0;
    final midSpan = math.min(140.0, size.width * 0.52);
    final midL = centerX - midSpan / 2;
    final midR = centerX + midSpan / 2;

    // Long line segments
    canvas.drawLine(Offset(left, y), Offset(midL, y), line);
    canvas.drawLine(Offset(midR, y), Offset(right, y), line);

    // Small inner parallel line
    canvas.drawLine(Offset(left + 10, y + (upside ? 2 : -2)), Offset(midL - 10, y + (upside ? 2 : -2)), thin);
    canvas.drawLine(Offset(midR + 10, y + (upside ? 2 : -2)), Offset(right - 10, y + (upside ? 2 : -2)), thin);

    // Center diamond
    final d = 7.0;
    final diamond = Path()
      ..moveTo(centerX, y - d)
      ..lineTo(centerX + d, y)
      ..lineTo(centerX, y + d)
      ..lineTo(centerX - d, y)
      ..close();
    canvas.drawPath(diamond, Paint()..color = line.color.withOpacity(0.9));

    // Small side chevrons near diamond
    final wing = 18.0;
    final chevronH = 6.0;
    final c1 = Path()
      ..moveTo(centerX - d - 4, y)
      ..lineTo(centerX - d - 4 - wing, y)
      ..lineTo(centerX - d - 4 - wing + 8, y - (upside ? chevronH : -chevronH));
    canvas.drawPath(c1, thin);

    final c2 = Path()
      ..moveTo(centerX + d + 4, y)
      ..lineTo(centerX + d + 4 + wing, y)
      ..lineTo(centerX + d + 4 + wing - 8, y - (upside ? chevronH : -chevronH));
    canvas.drawPath(c2, thin);

    // Bottom-only scallop (намёк на “арки” из рефа)
    if (!upside) {
      final scallopW = 44.0;
      final scallopH = 10.0;
      final startX = centerX - scallopW / 2;
      final p = Path();
      p.moveTo(startX, y);
      p.quadraticBezierTo(centerX - scallopW * 0.25, y - scallopH, centerX, y);
      p.quadraticBezierTo(centerX + scallopW * 0.25, y - scallopH, centerX + scallopW / 2, y);
      canvas.drawPath(p, thin);
    }
  }

  void _drawCornerTicks(Canvas canvas, Size size, Paint line, Paint thin) {
    final tick = 10.0;
    final inset = 10.0;

    // TL
    canvas.drawLine(Offset(inset, inset + tick), Offset(inset, inset), line);
    canvas.drawLine(Offset(inset, inset), Offset(inset + tick, inset), line);
    canvas.drawLine(Offset(inset + 2, inset + tick), Offset(inset + 2, inset + 2), thin);
    canvas.drawLine(Offset(inset + 2, inset + 2), Offset(inset + tick, inset + 2), thin);

    // TR
    canvas.drawLine(Offset(size.width - inset - tick, inset), Offset(size.width - inset, inset), line);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + tick), line);
    canvas.drawLine(Offset(size.width - inset - tick, inset + 2), Offset(size.width - inset - 2, inset + 2), thin);
    canvas.drawLine(Offset(size.width - inset - 2, inset + 2), Offset(size.width - inset - 2, inset + tick), thin);

    // BL
    canvas.drawLine(Offset(inset, size.height - inset - tick), Offset(inset, size.height - inset), line);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset + tick, size.height - inset), line);
    canvas.drawLine(Offset(inset + 2, size.height - inset - tick), Offset(inset + 2, size.height - inset - 2), thin);
    canvas.drawLine(Offset(inset + 2, size.height - inset - 2), Offset(inset + tick, size.height - inset - 2), thin);

    // BR
    canvas.drawLine(
      Offset(size.width - inset - tick, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      line,
    );
    canvas.drawLine(
      Offset(size.width - inset, size.height - inset - tick),
      Offset(size.width - inset, size.height - inset),
      line,
    );
    canvas.drawLine(
      Offset(size.width - inset - tick, size.height - inset - 2),
      Offset(size.width - inset - 2, size.height - inset - 2),
      thin,
    );
    canvas.drawLine(
      Offset(size.width - inset - 2, size.height - inset - tick),
      Offset(size.width - inset - 2, size.height - inset - 2),
      thin,
    );
  }

  @override
  bool shouldRepaint(covariant _ArtDecoOrnamentPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.pressed != pressed ||
        oldDelegate.disabled != disabled;
  }
}

// Вспомогательный виджет для кнопок с иконкой
class ArtDecoIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool primary;
  final bool loading;
  final double size;

  const ArtDecoIconButton({
    Key? key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.primary = false,
    this.loading = false,
    this.size = 40,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;

    final gold = TitanicTheme.raptureGold;
    final brass = TitanicTheme.brassAccent;
    final bg = primary ? TitanicTheme.panelDark : TitanicTheme.surfaceNavy;

    return Tooltip(
      message: tooltip ?? '',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDisabled ? null : onPressed,
            borderRadius: BorderRadius.circular(10),
            splashColor: gold.withOpacity(0.18),
            child: CustomPaint(
              painter: _IconButtonFramePainter(
                border: isDisabled ? gold.withOpacity(0.22) : gold.withOpacity(primary ? 0.9 : 0.55),
                accent: isDisabled ? brass.withOpacity(0.14) : brass.withOpacity(0.35),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isDisabled ? bg.withOpacity(0.45) : bg,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isDisabled
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDisabled ? gold.withOpacity(0.35) : gold.withOpacity(0.9),
                          ),
                        )
                      : Icon(
                          icon,
                          size: 20,
                          color: isDisabled ? TitanicTheme.ivoryCream.withOpacity(0.45) : gold.withOpacity(0.95),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButtonFramePainter extends CustomPainter {
  final Color border;
  final Color accent;

  _IconButtonFramePainter({required this.border, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    final p1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = border;

    final p2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = accent.withOpacity(0.9);

    canvas.drawRRect(r, p1);

    final inset = 3.0;
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      const Radius.circular(8),
    );
    canvas.drawRRect(inner, p2);

    // tiny center diamond
    final cx = size.width / 2;
    final cy = size.height / 2;
    final d = 4.5;
    final diamond = Path()
      ..moveTo(cx, cy - d)
      ..lineTo(cx + d, cy)
      ..lineTo(cx, cy + d)
      ..lineTo(cx - d, cy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = border.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(covariant _IconButtonFramePainter oldDelegate) {
    return oldDelegate.border != border || oldDelegate.accent != accent;
  }
}
