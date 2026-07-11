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

// The map artwork, styled after a real city map with an itinerary drawn on
// it: a river, parks, faint building blocks, a street network, and a dotted
// route that follows the streets through three numbered stop pins.
// Deliberately never mirrored for RTL — maps don't flip.
class _TripMapPainter extends CustomPainter {
  const _TripMapPainter();

  // Route vertices (fractions of w/h). Each segment lies on a street drawn
  // below, so the route visibly follows roads like a real navigation trace.
  static const _route = [
    Offset(0.13, 0.80), // stop 1
    Offset(0.32, 0.78),
    Offset(0.34, 0.57),
    Offset(0.55, 0.54), // stop 2
    Offset(0.57, 0.33),
    Offset(0.74, 0.31),
    Offset(0.88, 0.20), // stop 3
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Strokes scale off the shortest side so the art reads the same at the
    // 120px card and the 240px hero.
    final k = (size.shortestSide / 160).clamp(0.9, 1.5).toDouble();

    // Streets/river run past the frame edges — CustomPaint doesn't clip.
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

    // River winding down the left edge (streets drawn later read as bridges).
    final waterPaint = Paint()..color = const Color(0xE6C7D0D4);
    final river = Path()
      ..moveTo(0.14 * w, -0.05 * h)
      ..cubicTo(0.10 * w, 0.10 * h, 0.01 * w, 0.16 * h, 0.03 * w, 0.28 * h)
      ..cubicTo(0.05 * w, 0.38 * h, -0.02 * w, 0.44 * h, -0.06 * w, 0.50 * h);
    canvas.drawPath(
      river,
      Paint()
        ..color = waterPaint.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15 * k
        ..strokeCap = StrokeCap.round,
    );

    // Parks: large one upper-right (with a pond), small one lower-right.
    final parkPaint = Paint()..color = const Color(0xD9CDD6CD);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.62 * w, 0.06 * h, 0.28 * w, 0.24 * h),
        Radius.circular(10 * k),
      ),
      parkPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(0.76 * w, 0.18 * h), width: 0.09 * w, height: 0.10 * h),
      waterPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.80 * w, 0.60 * h, 0.16 * w, 0.24 * h),
        Radius.circular(8 * k),
      ),
      parkPaint,
    );

    // Building blocks — faint darker rects clustered inside street blocks.
    final buildingPaint = Paint()..color = const Color(0x2E6E7B74);
    const buildings = [
      Offset(0.40, 0.42), Offset(0.455, 0.465), Offset(0.405, 0.50),
      Offset(0.63, 0.415), Offset(0.685, 0.45),
      Offset(0.46, 0.66), Offset(0.515, 0.695),
      Offset(0.20, 0.60), Offset(0.255, 0.635),
      Offset(0.56, 0.875), Offset(0.615, 0.845),
      Offset(0.155, 0.17), Offset(0.21, 0.21),
    ];
    for (var i = 0; i < buildings.length; i++) {
      final c = buildings[i];
      // Alternate two footprints for a hand-placed feel.
      final bw = (i.isEven ? 11.0 : 8.5) * k;
      final bh = (i.isEven ? 7.5 : 9.5) * k;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(c.dx * w, c.dy * h), width: bw, height: bh),
          Radius.circular(1.5 * k),
        ),
        buildingPaint,
      );
    }

    // Street network. The first three thin streets and the three avenues run
    // exactly through the route segments above (extended to the frame edges).
    final thin = Paint()
      ..color = const Color(0xB3FFFFFF)
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Carries route p0→p1
    canvas.drawLine(Offset(-0.05 * w, 0.819 * h), Offset(1.05 * w, 0.703 * h), thin);
    // Carries route p3→p4
    canvas.drawLine(Offset(0.501 * w, 1.05 * h), Offset(0.606 * w, -0.05 * h), thin);
    // Carries route p4→p5
    canvas.drawLine(Offset(-0.05 * w, 0.403 * h), Offset(1.05 * w, 0.274 * h), thin);
    // Filler grid
    canvas.drawLine(Offset(0.10 * w, -0.05 * h), Offset(0.16 * w, 1.05 * h), thin);
    canvas.drawLine(Offset(0.72 * w, -0.05 * h), Offset(0.78 * w, 1.05 * h), thin);
    canvas.drawLine(Offset(0.88 * w, -0.05 * h), Offset(0.93 * w, 1.05 * h), thin);
    canvas.drawLine(Offset(-0.05 * w, 0.135 * h), Offset(1.05 * w, 0.09 * h), thin);
    canvas.drawLine(Offset(-0.05 * w, 0.95 * h), Offset(1.05 * w, 0.90 * h), thin);

    final avenue = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.5 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Carries route p1→p2
    canvas.drawLine(Offset(0.294 * w, 1.05 * h), Offset(0.399 * w, -0.05 * h), avenue);
    // Carries route p2→p3
    canvas.drawLine(Offset(-0.05 * w, 0.626 * h), Offset(1.05 * w, 0.469 * h), avenue);
    // Diagonal avenue carrying route p5→p6
    canvas.drawLine(Offset(-0.05 * w, 0.93 * h), Offset(1.05 * w, 0.066 * h), avenue);

    // Route: dotted navigation trace following the streets stop → stop.
    final route = Path()..moveTo(_route.first.dx * w, _route.first.dy * h);
    for (final p in _route.skip(1)) {
      route.lineTo(p.dx * w, p.dy * h);
    }
    final routePaint = Paint()
      ..color = _kRoute
      ..strokeWidth = 4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // 0.5-length dashes + round caps render as dots (dash 0.5 / gap 11).
    _drawDashed(canvas, route, routePaint, 0.5 * k, 11 * k);

    // Numbered stop pins at start / middle / end — middle one darker.
    const stops = [(0, _kPinEnds, '1'), (3, _kInk, '2'), (6, _kPinEnds, '3')];
    for (final (i, color, label) in stops) {
      final v = _route[i];
      _drawPin(canvas, Offset(v.dx * w, v.dy * h), 7.5 * k, color, label);
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

  // Teardrop pin with its tail tip at [tip]; [r] is the head radius. The head
  // carries the stop number — Western digits match the app's ar/fr/en copy.
  void _drawPin(Canvas canvas, Offset tip, double r, Color color, String label) {
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
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 1.3,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(head.dx - tp.width / 2, head.dy - tp.height / 2));
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
