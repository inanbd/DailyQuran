// Renders the app icon at every size Android, iOS and Google Play ask for,
// plus the Play listing's feature graphic, from the drawing in app_icon.dart.
//
// It runs as a test only because the Flutter test runner is the one headless
// way to draw with dart:ui. It is not part of the suite: `flutter test` looks
// in test/ alone.
//
// Usage:
//
//   flutter test tool/icon/generate_icons_test.dart
//
// Android's adaptive icon itself (mipmap-anydpi-v26/ic_launcher.xml) is
// written by hand and only names the layers this renders.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_icon.dart';
import 'png.dart';

const String _androidRes = 'android/app/src/main/res';
const String _iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const String _playImages = 'fastlane/metadata/android/en-US/images';

/// Android's density buckets and their scale from mdpi.
const Map<String, double> _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

/// Every file the iOS asset catalogue names, with its size in pixels.
const Map<String, int> _iosSizes = <String, int>{
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders the app icon and store graphics', () async {
    for (final MapEntry<String, double> density in _densities.entries) {
      final String folder = '$_androidRes/mipmap-${density.key}';

      // Adaptive layers, 108dp square. Launchers show the middle 72dp and
      // guarantee the middle 66dp, which the mark stays inside.
      final int layer = (108 * density.value).round();
      await _render('$folder/ic_launcher_background.png', layer, layer,
          (ui.Canvas canvas, ui.Rect rect) {
        AppIconArt.paintBackground(canvas, rect);
      });
      await _render('$folder/ic_launcher_foreground.png', layer, layer,
          (ui.Canvas canvas, ui.Rect rect) {
        AppIconArt.paintMark(canvas, rect.center, rect.height * 50 / 108);
      }, alpha: true);
      await _render('$folder/ic_launcher_monochrome.png', layer, layer,
          (ui.Canvas canvas, ui.Rect rect) {
        AppIconArt.paintMark(
          canvas,
          rect.center,
          rect.height * 50 / 108,
          tint: const ui.Color(0xFFFFFFFF),
        );
      }, alpha: true);

      // Before Android 8 the launcher shows this as it is, so it carries its
      // own shape: a rounded square with the usual 2dp margin.
      final int legacy = (48 * density.value).round();
      await _render('$folder/ic_launcher.png', legacy, legacy,
          (ui.Canvas canvas, ui.Rect rect) {
        final ui.Rect tile = rect.deflate(rect.width * 2 / 48);
        canvas
          ..save()
          ..clipRRect(
            ui.RRect.fromRectAndRadius(
              tile,
              ui.Radius.circular(tile.width * 0.2),
            ),
          );
        AppIconArt.paintBackground(canvas, tile);
        AppIconArt.paintMark(canvas, tile.center, tile.height * 0.62);
        canvas.restore();
      }, alpha: true);
    }

    // iOS and Play both take a full square and round the corners themselves.
    // iOS refuses an alpha channel; Play asks for one (a 32-bit PNG).
    for (final MapEntry<String, int> icon in _iosSizes.entries) {
      await _render('$_iosIcons/${icon.key}', icon.value, icon.value, _square);
    }
    await _render('$_playImages/icon.png', 512, 512, _square, alpha: true);

    await _loadInter();
    await _render('$_playImages/featureGraphic.png', 1024, 500, _feature);
  });
}

void _square(ui.Canvas canvas, ui.Rect rect) {
  AppIconArt.paintBackground(canvas, rect);
  AppIconArt.paintMark(canvas, rect.center, rect.height * 0.58);
}

/// Google Play's 1024 × 500 banner: the mark, the name, and what it is for.
void _feature(ui.Canvas canvas, ui.Rect rect) {
  AppIconArt.paintBackground(canvas, rect);
  AppIconArt.paintMark(canvas, const ui.Offset(250, 250), 280);

  const double left = 440;
  const double width = 520;
  final ui.Paragraph title = _paragraph(
    'Daily Quran',
    size: 76,
    weight: 600,
    color: AppIconArt.paper,
    width: width,
  );
  final ui.Paragraph tagline = _paragraph(
    'An ayah a day, or the whole Qur’an by a date you choose.',
    size: 30,
    weight: 400,
    color: AppIconArt.paper.withValues(alpha: 0.85),
    width: width,
    lineHeight: 1.35,
  );
  const double ruleGap = 22;
  const double rule = 3;
  final double block =
      title.height + ruleGap + rule + ruleGap + tagline.height;
  double y = rect.center.dy - block / 2;

  canvas.drawParagraph(title, ui.Offset(left, y));
  y += title.height + ruleGap;
  canvas.drawRect(
    ui.Rect.fromLTWH(left + 4, y, 72, rule),
    ui.Paint()..color = AppIconArt.gold,
  );
  y += rule + ruleGap;
  canvas.drawParagraph(tagline, ui.Offset(left, y));
}

ui.Paragraph _paragraph(
  String text, {
  required double size,
  required double weight,
  required ui.Color color,
  required double width,
  double lineHeight = 1.15,
}) {
  final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(fontFamily: 'Inter', fontSize: size, height: lineHeight),
  )
    ..pushStyle(
      ui.TextStyle(
        color: color,
        fontFamily: 'Inter',
        fontSize: size,
        height: lineHeight,
        fontVariations: <ui.FontVariation>[ui.FontVariation('wght', weight)],
      ),
    )
    ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: width));
}

/// The test runner draws text in a placeholder font until it is given a real
/// one; this is the app's own.
Future<void> _loadInter() async {
  final Uint8List bytes =
      File('assets/fonts/Inter-Variable.ttf').readAsBytesSync();
  await (FontLoader('Inter')..addFont(Future<ByteData>.value(bytes.buffer.asByteData())))
      .load();
}

Future<void> _render(
  String path,
  int width,
  int height,
  void Function(ui.Canvas canvas, ui.Rect rect) paint, {
  bool alpha = false,
}) async {
  final ui.Rect rect =
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder, rect), rect);
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData? pixels =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(
      Png.encode(pixels!.buffer.asUint8List(), width, height, alpha: alpha),
    );
}
