/// Regenerate native launch artwork with:
/// flutter test scripts/prepare_branding_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/shared/widgets/fitnep_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _logoWidth = 180.0;
const _logoHeight = 173.0;
const _androidSplashSize = 288.0;
const _androidDensities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};
const _appleImages = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Render native ${brightness.name} launch artwork', (
      tester,
    ) async {
      final dark = brightness == Brightness.dark;
      await tester.runAsync(() async {
        await (FontLoader('Inter')..addFont(
              rootBundle.load('lib/shared/assets/fonts/Inter-Variable.ttf'),
            ))
            .load();
      });
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        Theme(
          data: dark ? AppTheme.dark : AppTheme.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: captureKey,
                child: const SizedBox(
                  width: _logoWidth,
                  height: _logoHeight,
                  child: Center(child: FitNepWordmark(width: _logoWidth)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage(FitNepWordmark.assetPath),
          tester.element(find.byType(FitNepWordmark)),
        );
      });
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final capture =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final logo = await capture.toImage(pixelRatio: 4);
        try {
          for (final entry in _androidDensities.entries) {
            final density = entry.key;
            final scale = entry.value;
            final appearance = dark ? '-night' : '';
            final directory =
                'android/app/src/main/res/drawable$appearance-$density';
            await _writePng(logo, '$directory/fitnep_splash.png', scale);
            // Android 12 and later mask the icon around its center.
            await _writePng(
              logo,
              '$directory/fitnep_splash_android12.png',
              scale,
              canvasSize: _androidSplashSize,
            );
          }
          for (final scale in [1, 2, 3]) {
            final appearance = dark ? 'Dark' : '';
            final suffix = scale == 1 ? '' : '@${scale}x';
            await _writePng(
              logo,
              '$_appleImages/LaunchImage$appearance$suffix.png',
              scale.toDouble(),
            );
          }
        } finally {
          logo.dispose();
        }
      });
    });
  }
}

Future<void> _writePng(
  ui.Image logo,
  String path,
  double scale, {
  double? canvasSize,
}) async {
  final width = ((canvasSize ?? _logoWidth) * scale).round();
  final height = ((canvasSize ?? _logoHeight) * scale).round();
  final logoWidth = (_logoWidth * scale).roundToDouble();
  final logoHeight = (_logoHeight * scale).roundToDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    logo,
    Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
    Rect.fromLTWH(
      (width - logoWidth) / 2,
      (height - logoHeight) / 2,
      logoWidth,
      logoHeight,
    ),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final bitmap = await picture.toImage(width, height);
  picture.dispose();
  try {
    final png = (await bitmap.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    bitmap.dispose();
  }
}
