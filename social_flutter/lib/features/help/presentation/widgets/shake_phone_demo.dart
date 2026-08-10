// features/help/presentation/widgets/shake_phone_demo.dart
//
// The animated demonstration on the Report-a-bug screen: a phone that tips
// left and right with motion arcs, pausing between shakes.
//
// Hand-rolled rather than a package — the app carries no animation dependency
// and no image assets, and every other custom animation here is an
// AnimationController + CustomPainter (see shared/widgets/loaders.dart).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

class ShakePhoneDemo extends StatefulWidget {
  final double size;

  /// Dimmed when the gesture is switched off — the demo still explains what
  /// the setting does, it just stops looking like an instruction to follow.
  final bool muted;

  const ShakePhoneDemo({super.key, this.size = 140, this.muted = false});

  @override
  State<ShakePhoneDemo> createState() => _ShakePhoneDemoState();
}

class _ShakePhoneDemoState extends State<ShakePhoneDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // Rest, five decaying swings, longer rest. The curve goes on each item —
    // a CurvedAnimation over the whole sequence would ease the rests too and
    // the pause would drift instead of holding still.
    final swing = CurveTween(curve: Curves.easeInOut);
    _angle = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 18),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 0.16).chain(swing), weight: 8),
      TweenSequenceItem(
          tween: Tween(begin: 0.16, end: -0.16).chain(swing), weight: 12),
      TweenSequenceItem(
          tween: Tween(begin: -0.16, end: 0.14).chain(swing), weight: 12),
      TweenSequenceItem(
          tween: Tween(begin: 0.14, end: -0.12).chain(swing), weight: 12),
      TweenSequenceItem(
          tween: Tween(begin: -0.12, end: 0.0).chain(swing), weight: 8),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
    ]).animate(_ctrl);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not readable in initState, so the reduce-motion decision
    // lands here. A `repeat()` controller also never lets pumpAndSettle finish,
    // which is what the widget test asserts on.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _ctrl.stop();
      _ctrl.value = 0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Reduce motion still gets a picture of a shake, just a still one: the
    // phone frozen mid-tip with both arcs drawn.
    if (reduceMotion) {
      return CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _ShakePhonePainter(0.16, nt, widget.muted, staticFrame: true),
      );
    }

    return AnimatedBuilder(
      animation: _angle,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _ShakePhonePainter(_angle.value, nt, widget.muted),
      ),
    );
  }
}

class _ShakePhonePainter extends CustomPainter {
  final double angle;
  final NtripiColors nt;
  final bool muted;
  final bool staticFrame;

  _ShakePhonePainter(this.angle, this.nt, this.muted,
      {this.staticFrame = false});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 140.0;
    final opacity = muted ? 0.35 : 1.0;

    // Arcs fade in with the swing so a resting phone sits on a clean canvas.
    // The demo is symmetric — both sides are drawn together — so it reads the
    // same under RTL and needs no Directionality handling.
    final arcStrength = staticFrame ? 1.0 : (angle.abs() / 0.16).clamp(0.0, 1.0);
    if (arcStrength > 0.01) {
      final arcPaint = Paint()
        ..color = nt.forest.withValues(alpha: 0.5 * arcStrength * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s
        ..strokeCap = StrokeCap.round;
      for (final dir in [-1.0, 1.0]) {
        for (var i = 0; i < 2; i++) {
          final r = (46 + i * 11) * s;
          canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: r),
            dir > 0 ? -0.55 : math.pi - 0.55,
            1.1,
            false,
            arcPaint,
          );
        }
      }
    }

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);

    final w = 46 * s;
    final h = 84 * s;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(10 * s),
    );

    canvas.drawRRect(body, Paint()..color = nt.surface);
    canvas.drawRRect(
      body,
      Paint()
        ..color = nt.bark.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s,
    );

    // Screen area, inset to leave a bezel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, 3 * s), width: w - 12 * s, height: h - 22 * s),
        Radius.circular(4 * s),
      ),
      Paint()..color = nt.mist.withValues(alpha: opacity),
    );

    // Speaker slot and home indicator — enough detail to read as a phone.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, -h / 2 + 7 * s), width: 12 * s, height: 2.5 * s),
        Radius.circular(2 * s),
      ),
      Paint()..color = nt.bark.withValues(alpha: 0.45 * opacity),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, h / 2 - 6 * s), width: 16 * s, height: 2.5 * s),
        Radius.circular(2 * s),
      ),
      Paint()..color = nt.bark.withValues(alpha: 0.45 * opacity),
    );

    // Amber bug dot on the screen — what the user is here to report.
    canvas.drawCircle(
      Offset(0, 3 * s),
      6 * s,
      Paint()..color = nt.amber.withValues(alpha: opacity),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShakePhonePainter old) =>
      old.angle != angle || old.muted != muted || old.nt != nt;
}
