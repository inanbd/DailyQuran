import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Daily Quran's mark — an open mushaf beneath an eight-point star, gold and
/// paper on the app's green — drawn in code so that every size, from a 20px
/// iOS settings icon to Google Play's 512px listing icon, is rendered sharp
/// from the one source.
///
/// The mark is drawn in its own units, centred on the origin: [markHeight]
/// tall and 47 wide. [paintMark] scales it to whatever it is drawn on.
abstract final class AppIconArt {
  /// `AppColors.light.accent`, the app's one brand colour.
  static const Color green = Color(0xFF295F4E);

  /// A lighter and a darker step of [green], for the background's soft glow.
  static const Color _glow = Color(0xFF32705D);
  static const Color _shade = Color(0xFF1F4A3C);

  /// `AppColors.dark.warm`: the brighter of the app's two golds, the one that
  /// holds up on green.
  static const Color gold = Color(0xFFC9A469);

  /// `AppColors.light.background`, the reading screen's paper.
  static const Color paper = Color(0xFFFAF9F6);

  /// The mark's height in its own units, star tip to spine.
  static const double markHeight = 50;

  /// Half the gap between the two pages, which shows the background through
  /// the spine.
  static const double _spine = 1.2;

  /// The green behind the mark, glowing a little above centre.
  static void paintBackground(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(
          rect.center.translate(0, -rect.height * 0.12),
          rect.longestSide * 0.72,
          const <Color>[_glow, _shade],
        ),
    );
  }

  /// Draws the mark [height] tall, centred on [center]. A [tint] draws every
  /// part in that one colour, for Android's themed (monochrome) icon.
  static void paintMark(
    Canvas canvas,
    Offset center,
    double height, {
    Color? tint,
  }) {
    final double scale = height / markHeight;
    final Paint gilt = Paint()..color = tint ?? gold;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..drawPath(_star(), gilt)
      ..drawPath(_mirrored(_coverHalf()), gilt)
      ..drawPath(_mirrored(_pageHalf()), Paint()..color = tint ?? paper)
      ..restore();
  }

  /// A Rub el Hizb: two squares, one turned an eighth of a turn, with the
  /// centre open.
  static Path _star() {
    const Offset centre = Offset(0, -13);
    const double radius = 12;
    Path square(double turn) {
      final Path path = Path();
      for (int corner = 0; corner < 4; corner++) {
        final double angle = turn + corner * math.pi / 2;
        final Offset point =
            centre + Offset(math.cos(angle), math.sin(angle)) * radius;
        corner == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    final Path star = Path.combine(
      PathOperation.union,
      square(-math.pi / 2),
      square(-math.pi / 4),
    );
    return Path.combine(
      PathOperation.difference,
      star,
      Path()..addOval(Rect.fromCircle(center: centre, radius: 3.4)),
    );
  }

  /// The left-hand page, rising out of the spine and flattening towards its
  /// outer edge, the way an open book lies.
  static Path _pageHalf() => Path()
    ..moveTo(-_spine, 5)
    ..quadraticBezierTo(-6, 0.5, -22, 1)
    ..lineTo(-22, 18)
    ..quadraticBezierTo(-6, 17.5, -_spine, 22)
    ..close();

  /// The left-hand board of the cover, showing as a gold edge outside and
  /// below the page.
  static Path _coverHalf() => Path()
    ..moveTo(-_spine, 8)
    ..quadraticBezierTo(-6, 3.5, -23.5, 3)
    ..lineTo(-23.5, 20.5)
    ..quadraticBezierTo(-6, 20.5, -_spine, 25)
    ..close();

  /// [left] and its reflection across the spine, as one path.
  static Path _mirrored(Path left) {
    final Float64List flip = Float64List.fromList(<double>[
      -1, 0, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]);
    return Path()
      ..addPath(left, Offset.zero)
      ..addPath(left.transform(flip), Offset.zero);
  }
}
