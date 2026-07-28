// Mobile/desktop NSFW pre-check — runs the GantMan MobileNetV2 NSFW model
// (5 classes) through tflite_flutter, off the UI thread via IsolateInterpreter.
//
// Never-block contract: if the model asset is absent or anything throws, this
// silently disables itself and isLikelyNsfw() returns false — the backend
// Rekognition scan remains the authority.
//
// The model file (assets/models/nsfw_mobilenet.tflite, ~3 MB) is NOT vendored
// in the repo; see assets/models/README.md for how to source it. Until it's
// dropped in, this tier is a no-op.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// GantMan/nsfw_model output is 5 alphabetical classes:
//   0 drawings · 1 hentai · 2 neutral · 3 porn · 4 sexy
const int _kHentaiIndex = 1;
const int _kPornIndex = 3;
const int _kSexyIndex = 4;
const int _kModelInputSize = 224;
const double _kNsfwThreshold = 0.6;
const double _kNsfwThresholdSexy = 0.999;
const String _kModelAsset = 'assets/models/nsfw_mobilenet.tflite';

// The loaded model (null until _load succeeds, or forever if it fails).
IsolateInterpreter? _interpreter;
// Holds the in-flight/finished load so we only ever load once — see _ensureLoaded.
Future<void>? _loadFuture;

void warmUpNsfwPrecheck() {
  // Fire-and-forget: kick off the (idempotent) model load without awaiting it,
  // so mounting the upload UI never blocks on the ~3 MB model.
  _ensureLoaded();
}

// `??=` assigns _loadFuture only the first time; every later call reuses that
// same Future, so concurrent callers share one load instead of racing to reload.
Future<void> _ensureLoaded() => _loadFuture ??= _load();

Future<void> _load() async {
  try {
    // Read the bundled .tflite file into a plain (main-isolate) interpreter…
    final interpreter = await Interpreter.fromAsset(_kModelAsset);
    // …then wrap its native pointer (`address`) in an isolate-backed interpreter
    // so inference runs on a background isolate and never janks the UI thread.
    _interpreter = await IsolateInterpreter.create(address: interpreter.address);
  } catch (e) {
    // Missing/incompatible model → pre-check stays disabled (never-block).
    _interpreter = null;
    if (kDebugMode) debugPrint('NSFW pre-check disabled (model load failed): $e');
  }
}

Future<bool> isLikelyNsfw(Uint8List imageBytes) async {
  try {
    await _ensureLoaded(); // block until the (one-time) model load finishes
    final interpreter = _interpreter;
    if (interpreter == null) return false; // model unavailable → allow the upload

    // Convert the raw image into the tensor the model expects (224×224 RGB floats).
    final input = await _preprocess(imageBytes);
    if (input == null) return false;

    // Pre-allocate the buffer the model writes results into: shape [1, 5], i.e.
    // one row of 5 softmax probabilities (one per class) that the run() call fills.
    final output = List.filled(5, 0.0).reshape([1, 5]);
    await interpreter.run(input, output); // runs on the background isolate

    // output[0] = [drawings, hentai, neutral, porn, sexy], each 0.0–1.0, summing ≈1.
    final scores = (output[0] as List).cast<double>();
    // Flag only the two explicit classes above the threshold; `sexy`/`drawings`
    // stay allowed (this is a soft UX pre-check, not the authoritative filter).
    return scores[_kPornIndex] > _kNsfwThreshold ||
        scores[_kHentaiIndex] > _kNsfwThreshold ||
        scores[_kSexyIndex] > _kNsfwThresholdSexy;
  } catch (e) {
    // Any failure → allow the upload; the backend scan is authoritative.
    if (kDebugMode) debugPrint('NSFW pre-check errored (allowing): $e');
    return false;
  }
}

/// Decode + resize to 224×224 and build a normalized [1,224,224,3] float input.
/// Uses dart:ui so we don't pull in the heavy `image` package.
Future<List?> _preprocess(Uint8List bytes) async {
  // Decode and resize in one step — passing target dims lets the codec do the
  // scaling for us, so we never hold the full-resolution bitmap in memory.
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: _kModelInputSize,
    targetHeight: _kModelInputSize,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  // Pull the pixels out as a flat RGBA byte buffer: 4 bytes (R,G,B,A) per pixel.
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose(); // free the native image handle now that we have the bytes
  if (byteData == null) return null;

  final rgba = byteData.buffer.asUint8List();
  // Reshape the flat buffer into the [1, 224, 224, 3] tensor the model wants:
  // 1 image → 224 rows → 224 pixels → [R,G,B] each scaled to 0.0–1.0 (alpha dropped).
  return [
    List.generate(_kModelInputSize, (y) {          // y = row (height)
      return List.generate(_kModelInputSize, (x) {  // x = column (width)
        final i = (y * _kModelInputSize + x) * 4;   // byte offset of pixel (x,y)
        return [rgba[i] / 255.0, rgba[i + 1] / 255.0, rgba[i + 2] / 255.0];
      });
    }),
  ];
}
