// core/media/browser_reencode_web.dart — turns a picked picture into a PNG
// through the browser's own image decoder (createImageBitmap), for a format
// Flutter's web engine cannot open itself.
//
// Flutter decodes AVIF through WebCodecs' ImageDecoder in a Chromium browser,
// and Edge refuses every AVIF there ("Failed to retrieve track metadata",
// Edge 157, 2026-11-07) while createImageBitmap opens the same files.

import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The longest side handed on: what the phones' picker resizes to. The crop
/// editor outputs at most 1200 px, and a smaller PNG encodes faster.
const int _kMaxSide = 2400;

/// [bytes] as a PNG, or null when this browser cannot open them.
Future<Uint8List?> reencodeAsPng(Uint8List bytes, String mimeType) async {
  try {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final bitmap = await web.window.createImageBitmap(blob).toDart;
    try {
      final scale =
          math.min(1.0, _kMaxSide / math.max(bitmap.width, bitmap.height));
      final width = math.max(1, (bitmap.width * scale).round());
      final height = math.max(1, (bitmap.height * scale).round());
      final canvas = web.OffscreenCanvas(width, height);
      final context =
          canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D;
      context.drawImage(bitmap, 0, 0, width, height);
      // PNG keeps an AVIF's transparency for the crop editor.
      final png = await canvas
          .convertToBlob(web.ImageEncodeOptions(type: 'image/png'))
          .toDart;
      final buffer = await png.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } finally {
      bitmap.close();
    }
  } catch (_) {
    return null;
  }
}
