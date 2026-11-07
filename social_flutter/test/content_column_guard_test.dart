// One width rule on every device — and this keeps it true for screens nobody
// has written yet.
//
// A screen's width used to be decided by the platform: `isDesktopWeb()` capped
// content at 480 px in a desktop browser and nowhere else, so an iPad stretched
// every screen edge to edge, and nine screens had no cap at all. Width decides
// now (core/ui/app_layout.dart): every screen puts its content, or its whole
// page, in the 600 px column through ContentColumn / ContentPage /
// SliverContentColumn (shared/widgets/content_column.dart). A screen that must
// fill the window may — but only with a stated reason, here.
//
// The column centres on the window, and so must a sheet: one opened on a tab's
// own navigator is laid out in the tab, which beside the side bar is not
// centred on the window. Every sheet opens on the root navigator.
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

/// The argument list of every `showModalBottomSheet` call in [source], with
/// string literals blanked so a bracket in a label cannot unbalance the scan.
/// A type argument may be a record, brackets and all, so it is skipped by its
/// own angle brackets.
Iterable<String> _sheetCalls(String source, String file) sync* {
  final code = source.replaceAll(
      RegExp(r"'(?:[^'\\\n]|\\.)*'" r'|"(?:[^"\\\n]|\\.)*"'), "''");
  for (final name in RegExp(r'\bshowModalBottomSheet\b').allMatches(code)) {
    var i = name.end;
    if (i < code.length && code[i] == '<') {
      for (var angles = 0; i < code.length; i++) {
        if (code[i] == '<') angles++;
        if (code[i] == '>' && --angles == 0) break;
      }
      i++;
    }
    if (i >= code.length || code[i] != '(') continue; // named, not called
    var depth = 0;
    int? end;
    for (var j = i; j < code.length && end == null; j++) {
      if ('([{'.contains(code[j])) depth++;
      if (')]}'.contains(code[j]) && --depth == 0) end = j;
    }
    // Skipping a call the scan cannot read would let it through unchecked.
    if (end == null) {
      throw StateError('$file: a showModalBottomSheet( call never closes');
    }
    yield code.substring(i + 1, end);
  }
}

/// The named arguments of [args] at its own level, not inside a nested call.
Map<String, String> _namedArguments(String args) {
  final named = <String, String>{};
  var depth = 0;
  var start = 0;
  for (var i = 0; i <= args.length; i++) {
    final c = i < args.length ? args[i] : ',';
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      final argument = RegExp(r'^\s*(\w+)\s*:\s*([\s\S]*?)\s*$')
          .firstMatch(args.substring(start, i));
      if (argument != null) named[argument[1]!] = argument[2]!;
      start = i + 1;
    }
  }
  return named;
}

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
        if (!RegExp(r'\b(?:Sliver)?Content(?:Column|Page)\(')
            .hasMatch(sources[file]!))
          file,
    };
    expect(live.difference(_mayFillWindow), isEmpty,
        reason: 'Put the content in ContentColumn — or the whole page in '
            'ContentPage when an AppBar or a floating button sits in the '
            "Scaffold's own slots, or each sliver in SliverContentColumn when "
            'something in the scroll view may be wider — or add the file to '
            '_mayFillWindow with the reason it must fill the window.');
    expect(_mayFillWindow.difference(live), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('every sheet opens on the root navigator, centred on the window', () {
    final calls = <String>[];
    final offTheRoot = <String>[];
    for (final MapEntry(key: file, value: source) in sources.entries) {
      for (final args in _sheetCalls(source, file)) {
        calls.add(file);
        if (_namedArguments(args)['useRootNavigator'] != 'true') {
          offTheRoot.add(file);
        }
      }
    }
    expect(calls, isNotEmpty,
        reason: 'The scan found no sheet at all, so it checked nothing — it '
            'is the scan that broke, not the sheets.');
    expect(offTheRoot, isEmpty,
        reason: 'Pass useRootNavigator: true. On a tab\'s own navigator the '
            'sheet is laid out in the tab — beside the side bar not centred '
            'on the window — and the bar below stays tappable under it.');
  });
}
