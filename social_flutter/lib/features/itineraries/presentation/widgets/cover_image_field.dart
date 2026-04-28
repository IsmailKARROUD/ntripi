// widgets/cover_image_field.dart — Optional cover image picker for itineraries.
//
// Shows either:
//   • A tap-to-pick placeholder when no image is set
//   • A preview with Change / Remove buttons when an image is set

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';

const _maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

class CoverImageField extends StatefulWidget {
  /// URL of the existing cover image (from the server). Null if none.
  final String? initialUrl;

  /// Called when the user picks a new image. Deferred upload — caller decides
  /// when to send it to the server (on create: after itinerary creation;
  /// on edit: alongside other PATCH fields at Save time).
  final void Function(Uint8List bytes, String filename) onImageSelected;

  /// Called when the user removes the current image. Caller should call
  /// DELETE /itineraries/{id}/image at Save time.
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
  // In-memory bytes of a newly-picked image (not yet uploaded).
  Uint8List? _pickedBytes;
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
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxFileSizeBytes) {
        setState(() => _error = 'Image is too large (max 10 MB).');
        return;
      }

      setState(() {
        _pickedBytes = bytes;
        _removed = false;
      });
      widget.onImageSelected(bytes, picked.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _remove() {
    setState(() {
      _pickedBytes = null;
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
            child: _hasImage ? _ImagePreview(
              pickedBytes: _pickedBytes,
              networkUrl: _removed ? null : widget.initialUrl,
              onTap: _picking ? null : _pick,
            ) : _ImagePlaceholder(
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
                label: const Text('Change image'),
                onPressed: _picking ? null : _pick,
              ),
              const SizedBox(width: 8),
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
// Internal widgets
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
