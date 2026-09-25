import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Quiet ornamental pieces in the app's classical register: the eight-pointed
/// star (khatam) of Islamic geometry, hairline rules that fade at their ends,
/// and a slender progress ring.
///
/// All of it is decoration in the strict sense the palette documents: these
/// widgets carry no text and convey nothing that the words around them do not
/// also say, so the warm gold they are usually painted in never has to carry
/// meaning at less than AA contrast.
class EightPointStar extends StatelessWidget {
  const EightPointStar({required this.size, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _EightPointStarPainter(color),
      ),
    );
  }
}

class _EightPointStarPainter extends CustomPainter {
  const _EightPointStarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final Offset centre = size.center(Offset.zero);
    final double outer = size.shortestSide / 2;
    // The classical khatam proportion: inner radius at cos(22.5°) of the
    // outer, which is what two overlapped squares produce.
    final double inner = outer * math.cos(math.pi / 8) * 0.62;

    final Path path = Path();
    for (int i = 0; i < 16; i++) {
      final double radius = i.isEven ? outer : inner;
      final double angle = (math.pi / 8) * i - math.pi / 2;
      final Offset point = centre +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EightPointStarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A centred star between two hairlines that fade towards the page edges.
class OrnamentalDivider extends StatelessWidget {
  const OrnamentalDivider({required this.color, this.starSize = 10, super.key});

  final Color color;
  final double starSize;

  @override
  Widget build(BuildContext context) {
    Widget rule({required bool fadeStart}) {
      return Expanded(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: fadeStart
                  ? <Color>[color.withValues(alpha: 0), color]
                  : <Color>[color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          rule(fadeStart: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: EightPointStar(size: starSize, color: color),
          ),
          rule(fadeStart: false),
        ],
      ),
    );
  }
}

/// A thin circular progress ring with its content set in the middle.
///
/// Purely visual: callers put the spoken meaning in the text they centre
/// inside it, so the ring itself is excluded from semantics.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.progress,
    required this.size,
    required this.trackColor,
    required this.fillColor,
    required this.child,
    this.strokeWidth = 8,
    super.key,
  });

  /// 0.0–1.0.
  final double progress;
  final double size;
  final Color trackColor;
  final Color fillColor;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        // The same quiet fill the linear bars use, rather than a jump.
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
        builder: (BuildContext context, double value, Widget? inner) {
          return CustomPaint(
            painter: _RingPainter(
              progress: value,
              trackColor: trackColor,
              fillColor: fillColor,
              strokeWidth: strokeWidth,
            ),
            child: inner,
          );
        },
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(strokeWidth / 2);

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);

    if (progress <= 0) return;
    final Paint fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    // From the top, clockwise, the way a clock face is read.
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
