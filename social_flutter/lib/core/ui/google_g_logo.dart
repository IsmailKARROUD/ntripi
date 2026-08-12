// The official Google "G" mark, drawn as vector paths.
//
// Google's branding terms require the logo unmodified — same four colors, same
// geometry — so this is a faithful transcription of the 48×48 mark from their
// sign-in branding kit rather than an approximation.
//
// Drawn rather than shipped as an asset for two reasons: the project has no
// image-asset pipeline (only json/tflite/wav) and no SVG package, and a painter
// stays crisp at any size and pixel ratio without three density variants.
import 'package:flutter/material.dart';

import 'package:social_flutter/core/ui/app_theme.dart';

class GoogleGLogo extends StatelessWidget {
  /// Side length in logical pixels. The mark is square.
  final double size;

  const GoogleGLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GoogleGPainter()),
      );
}

class _GoogleGPainter extends CustomPainter {
  /// The mark's design grid — every coordinate below is in this box, so the
  /// canvas is scaled once instead of every point being divided by 48.
  static const _viewBox = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);

    final paint = Paint()..isAntiAlias = true;

    // Red — the top of the ring.
    canvas.drawPath(
      Path()
        ..moveTo(24, 9.5)
        ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
        ..relativeLineTo(6.85, -6.85)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..relativeLineTo(7.98, 6.19)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close(),
      paint..color = NtripiBrand.googleMarkRed,
    );

    // Blue — the right of the ring plus the crossbar.
    canvas.drawPath(
      Path()
        ..moveTo(46.98, 24.55)
        ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
        ..lineTo(24, 20)
        ..relativeLineTo(0, 9.02)
        ..relativeLineTo(12.94, 0)
        ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
        ..relativeLineTo(7.73, 6)
        ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
        ..close(),
      paint..color = NtripiBrand.googleMarkBlue,
    );

    // Yellow — the left of the ring. The second curve is an SVG smooth-cubic;
    // its first control point is the reflection of the previous one about
    // (9.77, 24), which is why that point is spelled out here.
    canvas.drawPath(
      Path()
        ..moveTo(10.53, 28.59)
        ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
        ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
        ..relativeLineTo(-7.98, -6.19)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
        ..relativeLineTo(7.97, -6.19)
        ..close(),
      paint..color = NtripiBrand.googleMarkYellow,
    );

    // Green — the bottom of the ring.
    canvas.drawPath(
      Path()
        ..moveTo(24, 48)
        ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
        ..relativeLineTo(-7.73, -6)
        ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
        ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
        ..relativeLineTo(-7.98, 6.19)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close(),
      paint..color = NtripiBrand.googleMarkGreen,
    );

    canvas.restore();
  }

  // Nothing to compare — the mark is fixed and takes no parameters.
  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}
