import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

// ── 1. NTripiPeakLoader — mountain path traces itself ──────────────────────

class NTripiPeakLoader extends StatefulWidget {
  final double size;
  const NTripiPeakLoader({super.key, this.size = 80});

  @override
  State<NTripiPeakLoader> createState() => _NTripiPeakLoaderState();
}

class _NTripiPeakLoaderState extends State<NTripiPeakLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _PeakPainter(_ctrl.value, context.nt),
        ),
      );
}

class _PeakPainter extends CustomPainter {
  final double t;
  final NtripiColors nt;
  _PeakPainter(this.t, this.nt);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 96.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(22 * s)),
      Paint()..color = nt.forest,
    );

    // Mountain path: bottom-left → top-left → mid-dip → top-right
    final path = Path()
      ..moveTo(22 * s, 72 * s)
      ..lineTo(22 * s, 30 * s)
      ..lineTo(48 * s, 60 * s)
      ..lineTo(74 * s, 30 * s);

    // 0→0.55 draw in, 0.55→0.85 hold, 0.85→1 erase
    double drawP;
    if (t < 0.55) {
      drawP = t / 0.55;
    } else if (t < 0.85) {
      drawP = 1.0;
    } else {
      drawP = 1.0 - (t - 0.85) / 0.15;
    }
    drawP = drawP.clamp(0.0, 1.0);

    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * drawP),
      Paint()
        // surface, not white — keeps the path visible on dark's light-green tile
        ..color = nt.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Amber sun pops at the peak (0.50→0.65 fade-in, holds, fades with path)
    double sunOpacity;
    double sunScale;
    if (t < 0.50) {
      sunOpacity = 0;
      sunScale = 0.4;
    } else if (t < 0.65) {
      final p = (t - 0.50) / 0.15;
      sunOpacity = p;
      sunScale = 0.4 + p * 0.75;
    } else if (t < 0.85) {
      sunOpacity = 1;
      sunScale = 1.0;
    } else {
      sunOpacity = 1.0 - (t - 0.85) / 0.15;
      sunScale = 1.0;
    }
    sunOpacity = sunOpacity.clamp(0, 1);

    if (sunOpacity > 0) {
      canvas.save();
      canvas.translate(74 * s, 30 * s);
      canvas.scale(sunScale);
      canvas.drawCircle(
          Offset.zero, 8 * s, Paint()..color = nt.amber.withValues(alpha: sunOpacity));
      canvas.drawCircle(
          Offset.zero, 3.5 * s, Paint()..color = nt.surface.withValues(alpha: sunOpacity));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PeakPainter old) => old.t != t;
}

// ── 2. NTripiRouteLoader — dot travels a dashed curved path ────────────────

class NTripiRouteLoader extends StatefulWidget {
  const NTripiRouteLoader({super.key});

  @override
  State<NTripiRouteLoader> createState() => _NTripiRouteLoaderState();
}

class _NTripiRouteLoaderState extends State<NTripiRouteLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: const Size(160, 120),
          painter: _RoutePathPainter(_ctrl.value, context.nt),
        ),
      );
}

class _RoutePathPainter extends CustomPainter {
  final double t;
  final NtripiColors nt;
  _RoutePathPainter(this.t, this.nt);

  Path _buildPath(Size size) {
    final s = size.width / 160.0;
    final h = size.height / 120.0;
    // SVG: M 16 96 Q 50 96 60 64 T 100 40 Q 120 24 144 24
    // T smooth-quadratic reflects prev control: 2*(60,64)-(50,96) = (70,32)
    return Path()
      ..moveTo(16 * s, 96 * h)
      ..quadraticBezierTo(50 * s, 96 * h, 60 * s, 64 * h)
      ..quadraticBezierTo(70 * s, 32 * h, 100 * s, 40 * h)
      ..quadraticBezierTo(120 * s, 24 * h, 144 * s, 24 * h);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);
    final s = size.width / 160.0;
    final h = size.height / 120.0;

    _drawDashed(
      canvas, path,
      Paint()
        ..color = nt.mist
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * s
        ..strokeCap = StrokeCap.round,
      2 * s, 8 * s,
    );

    // Start pin (forest)
    canvas.drawCircle(Offset(16 * s, 96 * h), 6 * s, Paint()..color = nt.forest);
    canvas.drawCircle(Offset(16 * s, 96 * h), 2 * s, Paint()..color = nt.surface);

    // End pin (amber)
    canvas.drawCircle(Offset(144 * s, 24 * h), 7 * s, Paint()..color = nt.amber);
    canvas.drawCircle(Offset(144 * s, 24 * h), 2.5 * s, Paint()..color = nt.surface);

    // Traveler dot: 8% fade-in → travel → 92% fade-out
    double dotProgress;
    double dotOpacity;
    if (t < 0.08) {
      dotProgress = 0;
      dotOpacity = t / 0.08;
    } else if (t < 0.92) {
      dotProgress = (t - 0.08) / 0.84;
      dotOpacity = 1.0;
    } else {
      dotProgress = 1.0;
      dotOpacity = 1.0 - (t - 0.92) / 0.08;
    }

    final metric = path.computeMetrics().first;
    final tangent =
        metric.getTangentForOffset(metric.length * dotProgress.clamp(0, 1));
    if (tangent != null && dotOpacity > 0) {
      canvas.drawCircle(
        tangent.position,
        6 * s,
        Paint()..color = nt.forest.withValues(alpha: dotOpacity.clamp(0, 1)),
      );
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

  @override
  bool shouldRepaint(_RoutePathPainter old) => old.t != t;
}

// ── 3. NTripiPinLoader — pin bounce with sonar rings ───────────────────────

class NTripiPinLoader extends StatefulWidget {
  const NTripiPinLoader({super.key});

  @override
  State<NTripiPinLoader> createState() => _NTripiPinLoaderState();
}

class _NTripiPinLoaderState extends State<NTripiPinLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: const Size(80, 110),
          painter: _PinPainter(_ctrl.value, context.nt),
        ),
      );
}

class _PinPainter extends CustomPainter {
  final double t;
  final NtripiColors nt;
  _PinPainter(this.t, this.nt);

  static const double _cx = 40;
  static const double _headR = 13.0;
  static const double _tailH = 18.0; // tail length below head edge
  static const double _tailW = 7.0; // tail half-width at head

  @override
  void paint(Canvas canvas, Size size) {
    // Bounce: drops smoothly over the cycle, 0px at 50%, −8px at 0%/100%
    final bounce = -8.0 * (1 - math.sin(math.pi * t));
    final headY = 20.0 + bounce;

    // Shadow — widens and darkens when pin is at lowest point
    final shadowW = 22.0 + 10.0 * math.sin(math.pi * t);
    final shadowA = 0.15 + 0.20 * math.sin(math.pi * t);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(_cx, 104), width: shadowW, height: 7),
      Paint()
        ..color = nt.shadow.withValues(alpha: shadowA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Two sonar rings staggered by half a cycle
    for (int i = 0; i < 2; i++) {
      final ringT = (t + i * 0.5) % 1.0;
      if (ringT < 0.8) {
        final progress = ringT / 0.8;
        final ringR = 12.0 * (0.4 + progress * 2.2); // scale 0.4→2.6
        final ringA = 0.7 * (1 - progress);
        canvas.drawCircle(
          const Offset(_cx, 98),
          ringR,
          Paint()
            ..color = nt.amber.withValues(alpha: ringA)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // Pin head
    canvas.drawCircle(Offset(_cx, headY), _headR, Paint()..color = nt.forest);

    // Pin tail (triangle below head)
    canvas.drawPath(
      Path()
        ..moveTo(_cx - _tailW, headY + _headR - 4)
        ..lineTo(_cx + _tailW, headY + _headR - 4)
        ..lineTo(_cx, headY + _headR + _tailH)
        ..close(),
      Paint()..color = nt.forest,
    );

    // Amber inner dot
    canvas.drawCircle(Offset(_cx, headY), 5.0, Paint()..color = nt.amber);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.t != t;
}

// ── 4. NTripiCompassLoader — needle spins with deliberate overshoot ─────────

class NTripiCompassLoader extends StatefulWidget {
  final double size;
  const NTripiCompassLoader({super.key, this.size = 100});

  @override
  State<NTripiCompassLoader> createState() => _NTripiCompassLoaderState();
}

class _NTripiCompassLoaderState extends State<NTripiCompassLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    // Matches CSS keyframes: 0%→0°, 30%→280°, 50%→250°, 80%→370°, 100%→360°
    _angle = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 280.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 280.0, end: 250.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 250.0, end: 370.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 370.0, end: 360.0), weight: 20),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _angle,
        builder: (_, __) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CompassPainter(_angle.value, context.nt),
        ),
      );
}

class _CompassPainter extends CustomPainter {
  final double angleDeg;
  final NtripiColors nt;
  _CompassPainter(this.angleDeg, this.nt);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 120.0;
    final r = 52 * s;

    // Mist outer ring
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = nt.mist
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s,
    );

    // 8 tick marks (major every 90°, minor every 45°)
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final isMajor = i % 2 == 0;
      canvas.drawLine(
        Offset(cx + (r - 2) * math.cos(a), cy + (r - 2) * math.sin(a)),
        Offset(cx + (r - (isMajor ? 8 : 5) * s) * math.cos(a),
            cy + (r - (isMajor ? 8 : 5) * s) * math.sin(a)),
        Paint()
          ..color = nt.forest.withValues(alpha: isMajor ? 1.0 : 0.35)
          ..strokeWidth = 2 * s
          ..strokeCap = StrokeCap.round,
      );
    }

    // "N" label at top
    final tp = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TextStyle(
            fontSize: 9 * s,
            fontWeight: FontWeight.w700,
            color: nt.forest,
            height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, 7 * s));

    // Rotating needle
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angleDeg * math.pi / 180);

    // Full diamond (forest): north tip (0,−38), east (5,0), south (0,38), west (−5,0)
    canvas.drawPath(
      Path()
        ..moveTo(0, -38 * s)
        ..lineTo(5 * s, 0)
        ..lineTo(0, 38 * s)
        ..lineTo(-5 * s, 0)
        ..close(),
      Paint()..color = nt.forest,
    );
    // Amber overlay on north-right quarter
    canvas.drawPath(
      Path()
        ..moveTo(0, -38 * s)
        ..lineTo(5 * s, 0)
        ..lineTo(0, 0)
        ..close(),
      Paint()..color = nt.amber,
    );

    canvas.restore();

    // Pivot
    canvas.drawCircle(Offset(cx, cy), 5 * s, Paint()..color = nt.bark);
    canvas.drawCircle(Offset(cx, cy), 2 * s, Paint()..color = nt.surface);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.angleDeg != angleDeg;
}

// ── 5. NTripiTicketLoader — boarding-pass shimmer ──────────────────────────

class NTripiTicketLoader extends StatefulWidget {
  const NTripiTicketLoader({super.key});

  @override
  State<NTripiTicketLoader> createState() => _NTripiTicketLoaderState();
}

class _NTripiTicketLoaderState extends State<NTripiTicketLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Sweep left→right over first 60% of cycle, then hold off-screen right
        final shimmerX =
            _ctrl.value < 0.60 ? -1.0 + (_ctrl.value / 0.60) * 2.0 : 1.0;

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: nt.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: nt.shadow.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('MRK',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: nt.bark,
                                letterSpacing: -0.5)),
                        Text('Marrakech',
                            style: TextStyle(
                                fontSize: 10,
                                color: nt.forest,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Expanded(child: Container(height: 1.5, color: nt.mist)),
                            const SizedBox(width: 4),
                            Icon(Icons.airplanemode_active,
                                color: nt.forest, size: 18),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('SAF',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: nt.bark,
                                letterSpacing: -0.5)),
                        Text('Safi',
                            style: TextStyle(
                                fontSize: 10,
                                color: nt.forest,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                // Shimmer overlay translates from −200 to +200 px
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(shimmerX * 200, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            nt.shimmerHighlight.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                          stops: const [0.3, 0.5, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 6. NTripiItineraryLoader — stop cards build up staggered ───────────────

class NTripiItineraryLoader extends StatefulWidget {
  const NTripiItineraryLoader({super.key});

  @override
  State<NTripiItineraryLoader> createState() => _NTripiItineraryLoaderState();
}

class _NTripiItineraryLoaderState extends State<NTripiItineraryLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final colors = [nt.forest, nt.canopy, nt.amber];
    const barWidths = [88.0, 64.0, 76.0];
    // Stagger: 0 ms, 250 ms, 500 ms out of 1600 ms total
    const delays = [0.0, 250 / 1600, 500 / 1600];

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          // Shift each card's phase so they enter sequentially
          var lT = (_ctrl.value - delays[i]) % 1.0;
          if (lT < 0) lT += 1.0;

          // Matches CSS: 0,5%→hidden | 5,20%→slide+fade in | 20,75%→hold | 75,95%→slide+fade out
          double opacity;
          double dx;
          if (lT < 0.05) {
            opacity = 0;
            dx = -12;
          } else if (lT < 0.20) {
            final p = (lT - 0.05) / 0.15;
            opacity = p;
            dx = -12 + 12 * p;
          } else if (lT < 0.75) {
            opacity = 1;
            dx = 0;
          } else if (lT < 0.95) {
            final p = (lT - 0.75) / 0.20;
            opacity = 1 - p;
            dx = 12 * p;
          } else {
            opacity = 0;
            dx = 12;
          }

          return Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: nt.surface,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: nt.shadow.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: colors[i], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: barWidths[i],
                      height: 5,
                      decoration: BoxDecoration(
                          color: nt.mist,
                          borderRadius: BorderRadius.circular(3)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── 7. NTripiRingLoader — route ring (recommended default spinner) ──────────

class NTripiRingLoader extends StatefulWidget {
  final double size;
  const NTripiRingLoader({super.key, this.size = 80});

  @override
  State<NTripiRingLoader> createState() => _NTripiRingLoaderState();
}

class _NTripiRingLoaderState extends State<NTripiRingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        builder: (_, __) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _RingPainter(_t.value, context.nt),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double t;
  final NtripiColors nt;
  _RingPainter(this.t, this.nt);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 34 / 96;
    final strokeW = size.width * 6 / 96;

    // Mist track ring
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = nt.mist
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Forest arc — 80/214 of the circle ≈ 134°
    const sweepAngle = 80 / 214 * 2 * math.pi;
    final startAngle = t * 2 * math.pi - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = nt.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    // Amber bead at the leading edge of the arc
    final beadX = cx + r * math.cos(startAngle);
    final beadY = cy + r * math.sin(startAngle);
    canvas.drawCircle(
        Offset(beadX, beadY), strokeW * 0.9, Paint()..color = nt.amber);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

// ── 8. NTripiDotsLoader — three dots bounce like mountain peaks ─────────────

class NTripiDotsLoader extends StatefulWidget {
  final double dotSize;
  const NTripiDotsLoader({super.key, this.dotSize = 14});

  @override
  State<NTripiDotsLoader> createState() => _NTripiDotsLoaderState();
}

class _NTripiDotsLoaderState extends State<NTripiDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final s = widget.dotSize;
        final spacing = s * 10 / 14;
        final bounce = s * 26 / 14;
        return SizedBox(
          height: s + bounce + 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _PeakDot(color: nt.forest, t: _ctrl.value, delay: 0.0, size: s, bounce: bounce),
              SizedBox(width: spacing),
              _PeakDot(color: nt.canopy, t: _ctrl.value, delay: 0.15 / 1.1, size: s, bounce: bounce),
              SizedBox(width: spacing),
              _PeakDot(color: nt.amber, t: _ctrl.value, delay: 0.30 / 1.1, size: s, bounce: bounce),
            ],
          ),
        );
      },
    );
  }
}

class _PeakDot extends StatelessWidget {
  final Color color;
  final double t;
  final double delay;
  final double size;
  final double bounce;
  const _PeakDot({required this.color, required this.t, required this.delay, required this.size, required this.bounce});

  @override
  Widget build(BuildContext context) {
    var lT = (t - delay) % 1.0;
    if (lT < 0) lT += 1.0;

    // 0→40% rise, 40→60% hold at peak, 60→100% fall
    double yOffset;
    if (lT < 0.40) {
      yOffset = -bounce * Curves.easeInOut.transform(lT / 0.40);
    } else if (lT < 0.60) {
      yOffset = -bounce;
    } else {
      yOffset = -bounce * (1 - Curves.easeInOut.transform((lT - 0.60) / 0.40));
    }

    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── 9. NTripiSkeleton — content-placeholder shimmer ────────────────────────

class NTripiSkeleton extends StatefulWidget {
  const NTripiSkeleton({super.key});

  @override
  State<NTripiSkeleton> createState() => _NTripiSkeletonState();
}

class _NTripiSkeletonState extends State<NTripiSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Shimmer band sweeps right→left: begin/end Alignment x from −1.5→0.5
        final shimX = -1.5 + 2.0 * _ctrl.value;

        Widget bar(double w, double h, {bool circle = false}) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle ? null : BorderRadius.circular(5),
                gradient: LinearGradient(
                  begin: Alignment(shimX, 0),
                  end: Alignment(shimX + 1, 0),
                  colors: [nt.mist, nt.shimmerHighlight, nt.mist],
                ),
              ),
            );

        return SizedBox(
          width: 170,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  bar(36, 36, circle: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(124, 9),  // ~70% of 124 px available
                        const SizedBox(height: 5),
                        bar(56, 6),   // ~45%
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              bar(170, 9),
              const SizedBox(height: 10),
              bar(145, 9),  // ~85%
              const SizedBox(height: 10),
              bar(102, 9),  // ~60%
            ],
          ),
        );
      },
    );
  }
}

// ── 10. OwnerRowSkeleton — shimmer placeholder matching _OwnerRow height ────

class OwnerRowSkeleton extends StatefulWidget {
  const OwnerRowSkeleton({super.key});

  @override
  State<OwnerRowSkeleton> createState() => _OwnerRowSkeletonState();
}

class _OwnerRowSkeletonState extends State<OwnerRowSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final shimX = -1.5 + 2.0 * _ctrl.value;

        Widget bar(double w, double h, {bool circle = false}) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle ? null : BorderRadius.circular(5),
                gradient: LinearGradient(
                  begin: Alignment(shimX, 0),
                  end: Alignment(shimX + 1, 0),
                  colors: [nt.mist, nt.shimmerHighlight, nt.mist],
                ),
              ),
            );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              bar(36, 36, circle: true),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(110, 9),
                  const SizedBox(height: 5),
                  bar(70, 7),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
