// Every picture the app picks goes through pickImageToCrop
// (lib/core/media/image_pick.dart), which reads the file's format from its
// first bytes and names an unsupported one before anything loads — the NSFW
// model or the crop editor. Before it, each picker read the gallery itself and
// a HEIC in a browser loaded for seconds before failing (2026-11-07).
//
// This holds it for code nobody has written yet: no other file in lib/ may
// import image_picker.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _helper = 'lib/core/media/image_pick.dart';

void main() {
  test('only $_helper imports image_picker', () {
    final importers = {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (file.readAsLinesSync().any((line) =>
            line.trimLeft().startsWith('import') &&
            line.contains('package:image_picker')))
          file.path,
    };
    expect(importers, {_helper},
        reason: 'pick a picture with pickImageToCrop, never ImagePicker '
            'directly: it is what names an unsupported format at once.');
  });
}
