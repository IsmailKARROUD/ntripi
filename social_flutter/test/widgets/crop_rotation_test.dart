// unrotateCrop maps a crop rect from the editor's rotated "display space" back
// into real source pixels. The crop editor does its pan/zoom math on the image
// as the user sees it; drawImageRect samples the source, so the two spaces have
// to be reconciled exactly or a rotated cover comes out framed on the wrong
// region.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';

/// Display-space size of a source image at [quarterTurns] — odd turns swap.
Size _display(Size image, int quarterTurns) => quarterTurns.isOdd
    ? Size(image.height, image.width)
    : image;

void main() {
  // Landscape on purpose: a square source would hide every width/height swap.
  const image = Size(200, 100);

  group('unrotateCrop', () {
    test('turn 0 is the identity', () {
      const crop = Rect.fromLTRB(10, 20, 60, 80);
      expect(unrotateCrop(crop, image, 0), crop);
    });

    test('a full-frame display crop maps back to the whole image at every turn',
        () {
      for (var turns = 0; turns < 4; turns++) {
        final display = _display(image, turns);
        final full = Rect.fromLTWH(0, 0, display.width, display.height);
        expect(
          unrotateCrop(full, image, turns),
          const Rect.fromLTRB(0, 0, 200, 100),
          reason: 'turn $turns should select the entire source',
        );
      }
    });

    test('turn 1 maps the display top-left corner to the image bottom-left', () {
      // At 90° CW the display is 100x200. Its top-left 100x50 block is the
      // image's bottom-left: image x in [0,50], image y in [0,100] reversed.
      const crop = Rect.fromLTRB(0, 0, 100, 50);
      expect(unrotateCrop(crop, image, 1), const Rect.fromLTRB(0, 0, 50, 100));
    });

    test('turn 1 maps an asymmetric rect where hand-computation says', () {
      // display (L,T,R,B) -> image (T, h-R, B, h-L), h = 100.
      const crop = Rect.fromLTRB(20, 30, 70, 160);
      expect(
        unrotateCrop(crop, image, 1),
        const Rect.fromLTRB(30, 30, 160, 80),
      );
    });

    test('turn 2 point-reflects the rect', () {
      const crop = Rect.fromLTRB(20, 30, 70, 80);
      expect(
        unrotateCrop(crop, image, 2),
        const Rect.fromLTRB(130, 20, 180, 70),
      );
    });

    test('turn 3 maps an asymmetric rect where hand-computation says', () {
      // display (L,T,R,B) -> image (w-B, L, w-T, R), w = 200.
      const crop = Rect.fromLTRB(20, 30, 70, 160);
      expect(
        unrotateCrop(crop, image, 3),
        const Rect.fromLTRB(40, 20, 170, 70),
      );
    });

    test('every turn preserves area', () {
      const crop = Rect.fromLTRB(20, 30, 70, 90);
      for (var turns = 0; turns < 4; turns++) {
        final out = unrotateCrop(crop, image, turns);
        expect(
          out.width * out.height,
          closeTo(crop.width * crop.height, 0.001),
          reason: 'turn $turns changed the selected area',
        );
      }
    });

    test('turns wrap modulo 4', () {
      const crop = Rect.fromLTRB(20, 30, 70, 90);
      expect(unrotateCrop(crop, image, 4), unrotateCrop(crop, image, 0));
      expect(unrotateCrop(crop, image, 5), unrotateCrop(crop, image, 1));
    });
  });
}
