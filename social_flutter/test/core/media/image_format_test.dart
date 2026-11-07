// sniffImageFormat reads a picked file's format from its first bytes — never
// its name, which Android's picker keeps as .heic on the JPEG it re-encodes.
// The ISO-BMFF headers below are the ones heif-enc, Pillow and ffmpeg wrote
// (2026-11-07), so HEIC and AVIF are told apart the way real files differ.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/media/image_format.dart';

Uint8List _bytes(List<Object> parts) => Uint8List.fromList([
      for (final part in parts)
        if (part is String) ...part.codeUnits else ...part as List<int>,
    ]);

/// An `ftyp` box of [size] bytes: the major brand, a zero minor version, then
/// the compatible brands — followed by [tail] bytes of whatever comes next.
Uint8List _ftyp(int size, String major, List<String> compatible,
        {int tail = 32}) =>
    _bytes([
      [size >> 24 & 0xFF, size >> 16 & 0xFF, size >> 8 & 0xFF, size & 0xFF],
      'ftyp',
      major,
      [0, 0, 0, 0],
      ...compatible,
      List.filled(tail, 0x41),
    ]);

void main() {
  group('accepted everywhere', () {
    final cases = <String, Uint8List>{
      'JPEG': _bytes([
        [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10],
        'JFIF'
      ]),
      'PNG': _bytes([
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D],
        'IHDR'
      ]),
      'GIF87a': _bytes(['GIF87a', List.filled(8, 0)]),
      'GIF89a': _bytes(['GIF89a', List.filled(8, 0)]),
      'WebP': _bytes([
        'RIFF',
        [0x24, 0, 0, 0],
        'WEBPVP8 ',
        List.filled(8, 0)
      ]),
      'BMP': _bytes(['BM', List.filled(24, 0)]),
      // ffmpeg / Pillow: major avif, compatible avif mif1 miaf MA1A.
      'AVIF (ffmpeg)': _ftyp(32, 'avif', ['avif', 'mif1', 'miaf', 'MA1A']),
      // heif-enc: major avif, compatible mif1 avif miaf.
      'AVIF (heif-enc)': _ftyp(28, 'avif', ['mif1', 'avif', 'miaf']),
      // A generic HEIF major brand that says AVIF among the compatible ones.
      'AVIF (mif1 major)': _ftyp(24, 'mif1', ['mif1', 'avif']),
      'AVIF sequence': _ftyp(24, 'avis', ['avis', 'msf1']),
    };
    final expected = <String, PickedImageFormat>{
      'JPEG': PickedImageFormat.jpeg,
      'PNG': PickedImageFormat.png,
      'GIF87a': PickedImageFormat.gif,
      'GIF89a': PickedImageFormat.gif,
      'WebP': PickedImageFormat.webp,
      'BMP': PickedImageFormat.bmp,
      'AVIF (ffmpeg)': PickedImageFormat.avif,
      'AVIF (heif-enc)': PickedImageFormat.avif,
      'AVIF (mif1 major)': PickedImageFormat.avif,
      'AVIF sequence': PickedImageFormat.avif,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        final format = sniffImageFormat(value);
        expect(format, expected[key]);
        expect(format.accepted, isTrue);
      });
    }
  });

  group('refused, and named', () {
    test('HEIC (heif-enc: major heic, compatible mif1 heic miaf)', () {
      final format = sniffImageFormat(_ftyp(28, 'heic', ['mif1', 'heic', 'miaf']));
      expect(format, PickedImageFormat.heic);
      expect(format.accepted, isFalse);
      expect(format.label, 'HEIC');
    });

    test('a generic HEIF (mif1 without avif) reads as HEIC', () {
      expect(sniffImageFormat(_ftyp(24, 'mif1', ['mif1', 'heic'])),
          PickedImageFormat.heic);
      expect(sniffImageFormat(_ftyp(16, 'mif1', [])), PickedImageFormat.heic);
    });

    test('TIFF in both byte orders', () {
      for (final head in [
        [0x49, 0x49, 0x2A, 0x00],
        [0x4D, 0x4D, 0x00, 0x2A],
      ]) {
        final format = sniffImageFormat(_bytes([head, List.filled(12, 0)]));
        expect(format, PickedImageFormat.tiff);
        expect(format.accepted, isFalse);
        expect(format.label, 'TIFF');
      }
    });

    test('SVG, bare, after a BOM, after whitespace, or after a prolog', () {
      for (final text in [
        '<svg xmlns="http://www.w3.org/2000/svg"/>',
        '  \n<svg viewBox="0 0 1 1"/>',
        '<?xml version="1.0" encoding="UTF-8"?>\n<svg/>',
        '<!-- logo -->\n<svg/>',
        '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x">\n<svg/>',
      ]) {
        expect(sniffImageFormat(_bytes([text])), PickedImageFormat.svg,
            reason: text);
      }
      final withBom = _bytes([
        [0xEF, 0xBB, 0xBF],
        '<svg/>'
      ]);
      expect(sniffImageFormat(withBom), PickedImageFormat.svg);
      expect(PickedImageFormat.svg.label, 'SVG');
      expect(PickedImageFormat.svg.accepted, isFalse);
    });
  });

  group('not a picture the app knows', () {
    final cases = <String, Uint8List>{
      'empty': Uint8List(0),
      'two bytes': Uint8List.fromList([0xFF, 0xD8]),
      'arbitrary bytes': Uint8List.fromList(List.filled(64, 7)),
      'text': _bytes(['hello, world']),
      'a WAV file (RIFF but not WEBP)': _bytes([
        'RIFF',
        [0x24, 0, 0, 0],
        'WAVEfmt ',
      ]),
      'an MP4 video (ftyp isom)': _ftyp(24, 'isom', ['isom', 'mp41']),
      'an XML document that is not SVG': _bytes(['<?xml version="1.0"?><note/>']),
      'a truncated ftyp box': _bytes([
        [0, 0, 0, 0x18],
        'ftypavi',
      ]),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () {
        final format = sniffImageFormat(value);
        expect(format, PickedImageFormat.unknown);
        expect(format.accepted, isFalse);
        expect(format.label, isNull);
      });
    }
  });

  group('an ftyp box that lies about its size never reads out of range', () {
    test('a size larger than the file', () {
      final bytes = _ftyp(0xFFFFFFF0, 'avif', ['mif1'], tail: 0);
      expect(sniffImageFormat(bytes), PickedImageFormat.avif);
    });

    test('a size of 0 ("to the end") or 1 (64-bit size follows)', () {
      expect(sniffImageFormat(_ftyp(0, 'heic', ['mif1'])),
          PickedImageFormat.heic);
      expect(sniffImageFormat(_ftyp(1, 'avif', [])), PickedImageFormat.avif);
    });

    test('a size smaller than the box header', () {
      expect(sniffImageFormat(_ftyp(8, 'avif', [], tail: 0)),
          PickedImageFormat.avif);
    });
  });

  test('every refused format the bytes identify has a name to show', () {
    for (final format in PickedImageFormat.values) {
      if (format.accepted || format == PickedImageFormat.unknown) continue;
      expect(format.label, isNotNull, reason: '$format');
    }
  });
}
