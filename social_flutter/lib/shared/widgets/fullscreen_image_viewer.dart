// shared/widgets/fullscreen_image_viewer.dart — Reusable full-screen photo viewer.
//
// Tap a cover or avatar image anywhere in the app to open it full-screen with
// pinch/double-tap zoom and pan (via photo_view). Dismiss with the X button or
// system back. Callers pass the raw image URL (relative or absolute); the viewer
// absolutizes it the same way the profile hero does.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

/// Opens [imageUrl] full-screen on a black backdrop. [imageUrl] may be a
/// relative `/uploads/...` path (backend media) or an absolute URL.
///
/// [sourcePosition] is the global tap point; when given, the viewer grows out
/// of (and collapses back into) that point instead of scaling from the center.
void showFullscreenImage(
  BuildContext context, {
  required String imageUrl,
  Offset? sourcePosition,
}) {
  if (imageUrl.isEmpty) return;
  // Same relative→absolute rule the profile hero uses for cover images.
  final resolved = imageUrl.startsWith('/') ? '$kApiBaseUrl$imageUrl' : imageUrl;

  // Map the tap point to a scale alignment (-1..1 across the screen) so the
  // ScaleTransition emanates from exactly where the user tapped.
  var origin = Alignment.center;
  if (sourcePosition != null) {
    final size = MediaQuery.of(context).size;
    if (size.width > 0 && size.height > 0) {
      origin = Alignment(
        (sourcePosition.dx / size.width) * 2 - 1,
        (sourcePosition.dy / size.height) * 2 - 1,
      );
    }
  }

  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => _FullscreenImageScreen(imageUrl: resolved),
      // Grow + fade out of the tapped point (or the center as a fallback).
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.ease);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
            alignment: origin,
            child: child,
          ),
        );
      },
    ),
  );
}

class _FullscreenImageScreen extends StatelessWidget {
  final String imageUrl;

  const _FullscreenImageScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NtripiBrand.backdrop,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoView(
              imageProvider: CachedNetworkImageProvider(
                imageUrl,
                cacheManager: NtripiImageCacheManager(),
              ),
              backgroundDecoration:
                  const BoxDecoration(color: NtripiBrand.backdrop),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              initialScale: PhotoViewComputedScale.contained,
              loadingBuilder: (_, _) => const Center(
                child: CircularProgressIndicator(color: NtripiBrand.chrome),
              ),
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: NtripiBrand.chrome, size: 48),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.close, color: NtripiBrand.chrome),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
