// widgets/cover_image_field.dart — Optional cover image picker with pan/zoom crop.
//
// Flow:
//   1. User taps placeholder or "Change" → gallery picker opens.
//   2. After picking, _CropScreen opens full-screen — user frames the desired
//      1200×630 area by dragging and pinching. "Done" returns cropped PNG bytes.
//   3. Cropped bytes go to onImageSelected. _originalBytes is kept so "Edit crop"
//      can re-open the editor without re-picking from the gallery.
//
// The editor is an OverlayEntry + LocalHistoryEntry rather than a pushed route,
// so go_router can never interfere and the system/browser back button still
// dismisses it. Both the overlay it goes into and its opacity are load-bearing
// — see openImageCropOverlay.
//
// Crop math (_CropScreen._done):
//   Transform: viewport_point = image_point * scale + offset
//   Inverting:  image_point  = (viewport_point - offset) / scale
//   We map viewport corners (0,0)→(vpW,vpH) to image space, clamp to image
//   bounds, then draw that rect onto a 1200×630 dart:ui canvas.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/cache/image_cache.dart';
import 'package:social_flutter/core/moderation/nsfw_precheck.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/core/utils/platform_utils.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/loaders.dart';

const _maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

/// Launches the full-screen crop overlay with the given source bytes and
/// target dimensions. Returns the cropped PNG bytes, or null if cancelled.
///
/// Used by [CoverImageField] and by ad-hoc avatar pickers that don't want
/// the full picker chrome — they only need the crop step after their own
/// gallery pick.
Future<Uint8List?> openImageCropOverlay(
  BuildContext context, {
  required Uint8List sourceBytes,
  required int targetWidth,
  required int targetHeight,
}) async {
  // The root Navigator's overlay — NOT Overlay.of(context, rootOverlay: true).
  // BetterFeedback wraps MaterialApp, so the true root overlay is the feedback
  // package's, which lives outside MaterialApp: an entry there gets no app
  // Theme and no app l10n. Resolve it before the await so the crop screen is
  // guaranteed to land inside the app's own navigator.
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return null;

  final completer = Completer<Uint8List?>();
  bool closed = false;

  late OverlayEntry overlayEntry;
  final historyEntry = LocalHistoryEntry(
    onRemove: () {
      if (closed) return;
      closed = true;
      overlayEntry.remove();
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  overlayEntry = OverlayEntry(
    // Deliberately not opaque: an opaque entry makes the Overlay drop every
    // entry below it that doesn't maintainState, which would unmount the
    // routes underneath. The crop Scaffold covers the screen by itself.
    builder: (_) => _CropScreen(
      imageBytes: sourceBytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      onDone: (bytes) {
        if (closed) return;
        closed = true;
        historyEntry.remove();
        overlayEntry.remove();
        if (!completer.isCompleted) completer.complete(bytes);
      },
      onCancel: () => historyEntry.remove(),
    ),
  );

  ModalRoute.of(context)?.addLocalHistoryEntry(historyEntry);
  overlay.insert(overlayEntry);

  return completer.future;
}

class CoverImageField extends StatefulWidget {
  /// URL of the existing cover image (from the server). Null if none.
  final String? initialUrl;

  /// Cropped bytes already picked by the user (deferred upload not yet sent).
  /// Lets the field re-hydrate its preview when the parent rebuilds it after
  /// this widget was unmounted (e.g. collapsing the optional-fields section).
  final Uint8List? initialBytes;
  final String? initialFilename;

  /// True when the user already removed the existing image in a prior mount.
  final bool initialRemoved;

  /// Called when the user picks + crops a new image. Deferred upload — caller
  /// decides when to send it to the server.
  final void Function(Uint8List bytes, String filename) onImageSelected;

  /// Called when the user removes the current image.
  final VoidCallback onImageRemoved;

  /// Target output dimensions for the crop. Default matches itinerary covers
  /// (1200×630). Avatars override to 800×800.
  final int targetWidth;
  final int targetHeight;

  const CoverImageField({
    super.key,
    this.initialUrl,
    this.initialBytes,
    this.initialFilename,
    this.initialRemoved = false,
    required this.onImageSelected,
    required this.onImageRemoved,
    this.targetWidth = 1200,
    this.targetHeight = 630,
  });

  @override
  State<CoverImageField> createState() => _CoverImageFieldState();
}

class _CoverImageFieldState extends State<CoverImageField> {
  Uint8List? _originalBytes; // pre-crop source — kept for "Edit crop"
  Uint8List? _pickedBytes; // cropped bytes ready to upload
  String? _pickedFilename;
  bool _removed = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Re-hydrate from the parent's deferred-upload state so the preview
    // survives this widget being unmounted and rebuilt (e.g. toggling the
    // optional-fields section). The parent is the source of truth for what
    // will actually be uploaded on save.
    _pickedBytes = widget.initialBytes;
    _pickedFilename = widget.initialFilename;
    _removed = widget.initialRemoved;
    // Warm up the NSFW model now so the check is instant when the user picks.
    warmUpNsfwPrecheck();
  }

  bool get _hasImage =>
      !_removed && (_pickedBytes != null || widget.initialUrl != null);

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      // On web, image_picker_web runs maxWidth/imageQuality through a Canvas
      // API that can throw on certain images. Skip pre-processing on web —
      // the crop screen outputs 1200×630 regardless of input size.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: kIsWeb ? null : 2400,
        imageQuality: kIsWeb ? null : 90,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxFileSizeBytes) {
        if (mounted) {
          setState(
              () => _error = AppLocalizations.of(context)!.imageTooLarge);
        }
        return;
      }
      // Client-side NSFW pre-check — instant reject before any upload. Returns
      // false on any failure (backend Rekognition scan is the real authority).
      if (await isLikelyNsfw(bytes)) {
        if (mounted) {
          setState(
              () => _error = AppLocalizations.of(context)!.imageBlockedNsfw);
        }
        return;
      }
      await _openCrop(bytes, picked.name);
    } catch (e) {
      if (mounted)
        setState(
            () => _error = AppLocalizations.of(context)!.couldNotLoadImage);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _editCrop() async {
    if (_originalBytes == null) return;
    await _openCrop(_originalBytes!, _pickedFilename ?? 'cover.jpg');
  }

  Future<void> _openCrop(Uint8List source, String filename) async {
    final cropped = await openImageCropOverlay(
      context,
      sourceBytes: source,
      targetWidth: widget.targetWidth,
      targetHeight: widget.targetHeight,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _originalBytes = source;
      _pickedBytes = cropped;
      _pickedFilename = filename;
      _removed = false;
    });
    widget.onImageSelected(cropped, filename);
  }

  void _remove() {
    setState(() {
      _originalBytes = null;
      _pickedBytes = null;
      _pickedFilename = null;
      _removed = true;
      _error = null;
    });
    widget.onImageRemoved();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: isDesktopWeb() ? kDesktopMaxWidth : double.infinity),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: widget.targetWidth / widget.targetHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _hasImage
                  ? _ImagePreview(
                      pickedBytes: _pickedBytes,
                      networkUrl: _removed ? null : widget.initialUrl,
                      onTap: _picking ? null : _pick,
                    )
                  : _ImagePlaceholder(
                      picking: _picking,
                      onTap: _picking ? null : _pick,
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ],
          if (_hasImage) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.photo_outlined, size: 16),
                  label: Text(AppLocalizations.of(context)!.coverChangeButton),
                  onPressed: _picking ? null : _pick,
                ),
                if (_originalBytes != null) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.crop_outlined, size: 16),
                    label: Text(AppLocalizations.of(context)!.coverEditCropButton),
                    onPressed: _picking ? null : _editCrop,
                  ),
                ],
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                  label: Text(AppLocalizations.of(context)!.removeButton, style: TextStyle(color: cs.error)),
                  onPressed: _remove,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CropScreen — full-screen pan/zoom crop editor
// ---------------------------------------------------------------------------

class _CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final int targetWidth;
  final int targetHeight;
  final void Function(Uint8List bytes) onDone;
  final VoidCallback onCancel;

  const _CropScreen({
    required this.imageBytes,
    required this.targetWidth,
    required this.targetHeight,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  bool _processing = false;
  Size? _imageSize;

  // Current transform: image top-left in viewport coordinates + uniform scale.
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _initialized = false;
  Size? _viewportSize;

  // Snapshot taken at the start of each gesture.
  double _gestureBaseScale = 1.0;
  Offset _gestureBaseOffset = Offset.zero;
  Offset _gestureBaseFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decodeImageSize();
  }

  Future<void> _decodeImageSize() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    if (mounted) {
      setState(() {
        _imageSize = Size(img.width.toDouble(), img.height.toDouble());
      });
    }
    img.dispose();
  }

  // Minimum scale at which the image exactly cover-fills the viewport.
  double _minScale(Size vp) =>
      math.max(vp.width / _imageSize!.width, vp.height / _imageSize!.height);

  // Hard-clamp so the viewport is always fully covered:
  //   offset.dx ∈ [vpW − iW*s, 0],  offset.dy ∈ [vpH − iH*s, 0]
  Offset _clampOffset(Offset o, double s, Size vp) => Offset(
        o.dx.clamp(vp.width - _imageSize!.width * s, 0.0),
        o.dy.clamp(vp.height - _imageSize!.height * s, 0.0),
      );

  // Called synchronously from LayoutBuilder — no setState, just field writes.
  void _maybeInit(Size vp) {
    if (_imageSize == null) return;
    if (!_initialized) {
      _initialized = true;
      _viewportSize = vp;
      final ms = _minScale(vp);
      _scale = ms;
      _offset = Offset(
        (vp.width - _imageSize!.width * ms) / 2,
        (vp.height - _imageSize!.height * ms) / 2,
      );
    } else if (_viewportSize != vp) {
      _viewportSize = vp;
      final ms = _minScale(vp);
      _scale = _scale.clamp(ms, ms * 8);
      _offset = _clampOffset(_offset, _scale, vp);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureBaseScale = _scale;
    _gestureBaseOffset = _offset;
    _gestureBaseFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_viewportSize == null || _imageSize == null) return;
    final vp = _viewportSize!;
    final ms = _minScale(vp);
    final newScale = (_gestureBaseScale * d.scale).clamp(ms, ms * 8);

    // Keep the focal point anchored in image-space across both pan and zoom.
    final focalInImage =
        (_gestureBaseFocal - _gestureBaseOffset) / _gestureBaseScale;
    final rawOffset = d.localFocalPoint - focalInImage * newScale;

    setState(() {
      _scale = newScale;
      _offset = _clampOffset(rawOffset, newScale, vp);
    });
  }

  Future<void> _done() async {
    if (_imageSize == null || _viewportSize == null) return;
    setState(() => _processing = true);
    try {
      final vpW = _viewportSize!.width;
      final vpH = _viewportSize!.height;

      // Invert: image_point = (viewport_point − offset) / scale
      final srcLeft = (-_offset.dx / _scale).clamp(0.0, _imageSize!.width);
      final srcTop = (-_offset.dy / _scale).clamp(0.0, _imageSize!.height);
      final srcRight =
          ((vpW - _offset.dx) / _scale).clamp(0.0, _imageSize!.width);
      final srcBottom =
          ((vpH - _offset.dy) / _scale).clamp(0.0, _imageSize!.height);

      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final srcImage = frame.image;

      final tw = widget.targetWidth;
      final th = widget.targetHeight;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        srcImage,
        Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
        Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(tw, th);
      final byteData = await output.toByteData(format: ui.ImageByteFormat.png);

      srcImage.dispose();
      output.dispose();

      if (!mounted) return;
      final bytes = byteData?.buffer.asUint8List();
      if (bytes != null) {
        widget.onDone(bytes);
      } else {
        setState(() => _processing = false);
      }
    } catch (_) {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: NtripiBrand.backdrop,
      appBar: AppBar(
        backgroundColor: nt.sand,
        foregroundColor: NtripiBrand.chrome,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
        ),
        title: Text(
          AppLocalizations.of(context)!.coverAdjustTitle,
          style: TextStyle(color: nt.bark),
        ),
        actions: [
          if (_processing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: NTripiRingLoader(size: 20)),
            )
          else
            TextButton(
              onPressed: _imageSize == null ? null : _done,
              child: Text(
                AppLocalizations.of(context)!.doneTooltip,
                style: TextStyle(
                  color: nt.forest,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: nt.sand,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AspectRatio(
              aspectRatio: widget.targetWidth / widget.targetHeight,
              child: _imageSize == null
                  ? const Center(child: NTripiRingLoader())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final vp = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        _maybeInit(vp);

                        return GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox.expand(
                              child: _initialized
                                  ? Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          left: _offset.dx,
                                          top: _offset.dy,
                                          width: _imageSize!.width * _scale,
                                          height: _imageSize!.height * _scale,
                                          child: Image.memory(
                                            widget.imageBytes,
                                            fit: BoxFit.fill,
                                            gaplessPlayback: true,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox(),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.pinchToZoomHint,
            style: TextStyle(color: nt.sand, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal preview widgets
// ---------------------------------------------------------------------------

class _ImagePreview extends StatelessWidget {
  final Uint8List? pickedBytes;
  final String? networkUrl;
  final VoidCallback? onTap;

  const _ImagePreview({
    required this.pickedBytes,
    required this.networkUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (pickedBytes != null)
            Image.memory(pickedBytes!, fit: BoxFit.cover)
          else if (networkUrl != null)
            CachedNetworkImage(
              imageUrl: _absoluteUrl(networkUrl!),
              cacheManager: NtripiImageCacheManager(),
              fit: BoxFit.cover,
              errorWidget: (ctx, __, ___) => _broken(ctx),
            ),
          // Subtle darkening hint that the image is tappable
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black26],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _broken(BuildContext context) => Container(
        color: context.nt.sand,
        child: Icon(Icons.broken_image_outlined, color: context.nt.text3),
      );
}

class _ImagePlaceholder extends StatelessWidget {
  final bool picking;
  final VoidCallback? onTap;

  const _ImagePlaceholder({required this.picking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: nt.overlayChrome.withValues(alpha: 0.5),
          border: Border.all(color: nt.text3, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(16),
        ),
        child: picking
            ? const Center(child: NTripiRingLoader())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_rounded,
                      size: 28, color: nt.forest),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.addCoverImage,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: nt.bark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.coverOptionalMapFallback,
                    style: TextStyle(fontSize: 11, color: nt.text2),
                  ),
                ],
              ),
      ),
    );
  }
}

/// If url is relative (from filesystem storage), prepend the API base URL.
String _absoluteUrl(String url) {
  if (url.startsWith('/')) return '$kApiBaseUrl$url';
  return url;
}
