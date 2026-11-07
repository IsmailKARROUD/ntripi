// Web NSFW pre-check — delegates to NSFWJS (TensorFlow.js) through a tiny
// vendored glue script that exposes `window.ntripiNsfw`. The glue lazily loads
// nsfwjs.min.js + the model on first use, so app boot is never blocked (see
// web/nsfw/README.md). It only scores a picture; nsfw_precheck.dart decides,
// for both platforms.
//
// Uses the modern dart:js_interop (not the deprecated dart:html/dart:js_util),
// which resolves on every platform so `flutter analyze` stays clean.
//
// Never-block contract: if the glue script or model is absent, or anything
// throws, nsfwScores() returns null — the backend image scan is the authority.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

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
  // Nullable: a browser can still hold a glue cached before it sent `sexy`.
  external double? get sexy;
}

void warmUpNsfwModel() {
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

/// The model's scores for [imageBytes], or null when it cannot answer.
Future<({double porn, double hentai, double sexy})?> nsfwScores(
    Uint8List imageBytes) async {
  try {
    final glue = _glue;
    if (glue == null) return null;
    await _ensureLoaded();
    // classify(bytes) → { porn, hentai, sexy } (each 0..1) or null.
    final result = await glue.classify(imageBytes.toJS).toDart;
    if (result == null) return null;
    return (porn: result.porn, hentai: result.hentai, sexy: result.sexy ?? 0);
  } catch (e) {
    // Any failure → no answer, which allows the upload; the backend decides.
    if (kDebugMode) debugPrint('NSFW pre-check errored (allowing): $e');
    return null;
  }
}
