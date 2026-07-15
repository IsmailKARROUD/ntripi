import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

/// The NTripi logo mark + optional "Tripi" wordmark.
///
/// The mark is a [size]×[size] rounded square in forest green with a white N
/// route path and an amber destination dot at the top-right endpoint.
///
/// [onDark] swaps the background to the lighter canopy green (used on dark
/// backgrounds such as the splash screen).
///
/// [showWordmark] adds the "Tripi" text to the right of the mark.
class NtripiLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final bool onDark;

  const NtripiLogo({
    super.key,
    this.size = 32,
    this.showWordmark = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _LogoMarkPainter(onDark: onDark),
        ),
        if (showWordmark) ...[
          SizedBox(width: size * 0.19),
          Text(
            'Tripi',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: size * 0.75,
              fontWeight: FontWeight.w800,
              // nt.forest flips to a light green in dark mode, keeping the
              // wordmark readable on dark surfaces.
              color: onDark ? NtripiBrand.mint : context.nt.forest,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  final bool onDark;

  const _LogoMarkPainter({this.onDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0;

    // Rounded square background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(8 * s),
      ),
      // Brand constants — the logo mark never flips with the theme.
      Paint()..color = onDark ? NtripiBrand.canopy : NtripiBrand.forest,
    );

    // N route path: bottom-left → top-left → mid-bottom → top-right
    final path = Path()
      ..moveTo(8 * s, 24 * s)
      ..lineTo(8 * s, 10 * s)
      ..lineTo(16 * s, 20 * s)
      ..lineTo(24 * s, 10 * s);

    canvas.drawPath(
      path,
      Paint()
        ..color = NtripiBrand.chrome
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Amber destination dot (outer)
    canvas.drawCircle(
      Offset(24 * s, 10 * s),
      3 * s,
      Paint()..color = NtripiBrand.amber,
    );

    // White inner dot
    canvas.drawCircle(
      Offset(24 * s, 10 * s),
      1.5 * s,
      Paint()..color = NtripiBrand.chrome,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter old) => old.onDark != onDark;
}
