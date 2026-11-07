// core/media/image_pick.dart — the one way the app picks a picture (a trip or
// profile cover, a profile photo): the gallery, then checks cheapest first, so
// a picture that cannot be used is named before anything loads. Nothing else
// may build an ImagePicker (test/image_pick_guard_test.dart).

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ntripi/core/media/browser_reencode_io.dart'
    if (dart.library.js_interop) 'package:ntripi/core/media/browser_reencode_web.dart'
    as browser;
import 'package:ntripi/core/media/image_format.dart';
import 'package:ntripi/core/moderation/nsfw_precheck.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// Why a picked picture was turned away.
enum PickRefusal { unsupportedFormat, tooLarge, notAllowed }

/// What a pick handed back: a picture for the crop editor, or why not.
sealed class ImagePick {
  const ImagePick();
}

/// A picture the crop editor can open.
final class PickedImage extends ImagePick {
  const PickedImage(this.bytes, this.name);

  final Uint8List bytes;
  final String name;
}

/// A picture refused at the pick, with the sentence that says why.
final class PickRefused extends ImagePick {
  const PickRefused(this.reason, {this.format});

  final PickRefusal reason;

  /// The refused format as people know it ("HEIC"); null when the bytes are
  /// nothing the app recognises.
  final String? format;

  String message(AppLocalizations l10n) => switch (reason) {
        PickRefusal.unsupportedFormat => format == null
            ? l10n.imageFormatUnknown
            : l10n.imageFormatUnsupported(format!),
        PickRefusal.tooLarge => l10n.imageTooLarge,
        PickRefusal.notAllowed => l10n.imageBlockedNsfw,
      };
}

/// Opens the gallery and vets what was picked; null when it was closed
/// without a pick. [maxBytes] caps the file as picked.
Future<ImagePick?> pickImageToCrop({int? maxBytes}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // On web, image_picker_web runs maxWidth/imageQuality through a Canvas API
    // that can throw on certain images, so the browser hands over the file as
    // it is; the crop editor outputs a fixed size regardless.
    maxWidth: kIsWeb ? null : 2400,
    imageQuality: kIsWeb ? null : 90,
  );
  if (picked == null) return null;
  return vetPickedImage(
    await picked.readAsBytes(),
    picked.name,
    web: kIsWeb,
    maxBytes: maxBytes,
  );
}

/// The checks behind [pickImageToCrop], cheapest first: the format (instant),
/// the size, an AVIF's re-encode in a browser, and last the NSFW pre-check,
/// which may wait up to its 5 s budget for the model.
@visibleForTesting
Future<ImagePick> vetPickedImage(
  Uint8List bytes,
  String name, {
  required bool web,
  int? maxBytes,
  Future<Uint8List?> Function(Uint8List bytes, String mimeType) reencode =
      browser.reencodeAsPng,
  Future<bool> Function(Uint8List bytes) isNsfw = isLikelyNsfw,
}) async {
  // The bytes, never the name: Android re-encodes a HEIC photo to JPEG and
  // keeps the .heic name.
  final format = sniffImageFormat(bytes);
  if (!format.accepted) {
    return PickRefused(PickRefusal.unsupportedFormat, format: format.label);
  }
  if (maxBytes != null && bytes.length > maxBytes) {
    return const PickRefused(PickRefusal.tooLarge);
  }
  var usable = bytes;
  // Flutter's web engine decodes AVIF through WebCodecs, which Edge refuses;
  // the browser's own decoder opens it (browser_reencode_web.dart). A phone's
  // picker has already re-encoded it.
  if (web && format == PickedImageFormat.avif) {
    final png = await reencode(bytes, 'image/avif');
    if (png == null) {
      return PickRefused(PickRefusal.unsupportedFormat, format: format.label);
    }
    usable = png;
  }
  if (await isNsfw(usable)) return const PickRefused(PickRefusal.notAllowed);
  return PickedImage(usable, name);
}
