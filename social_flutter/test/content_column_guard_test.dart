// One width rule on every device — and this keeps it true for screens nobody
// has written yet.
//
// A screen's width used to be decided by the platform: `isDesktopWeb()` capped
// content at 480 px in a desktop browser and nowhere else, so an iPad stretched
// every screen edge to edge, and nine screens had no cap at all. Width decides
// now (core/ui/app_layout.dart): every screen puts its content, or its whole
// page, in the 600 px column through ContentColumn / ContentPage
// (shared/widgets/content_column.dart). A screen that must fill the window
// may — but only with a stated reason, here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files with a Scaffold that fills the window on purpose.
const _mayFillWindow = {
  // The brand flash before the first screen.
  'lib/features/auth/presentation/splash_screen.dart',
  // Centres its own 420 px box, narrower than the column.
  'lib/features/auth/presentation/suspended_screen.dart',
  // A live map to pick a point on.
  'lib/features/itineraries/presentation/map_picker_screen.dart',
  // The crop editor: its frame's geometry is the crop math.
  'lib/features/itineraries/presentation/widgets/cover_image_field.dart',
  // A map of every place a profile has been.
  'lib/features/profile/presentation/fullscreen_locations_map_screen.dart',
  // A photo, as large as the window allows.
  'lib/shared/widgets/fullscreen_image_viewer.dart',
};

/// [source] without its comments. String literals are matched first and kept,
/// so the `//` of a URL in a string does not swallow the rest of its line.
String _withoutComments(String source) => source.replaceAllMapped(
      RegExp(r"""'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|/\*[\s\S]*?\*/|//[^\n]*"""),
      (m) => m[0]!.startsWith('/') ? '' : m[0]!,
    );

/// Every Dart file under lib/, comments removed — the commented-out
/// segment_form_screen.dart included, which is no screen at all.
Map<String, String> _sources() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: _withoutComments(file.readAsStringSync()),
    };

void main() {
  final sources = _sources();

  test('no screen sizes itself by platform', () {
    final live = {
      for (final entry in sources.entries)
        if (RegExp(r'\bisDesktopWeb\b|\bkDesktopMaxWidth\b')
            .hasMatch(entry.value))
          entry.key,
    };
    expect(live, isEmpty,
        reason: 'A desktop-only cap left every tablet stretched edge to edge. '
            'Width decides: wrap the content in ContentColumn, or the whole '
            'page in ContentPage.');
  });

  test('every Scaffold sits in the column, or says why it fills the window',
      () {
    final scaffolds = {
      for (final entry in sources.entries)
        if (RegExp(r'\bScaffold\(').hasMatch(entry.value)) entry.key,
    };
    expect(scaffolds, isNotEmpty,
        reason: 'The scan found no Scaffold at all, so it checked nothing — '
            'it is the scan that broke, not the screens.');

    final live = {
      for (final file in scaffolds)
        if (!RegExp(r'\bContent(Column|Page)\(').hasMatch(sources[file]!))
          file,
    };
    expect(live.difference(_mayFillWindow), isEmpty,
        reason: 'Put the content in ContentColumn — or the whole page in '
            'ContentPage when an AppBar or a floating button sits in the '
            "Scaffold's own slots — or add the file to _mayFillWindow with the "
            'reason it must fill the window.');
    expect(_mayFillWindow.difference(live), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });
}
