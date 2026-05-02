// widgets/cover_image_field.dart — Optional cover image picker with pan/zoom crop.
//
// Flow:
//   1. User taps placeholder or "Change" → gallery picker opens.
//   2. After picking, _CropScreen opens full-screen — user frames the desired
//      1200×630 area by dragging and pinching. "Done" returns cropped PNG bytes.
//   3. Cropped bytes go to onImageSelected. _originalBytes is kept so "Edit crop"
//      can re-open the editor without re-picking from the gallery.
//
// Crop math (_CropScreen._done):
//   Transform: viewport_point = image_point * scale + offset
//   Inverting:  image_point  = (viewport_point - offset) / scale
//   We map viewport corners (0,0)→(vpW,vpH) to image space, clamp to image
//   bounds, then draw that rect onto a 1200×630 dart:ui canvas.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

const _maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

class CoverImageField extends StatefulWidget {
  /// URL of the existing cover image (from the server). Null if none.
  final String? initialUrl;

  /// Called when the user picks + crops a new image. Deferred upload — caller
  /// decides when to send it to the server.
  final void Function(Uint8List bytes, String filename) onImageSelected;

  /// Called when the user removes the current image.
  final VoidCallback onImageRemoved;

  const CoverImageField({
    super.key,
    this.initialUrl,
    required this.onImageSelected,
    required this.onImageRemoved,
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
        setState(() => _error = 'Image is too large (max 10 MB).');
        return;
      }
      await _openCrop(bytes, picked.name);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load image. Please try another.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _editCrop() async {
    if (_originalBytes == null) return;
    await _openCrop(_originalBytes!, _pickedFilename ?? 'cover.jpg');
  }

  Future<void> _openCrop(Uint8List source, String filename) async {
    // On web, go_router's RouterDelegate can rebuild the navigator from the
    // current URL and silently pop any page route it doesn't own.
    // showGeneralDialog pushes a PopupRoute which go_router never manages.
    final Uint8List? cropped;
    if (kIsWeb) {
      cropped = await showGeneralDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        useRootNavigator: true,
        pageBuilder: (ctx, _, __) => _CropScreen(imageBytes: source),
      );
    } else {
      cropped = await Navigator.of(context, rootNavigator: true).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _CropScreen(imageBytes: source),
        ),
      );
    }
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1200 / 630,
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
                label: const Text('Change'),
                onPressed: _picking ? null : _pick,
              ),
              if (_originalBytes != null) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.crop_outlined, size: 16),
                  label: const Text('Edit crop'),
                  onPressed: _picking ? null : _editCrop,
                ),
              ],
              const SizedBox(width: 4),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                label: Text('Remove', style: TextStyle(color: cs.error)),
                onPressed: _remove,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _CropScreen — full-screen pan/zoom crop editor
// ---------------------------------------------------------------------------

class _CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropScreen({required this.imageBytes});

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

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        srcImage,
        Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
        const Rect.fromLTWH(0, 0, 1200, 630),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(1200, 630);
      final byteData = await output.toByteData(format: ui.ImageByteFormat.png);

      srcImage.dispose();
      output.dispose();

      if (!mounted) return;
      Navigator.of(context).pop(byteData?.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kSand,
        foregroundColor: Colors.white,
        title: const Text(
          'Adjust cover photo',
          style: TextStyle(color: kBark),
        ),
        actions: [
          if (_processing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _imageSize == null ? null : _done,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: kForest,
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
                color: kSand,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AspectRatio(
              aspectRatio: 1200 / 630,
              child: _imageSize == null
                  ? const Center(
                      child: CircularProgressIndicator(color: kSand),
                    )
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
          const Text(
            'Pinch to zoom · Drag to reposition',
            style: TextStyle(color: kSand, fontSize: 13),
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
            Image.network(
              _absoluteUrl(networkUrl!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _broken(),
            ),
          // Subtle darkening hint that the image is tappable
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              decoration: const BoxDecoration(
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

  Widget _broken() => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
      );
}

class _ImagePlaceholder extends StatelessWidget {
  final bool picking;
  final VoidCallback? onTap;

  const _ImagePlaceholder({required this.picking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(
            color: Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: picking
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 36, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'Add a cover image',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recommended: 1200 × 630',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
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
