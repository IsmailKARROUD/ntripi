// shared/widgets/itinerary_cover_placeholder.dart — Branded default cover.
//
// A stylized grey "trip map" shown whenever an itinerary has no cover image
// or the cover fails to load. Used by ItinerarySummaryCard (list, feed,
// profile grid) and the detail-screen hero.

import 'package:flutter/material.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

const _kInk = Color(0xFF4B554F); // darkest map grey — pill text + middle pin
const _kPinEnds = Color(0xFF6E7B74);
const _kRoute = Color(0xFF5E6B64);

class ItineraryCoverPlaceholder extends StatelessWidget {
  /// Where the "No cover image" pill sits. Default: centered-lower.
  final AlignmentGeometry labelAlignment;

  const ItineraryCoverPlaceholder({
    super.key,
    this.labelAlignment = const Alignment(0, 0.45),
  });

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary + static const painters → raster-cached in scroll lists.
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(
            painter: _TripMapPainter(),
            isComplex: true,
            willChange: false,
          ),
          // top-end (not top-start) — the cards put a VisibilityBadge at
          // top-start; directional positioning keeps them apart in RTL too.
          const PositionedDirectional(
            top: 8,
            end: 8,
            child: Opacity(
              opacity: 0.5,
              child: CustomPaint(
                size: Size(22, 22),
                painter: _NtripiMarkPainter(),
              ),
            ),
          ),
          Align(
            alignment: labelAlignment,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xD1FFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_not_supported_outlined,
                      size: 14, color: _kInk),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.noCoverImage,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The map artwork: land gradient, water blob, park block, white streets,
// dotted route with three pins. Deliberately never mirrored for RTL — maps
// don't flip.
class _TripMapPainter extends CustomPainter {
  const _TripMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Strokes scale off the shortest side so the art reads the same at the
    // 120px card and the 240px hero.
    final k = (size.shortestSide / 160).clamp(0.9, 1.5).toDouble();

    // Streets/blobs run past the frame edges — CustomPaint doesn't clip.
    canvas.clipRect(Offset.zero & size);

    // Land
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAEBEC), Color(0xFFD9DBDE)],
        ).createShader(Offset.zero & size),
    );

    // Water blob, lower-left
    final water = Path()
      ..moveTo(-0.05 * w, 0.62 * h)
      ..cubicTo(0.10 * w, 0.55 * h, 0.30 * w, 0.62 * h, 0.36 * w, 0.74 * h)
      ..cubicTo(0.42 * w, 0.86 * h, 0.34 * w, 1.02 * h, 0.22 * w, 1.08 * h)
      ..lineTo(-0.05 * w, 1.08 * h)
      ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xE6C7D0D4));

    // Park block, upper-right
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.62 * w, 0.08 * h, 0.30 * w, 0.30 * h),
        Radius.circular(10 * k),
      ),
      Paint()..color = const Color(0xD9CDD6CD),
    );

    // Thin street grid
    final grid = Paint()
      ..color = const Color(0xB3FFFFFF)
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0.22 * w, -0.05 * h), Offset(0.16 * w, 1.05 * h), grid);
    canvas.drawLine(Offset(0.55 * w, -0.05 * h), Offset(0.60 * w, 1.05 * h), grid);
    canvas.drawLine(Offset(0.80 * w, -0.05 * h), Offset(0.76 * w, 1.05 * h), grid);
    canvas.drawLine(Offset(-0.05 * w, 0.30 * h), Offset(1.05 * w, 0.24 * h), grid);
    canvas.drawLine(Offset(-0.05 * w, 0.72 * h), Offset(1.05 * w, 0.78 * h), grid);

    // Three wide streets
    final street = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.5 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(-0.05 * w, 0.52 * h), Offset(1.05 * w, 0.44 * h), street);
    canvas.drawLine(Offset(0.38 * w, -0.05 * h), Offset(0.44 * w, 1.05 * h), street);
    canvas.drawLine(Offset(-0.05 * w, 0.95 * h), Offset(1.05 * w, 0.10 * h), street);

    // Route: winding dotted path sweeping lower-left → upper-right.
    final route = Path()
      ..moveTo(0.10 * w, 0.85 * h)
      ..cubicTo(0.28 * w, 0.95 * h, 0.40 * w, 0.55 * h, 0.52 * w, 0.52 * h)
      ..cubicTo(0.66 * w, 0.48 * h, 0.62 * w, 0.20 * h, 0.88 * w, 0.18 * h);
    final routePaint = Paint()
      ..color = _kRoute
      ..strokeWidth = 4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // 0.5-length dashes + round caps render as dots (dash 0.5 / gap 11).
    _drawDashed(canvas, route, routePaint, 0.5 * k, 11 * k);

    // Three pins anchored on the route — middle one darker.
    final metric = route.computeMetrics().first;
    const stopsAlongRoute = [
      (0.10, _kPinEnds),
      (0.50, _kInk),
      (0.90, _kPinEnds),
    ];
    for (final (t, color) in stopsAlongRoute) {
      final tip = metric.getTangentForOffset(metric.length * t)!.position;
      _drawPin(canvas, tip, 7 * k, color);
    }
  }

  void _drawDashed(
      Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      double d = 0;
      bool drawing = true;
      while (d < m.length) {
        final len = drawing ? dash : gap;
        if (drawing) {
          canvas.drawPath(
              m.extractPath(d, (d + len).clamp(0, m.length)), paint);
        }
        d += len;
        drawing = !drawing;
      }
    }
  }

  // Teardrop pin with its tail tip at [tip]; [r] is the head radius.
  void _drawPin(Canvas canvas, Offset tip, double r, Color color) {
    final head = tip - Offset(0, r * 2.2);
    final fill = Paint()..color = color;
    canvas.drawCircle(head, r, fill);
    canvas.drawPath(
      Path()
        ..moveTo(head.dx - r * 0.55, head.dy + r * 0.65)
        ..lineTo(head.dx + r * 0.55, head.dy + r * 0.65)
        ..lineTo(tip.dx, tip.dy)
        ..close(),
      fill,
    );
    canvas.drawCircle(head, r * 0.38, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TripMapPainter oldDelegate) => false;
}

// Small NTripi mark: grey rounded square + white route polyline with end
// dots, in a 24-unit viewbox (matches the brand mark geometry).
class _NtripiMarkPainter extends CustomPainter {
  const _NtripiMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(6 * s),
      ),
      Paint()..color = const Color(0xFF8C9891),
    );

    canvas.drawPath(
      Path()
        ..moveTo(6 * s, 18 * s)
        ..lineTo(6 * s, 8 * s)
        ..lineTo(12 * s, 15 * s)
        ..lineTo(18 * s, 8 * s),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2.2 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(6 * s, 18 * s), 2 * s, dot);
    canvas.drawCircle(Offset(18 * s, 8 * s), 2 * s, dot);
  }

  @override
  bool shouldRepaint(_NtripiMarkPainter oldDelegate) => false;
}
