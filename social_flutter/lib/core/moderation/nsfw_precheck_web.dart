// Web NSFW pre-check — delegates to NSFWJS (TensorFlow.js) through a tiny
// vendored glue script that exposes `window.ntripiNsfw`. The glue lazily loads
// tf.min.js + nsfwjs.min.js + the model on first use, so app boot is never
// blocked (see web/nsfw/README.md for the vendored files).
//
// Uses the modern dart:js_interop (not the deprecated dart:html/dart:js_util),
// which resolves on every platform so `flutter analyze` stays clean.
//
// Never-block contract: if the glue script or model is absent, or anything
// throws, isLikelyNsfw() returns false — the backend Rekognition scan is the
// authority.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

const double _kNsfwThreshold = 0.60;

Future<void>? _loadFuture;

// Bound to the global `window.ntripiNsfw` exposed by web/nsfw/nsfw_glue.js.
// Nullable: null when the glue script isn't present (pre-check disabled).
@JS('ntripiNsfw')
external _NtripiNsfw? get _glue;

extension type _NtripiNsfw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> load();
  external JSPromise<_NsfwResult?> classify(JSUint8Array bytes);
}

extension type _NsfwResult(JSObject _) implements JSObject {
  external double get porn;
  external double get hentai;
}

void warmUpNsfwPrecheck() {
  // Fire-and-forget: trigger the glue's lazy model load without awaiting it.
  _ensureLoaded();
}

Future<void> _ensureLoaded() => _loadFuture ??= _load();

Future<void> _load() async {
  try {
    final glue = _glue;
    if (glue == null) return; // glue script not present → pre-check disabled
    await glue.load().toDart;
  } catch (e) {
    if (kDebugMode) debugPrint('NSFW pre-check disabled (web load failed): $e');
  }
}

Future<bool> isLikelyNsfw(Uint8List imageBytes) async {
  try {
    final glue = _glue;
    if (glue == null) return false;
    await _ensureLoaded();
    // classify(bytes) → { porn: <0..1>, hentai: <0..1> } or null.
    final result = await glue.classify(imageBytes.toJS).toDart;
    if (result == null) return false;
    return result.porn > _kNsfwThreshold || result.hentai > _kNsfwThreshold;
  } catch (e) {
    // Any failure → allow the upload; the backend scan is authoritative.
    if (kDebugMode) debugPrint('NSFW pre-check errored (allowing): $e');
    return false;
  }
}
