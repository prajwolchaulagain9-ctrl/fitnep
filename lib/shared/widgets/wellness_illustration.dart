import 'dart:math' as math;

import 'package:flutter/material.dart';

enum WellnessScene { nutrition, movement, care }

/// Original vector characters stay sharp, work offline, and need no image fetch.
class WellnessIllustration extends StatelessWidget {
  const WellnessIllustration({
    super.key,
    this.scene = WellnessScene.nutrition,
    this.size = 120,
  });
  final WellnessScene scene;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _WellnessPainter(scene, colors)),
      ),
    );
  }
}

class _WellnessPainter extends CustomPainter {
  const _WellnessPainter(this.scene, this.colors);
  final WellnessScene scene;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 160);
    final ink = const Color(0xFF25343A);
    final orange = const Color(0xFFFF923F);
    final green = const Color(0xFF79A987);
    final backdrop = Color.alphaBlend(
      colors.primary.withValues(alpha: .10),
      colors.primaryContainer,
    );
    void oval(Rect rect, Color color) =>
        canvas.drawOval(rect, Paint()..color = color);
    void line(Offset start, Offset end, Color color, double width) =>
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = color
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
    oval(const Rect.fromLTWH(10, 14, 140, 136), backdrop);
    oval(
      const Rect.fromLTWH(36, 138, 92, 8),
      Colors.black.withValues(alpha: 0.07),
    );
    if (scene == WellnessScene.nutrition) {
      line(const Offset(79, 44), const Offset(69, 23), green, 10);
      line(const Offset(80, 45), const Offset(91, 19), green, 11);
      line(const Offset(80, 45), const Offset(108, 32), green, 10);
      final carrot = Path()
        ..moveTo(54, 51)
        ..quadraticBezierTo(78, 39, 105, 51)
        ..quadraticBezierTo(110, 70, 91, 112)
        ..quadraticBezierTo(82, 139, 76, 136)
        ..quadraticBezierTo(52, 91, 54, 51);
      canvas.drawPath(carrot, Paint()..color = orange);
      line(const Offset(57, 82), const Offset(38, 76), orange, 8);
      line(const Offset(101, 80), const Offset(117, 67), orange, 8);
      line(const Offset(115, 68), const Offset(125, 70), orange, 8);
      line(
        const Offset(65, 65),
        const Offset(73, 67),
        const Color(0xFFE67522),
        3,
      );
      line(
        const Offset(86, 112),
        const Offset(94, 108),
        const Color(0xFFE67522),
        3,
      );
      oval(const Rect.fromLTWH(68, 77, 5, 7), ink);
      oval(const Rect.fromLTWH(89, 77, 5, 7), ink);
      canvas.drawArc(
        const Rect.fromLTWH(73, 86, 17, 12),
        0.1,
        math.pi - 0.2,
        false,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    } else if (scene == WellnessScene.movement) {
      const skin = Color(0xFFC99770);
      line(const Offset(75, 102), const Offset(64, 136), ink, 13);
      line(const Offset(92, 102), const Offset(108, 131), ink, 13);
      line(const Offset(64, 138), const Offset(49, 138), colors.secondary, 9);
      line(const Offset(108, 134), const Offset(119, 134), colors.secondary, 9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(58, 63, 49, 48),
          const Radius.circular(19),
        ),
        Paint()..color = colors.primary,
      );
      line(const Offset(62, 73), const Offset(43, 59), skin, 10);
      line(const Offset(43, 59), const Offset(47, 43), skin, 10);
      line(const Offset(103, 73), const Offset(120, 56), skin, 10);
      line(const Offset(120, 56), const Offset(116, 41), skin, 10);
      line(const Offset(73, 61), const Offset(73, 51), skin, 13);
      oval(const Rect.fromLTWH(61, 26, 30, 33), skin);
      canvas.drawArc(
        const Rect.fromLTWH(60, 23, 31, 25),
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = ink
          ..strokeWidth = 10
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      oval(const Rect.fromLTWH(69, 40, 3, 4), ink);
      oval(const Rect.fromLTWH(80, 40, 3, 4), ink);
      line(const Offset(73, 50), const Offset(78, 50), ink, 2);
      for (final x in [47.0, 117.0]) {
        line(Offset(x - 12, 36), Offset(x + 12, 36), ink, 5);
        line(Offset(x - 12, 29), Offset(x - 12, 43), colors.secondary, 8);
        line(Offset(x + 12, 29), Offset(x + 12, 43), colors.secondary, 8);
      }
    } else {
      final heart = Path()
        ..moveTo(80, 116)
        ..cubicTo(25, 81, 35, 41, 63, 47)
        ..quadraticBezierTo(74, 48, 80, 62)
        ..quadraticBezierTo(90, 42, 107, 48)
        ..cubicTo(141, 62, 110, 103, 80, 116);
      canvas.drawPath(heart, Paint()..color = orange);
      oval(const Rect.fromLTWH(64, 72, 5, 7), ink);
      oval(const Rect.fromLTWH(92, 72, 5, 7), ink);
      canvas.drawArc(
        const Rect.fromLTWH(72, 83, 17, 11),
        0,
        math.pi,
        false,
        Paint()
          ..color = ink
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
      line(const Offset(49, 96), const Offset(64, 110), green, 10);
      line(const Offset(112, 96), const Offset(97, 110), green, 10);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WellnessPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.colors != colors;
}
