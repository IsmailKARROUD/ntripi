// core/media/image_format.dart — what a picked file is, read from its first
// bytes. Never from its name: Android's picker re-encodes a HEIC photo to JPEG
// and keeps the .heic name, and a browser hands over whatever was chosen.
//
// The accepted formats are the ones every platform opens: what Flutter decodes
// itself (the signatures its web engine checks in image_format_detector.dart),
// plus AVIF, which a browser re-encodes first (image_pick.dart). Everything
// else is refused at the pick, before anything loads.

import 'dart:math' as math;
import 'dart:typed_data';

/// The formats a picked picture can be in, as far as the app tells them apart.
enum PickedImageFormat {
  jpeg,
  png,
  gif,
  webp,
  bmp,
  avif,
  heic,
  tiff,
  svg,
  unknown;

  /// Whether the app takes a picture in this format, on every platform.
  bool get accepted => switch (this) {
        PickedImageFormat.jpeg ||
        PickedImageFormat.png ||
        PickedImageFormat.gif ||
        PickedImageFormat.webp ||
        PickedImageFormat.bmp ||
        PickedImageFormat.avif =>
          true,
        PickedImageFormat.heic ||
        PickedImageFormat.tiff ||
        PickedImageFormat.svg ||
        PickedImageFormat.unknown =>
          false,
      };

  /// The name people know the format by, for a refusal; null when the bytes
  /// are nothing the app recognises.
  String? get label => switch (this) {
        PickedImageFormat.jpeg => 'JPEG',
        PickedImageFormat.png => 'PNG',
        PickedImageFormat.gif => 'GIF',
        PickedImageFormat.webp => 'WebP',
        PickedImageFormat.bmp => 'BMP',
        PickedImageFormat.avif => 'AVIF',
        PickedImageFormat.heic => 'HEIC',
        PickedImageFormat.tiff => 'TIFF',
        PickedImageFormat.svg => 'SVG',
        PickedImageFormat.unknown => null,
      };
}

// ISO-BMFF brands (the `ftyp` box). AVIF is checked first: an AVIF may also
// carry the generic HEIF brand `mif1`.
const _avifBrands = {'avif', 'avis'};
const _heicBrands = {
  'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'hevm', 'hevs', 'mif1', 'msf1',
};

/// The format [bytes] are in, from their signature alone.
PickedImageFormat sniffImageFormat(Uint8List bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return PickedImageFormat.jpeg;
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return PickedImageFormat.png;
  }
  if (at(0, 'GIF87a'.codeUnits) || at(0, 'GIF89a'.codeUnits)) {
    return PickedImageFormat.gif;
  }
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) {
    return PickedImageFormat.webp;
  }
  if (at(0, 'BM'.codeUnits)) return PickedImageFormat.bmp;
  if (at(4, 'ftyp'.codeUnits)) return _isoMediaFormat(bytes);
  if (at(0, const [0x49, 0x49, 0x2A, 0x00]) ||
      at(0, const [0x4D, 0x4D, 0x00, 0x2A])) {
    return PickedImageFormat.tiff;
  }
  if (_isSvg(bytes)) return PickedImageFormat.svg;
  return PickedImageFormat.unknown;
}

/// AVIF or HEIC by the `ftyp` box's brands; anything else in the same
/// container (an MP4, a MOV) is not a picture the app knows.
PickedImageFormat _isoMediaFormat(Uint8List bytes) {
  final declared =
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  // A box size of 0 or 1 means "to the end" or a 64-bit size: read a bounded
  // window instead, as also for a size the file does not hold.
  final end = math.min(
      bytes.length, declared >= 16 && declared <= 256 ? declared : 256);
  final brands = <String>[
    // The major brand, then the compatible ones after the minor version.
    if (end >= 12) String.fromCharCodes(bytes, 8, 12),
    for (var i = 16; i + 4 <= end; i += 4) String.fromCharCodes(bytes, i, i + 4),
  ];
  if (brands.any(_avifBrands.contains)) return PickedImageFormat.avif;
  if (brands.any(_heicBrands.contains)) return PickedImageFormat.heic;
  return PickedImageFormat.unknown;
}

/// An SVG document: a leading `<svg`, or `<svg` after an XML prolog, a
/// comment or a doctype within the first kilobyte.
bool _isSvg(Uint8List bytes) {
  var head = String.fromCharCodes(bytes.take(1024));
  if (head.startsWith('ï»¿')) head = head.substring(3); // UTF-8 BOM
  head = head.trimLeft();
  if (head.startsWith('<svg')) return true;
  return (head.startsWith('<?xml') ||
          head.startsWith('<!--') ||
          head.startsWith('<!DOCTYPE')) &&
      head.contains('<svg');
}
