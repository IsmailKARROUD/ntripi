import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/auth/token_manager.dart';
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/core/storage/secure_storage.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // The same brand-flash budget _navigate() spends warming the access token,
    // spent again on the audio engine: the plugin's global init, the asset
    // extraction and each short cue's SoundPool sample, none of which the first
    // cue should be paying for at the moment it is meant to be heard. Never
    // awaited, never throws — navigation must not wait on a decorative sound.
    unawaited(ref.read(sfxServiceProvider).warmUp());
    _navigate();
  }

  Future<void> _navigate() async {
    // Brand-flash budget — reuse it to warm the access token. If we have a
    // refresh token, kick off the rotation while the logo is still showing,
    // so the first home-screen API call doesn't pay the refresh latency.
    final brandFlash = Future<void>.delayed(const Duration(milliseconds: 1800));

    final refresh = await readRefreshToken();
    final refreshExp = await readRefreshExpiresAt();

    final hasLiveRefresh = refresh != null &&
        refresh.isNotEmpty &&
        (refreshExp == null || refreshExp.isAfter(DateTime.now()));

    if (hasLiveRefresh) {
      try {
        // Time-boxed: if the refresh hangs we still navigate, and the next
        // request will trigger another refresh attempt anyway.
        await ref
            .read(tokenManagerProvider)
            .getValidAccessToken()
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Network or session error — let the router decide where to land.
      }
    }

    await brandFlash;
    if (!mounted) return;

    if (hasLiveRefresh) {
      context.go('/profile/me');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      // Brand splash — deliberately identical in light and dark mode.
      backgroundColor: NtripiBrand.forest,
      body: Stack(
        children: [
          const _RouteTexture(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const NTripiPeakLoader(size: 120),
                      const SizedBox(height: 24),
                      const Text(
                        'NTripi',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: NtripiBrand.chrome,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.splashTagline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: NtripiBrand.chrome66,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Text(
                      l10n.splashMotto,
                      style: const TextStyle(
                        fontSize: 12,
                        color: NtripiBrand.chrome40,
                        letterSpacing: 0.2,
                      ),
                    ),
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
        color: NtripiBrand.chrome.withValues(alpha: opacity),
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
      ..color = NtripiBrand.chrome.withValues(alpha: 0.07)
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
      Paint()..color = NtripiBrand.chrome.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      Offset(w * 0.107, h * 0.985),
      4,
      Paint()..color = NtripiBrand.chrome.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
