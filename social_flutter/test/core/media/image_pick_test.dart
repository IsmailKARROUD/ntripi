// vetPickedImage — the checks every picked picture goes through, cheapest
// first. The point of the order: a picture in a format the app cannot open is
// named at once, before the NSFW model (up to 5 s) or the crop editor loads —
// the "keeps loading" the owner reported for a HEIC on the web (2026-11-07).
//
// The re-encode and the NSFW pre-check are fakes that count their calls, so
// "nothing slow ran" is an exact assertion.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/media/image_pick.dart';
import 'package:ntripi/l10n/app_localizations.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

Uint8List _file(List<int> head, [int body = 64]) =>
    Uint8List.fromList([...head, ...List.filled(body, 0x41)]);

final _jpeg = _file([0xFF, 0xD8, 0xFF, 0xE0]);
// heif-enc's HEIC header: major heic, compatible mif1 heic miaf.
final _heic = _file([
  0, 0, 0, 0x1C, ...'ftyp'.codeUnits, ...'heic'.codeUnits, 0, 0, 0, 0,
  ...'mif1'.codeUnits, ...'heic'.codeUnits, ...'miaf'.codeUnits,
]);
// ffmpeg's AVIF header: major avif, compatible avif mif1 miaf MA1A.
final _avif = _file([
  0, 0, 0, 0x20, ...'ftyp'.codeUnits, ...'avif'.codeUnits, 0, 0, 0, 0,
  ...'avif'.codeUnits, ...'mif1'.codeUnits, ...'miaf'.codeUnits,
  ...'MA1A'.codeUnits,
]);
final _png = _file([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

/// Fakes for the two slow steps, recording what they were handed.
class _Slow {
  _Slow({this.reencoded, this.flagged = false});

  final Uint8List? reencoded;
  final bool flagged;
  final reencodes = <String>[];
  final scanned = <Uint8List>[];

  Future<Uint8List?> reencode(Uint8List bytes, String mimeType) async {
    reencodes.add(mimeType);
    return reencoded;
  }

  Future<bool> isNsfw(Uint8List bytes) async {
    scanned.add(bytes);
    return flagged;
  }
}

Future<ImagePick> _vet(
  Uint8List bytes,
  _Slow slow, {
  String name = 'picture',
  bool web = true,
  int? maxBytes,
}) =>
    vetPickedImage(bytes, name,
        web: web,
        maxBytes: maxBytes,
        reencode: slow.reencode,
        isNsfw: slow.isNsfw);

Matcher _refused(PickRefusal reason, {String? format}) => isA<PickRefused>()
    .having((r) => r.reason, 'reason', reason)
    .having((r) => r.format, 'format', format);

void main() {
  group('a format the app cannot open is refused before anything slow', () {
    test('HEIC is named — and checked before the size, too', () async {
      final slow = _Slow(reencoded: _png);
      final pick = await _vet(_heic, slow, name: 'IMG_0001.HEIC', maxBytes: 4);
      expect(pick, _refused(PickRefusal.unsupportedFormat, format: 'HEIC'));
      expect(slow.reencodes, isEmpty);
      expect(slow.scanned, isEmpty, reason: 'the NSFW model must not be waited on');
    });

    test('bytes the app does not recognise name no format', () async {
      final slow = _Slow();
      final pick = await _vet(_file([7, 7, 7, 7]), slow);
      expect(pick, _refused(PickRefusal.unsupportedFormat));
      expect(slow.scanned, isEmpty);
    });

    test('on a phone too', () async {
      final slow = _Slow();
      final pick = await _vet(_heic, slow, web: false);
      expect(pick, _refused(PickRefusal.unsupportedFormat, format: 'HEIC'));
      expect(slow.scanned, isEmpty);
    });
  });

  test('the bytes decide, never the name', () async {
    // Android's picker re-encodes a HEIC photo to JPEG and keeps the name.
    final slow = _Slow();
    final pick = await _vet(_jpeg, slow, name: 'scaled_IMG_0001.heic');
    expect(pick, isA<PickedImage>());
    expect((pick as PickedImage).bytes, same(_jpeg));
    expect(pick.name, 'scaled_IMG_0001.heic');
  });

  test('a file over the cap is refused before the NSFW check', () async {
    final slow = _Slow();
    final pick = await _vet(_jpeg, slow, maxBytes: _jpeg.length - 1);
    expect(pick, _refused(PickRefusal.tooLarge));
    expect(slow.scanned, isEmpty);
  });

  test('a JPEG goes on as it is, through the NSFW check', () async {
    final slow = _Slow();
    final pick = await _vet(_jpeg, slow, maxBytes: _jpeg.length);
    expect(pick, isA<PickedImage>());
    expect((pick as PickedImage).bytes, same(_jpeg));
    expect(slow.reencodes, isEmpty, reason: 'only an AVIF is re-encoded');
    expect(slow.scanned.single, same(_jpeg));
  });

  test('a picture the NSFW pre-check flags is refused', () async {
    final pick = await _vet(_jpeg, _Slow(flagged: true));
    expect(pick, _refused(PickRefusal.notAllowed));
  });

  group('AVIF', () {
    test('in a browser it is re-encoded, and the editor gets the PNG',
        () async {
      final slow = _Slow(reencoded: _png);
      final pick = await _vet(_avif, slow, name: 'photo.avif');
      expect(slow.reencodes, ['image/avif']);
      expect(slow.scanned.single, same(_png),
          reason: 'the NSFW check sees what the editor will get');
      expect(pick, isA<PickedImage>());
      expect((pick as PickedImage).bytes, same(_png));
      expect(pick.name, 'photo.avif');
    });

    test('a browser that cannot open it refuses it as AVIF', () async {
      final slow = _Slow();
      final pick = await _vet(_avif, slow);
      expect(pick, _refused(PickRefusal.unsupportedFormat, format: 'AVIF'));
      expect(slow.scanned, isEmpty);
    });

    test('on a phone it goes on as it is — the picker re-encoded it', () async {
      final slow = _Slow(reencoded: _png);
      final pick = await _vet(_avif, slow, web: false);
      expect(slow.reencodes, isEmpty);
      expect((pick as PickedImage).bytes, same(_avif));
    });

    test('the size cap applies to the file as picked', () async {
      final slow = _Slow(reencoded: _png);
      final pick = await _vet(_avif, slow, maxBytes: _avif.length - 1);
      expect(pick, _refused(PickRefusal.tooLarge));
      expect(slow.reencodes, isEmpty);
    });
  });

  test('each refusal says why', () {
    expect(
        const PickRefused(PickRefusal.unsupportedFormat, format: 'HEIC')
            .message(_l10n),
        "HEIC images can't be opened here. Choose a JPEG, PNG or WebP image.");
    expect(const PickRefused(PickRefusal.unsupportedFormat).message(_l10n),
        _l10n.imageFormatUnknown);
    expect(const PickRefused(PickRefusal.tooLarge).message(_l10n),
        _l10n.imageTooLarge);
    expect(const PickRefused(PickRefusal.notAllowed).message(_l10n),
        _l10n.imageBlockedNsfw);
  });
}
