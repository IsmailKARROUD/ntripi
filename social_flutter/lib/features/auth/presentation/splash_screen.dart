import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    final token = await readToken();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      context.go('/profile/me');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: kForest,
      body: Stack(
        children: [
          _RouteTexture(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NTripiPeakLoader(size: 120),
                      SizedBox(height: 24),
                      Text(
                        'NTripi',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Discover & share travel itineraries\ncrafted by real explorers',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xA8FFFFFF),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Dot(opacity: 1.0),
                          SizedBox(width: 6),
                          _Dot(opacity: 0.4),
                          SizedBox(width: 6),
                          _Dot(opacity: 0.4),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Explore the world, one route at a time',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x66FFFFFF),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double opacity;
  const _Dot({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _RouteTexture extends StatelessWidget {
  const _RouteTexture();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _RouteTexturePainter(),
    );
  }
}

class _RouteTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path1 = Path()
      ..moveTo(w * 0.107, h * 0.985)
      ..lineTo(w * 0.107, h * 0.493)
      ..lineTo(w * 0.48, h * 0.739)
      ..lineTo(w * 0.907, h * 0.246)
      ..lineTo(w * 0.907, h * 0.123);
    canvas.drawPath(path1, paint);

    final path2 = Path()
      ..moveTo(0, h * 0.616)
      ..lineTo(w * 0.213, h * 0.37)
      ..lineTo(w * 0.533, h * 0.554)
      ..lineTo(w * 0.8, h * 0.185);
    canvas.drawPath(path2, paint..strokeWidth = 1.0);

    canvas.drawCircle(
      Offset(w * 0.907, h * 0.123),
      6,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      Offset(w * 0.107, h * 0.985),
      4,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
