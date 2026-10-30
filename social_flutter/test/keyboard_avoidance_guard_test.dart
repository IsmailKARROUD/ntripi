// Keyboard avoidance has one owner per surface — and this keeps it true for
// code nobody has written yet.
//
// The shell consumes the keyboard inset for its tabs, screens keep the default
// `resizeToAvoidBottomInset`, and sheets lift through AboveKeyboard /
// KeyboardSafeSheetBody (lib/shared/widgets/keyboard_avoidance.dart). Two
// one-line habits undid that before: `resizeToAvoidBottomInset: false` added to
// "fix a gap" (eighteen of them hid a leak in the shell, then left every
// root-navigator screen with no avoidance at all), and keyboard padding written
// inline inside a scroll view, where a height cap silently cancels it. Either
// may still be right somewhere — but only with a stated reason, here.
//
// A third habit hid the buttons: every KeyboardSafeSheetBody sheet ended its
// scrolling body with its button row, so Submit sat under the keyboard while a
// field was in use, and below the fold once the body outgrew the cap. Buttons
// go in `actions:`, pinned below the scroll view.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pages that must not reflow while the keyboard rises.
const _mayNotResize = {
  // Relayouting the live map every keyboard frame froze the device.
  'lib/features/itineraries/presentation/map_picker_screen.dart',
  // The crop frame's geometry is the crop math.
  'lib/features/itineraries/presentation/widgets/cover_image_field.dart',
};

/// Files that read the keyboard inset themselves.
const _mayReadInset = {
  // The primitives everything else goes through.
  'lib/shared/widgets/keyboard_avoidance.dart',
  // A page that never resizes, bounding its own search overlay.
  'lib/features/itineraries/presentation/map_picker_screen.dart',
  // A popover placed in the full-window overlay, outside any Scaffold.
  'lib/shared/widgets/field_help.dart',
};

/// [source] without its comments. String literals are matched first and kept,
/// so the `//` of a URL in a string does not swallow the rest of its line.
String _withoutComments(String source) => source.replaceAllMapped(
      RegExp(r"""'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|/\*[\s\S]*?\*/|//[^\n]*"""),
      (m) => m[0]!.startsWith('/') ? '' : m[0]!,
    );

/// Every Dart file under lib/, comments removed — a mention in prose (or the
/// commented-out segment_form_screen.dart) is not a use.
Map<String, String> _sources() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: _withoutComments(file.readAsStringSync()),
    };

/// Where KeyboardSafeSheetBody is declared — its constructor is not a call.
const _sheetBodyDefinition = 'lib/shared/widgets/keyboard_avoidance.dart';

/// Sheets with a field and no buttons to pin, each with its reason.
const _mayOmitActions = <String>{};

Set<String> _matching(Map<String, String> sources, RegExp pattern) => {
      for (final entry in sources.entries)
        if (pattern.hasMatch(entry.value)) entry.key,
    };

/// The argument list of every `KeyboardSafeSheetBody(` call in [source], with
/// string literals blanked so a bracket in a label cannot unbalance the scan.
Iterable<String> _sheetBodyCalls(String source, [String file = 'source']) sync* {
  final code = source.replaceAll(
      RegExp(r"'(?:[^'\\\n]|\\.)*'" r'|"(?:[^"\\\n]|\\.)*"'), "''");
  for (final call in RegExp(r'\bKeyboardSafeSheetBody\(').allMatches(code)) {
    var depth = 0;
    int? end;
    for (var i = call.end - 1; i < code.length && end == null; i++) {
      if ('([{'.contains(code[i])) depth++;
      if (')]}'.contains(code[i]) && --depth == 0) end = i;
    }
    // Skipping a call the scan cannot read would let it through unchecked.
    if (end == null) {
      throw StateError('$file: a KeyboardSafeSheetBody( call never closes');
    }
    yield code.substring(call.end, end);
  }
}

/// The named arguments of [args] at its own level, not inside a nested call.
Set<String> _argumentNames(String args) {
  final names = <String>{};
  var depth = 0;
  var start = 0;
  for (var i = 0; i <= args.length; i++) {
    final c = i < args.length ? args[i] : ',';
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      final name =
          RegExp(r'^\s*(\w+)\s*:').firstMatch(args.substring(start, i));
      if (name != null) names.add(name.group(1)!);
      start = i + 1;
    }
  }
  return names;
}

void main() {
  final sources = _sources();

  test('resizeToAvoidBottomInset: false only where a page must not reflow', () {
    final live =
        _matching(sources, RegExp(r'resizeToAvoidBottomInset\s*:\s*false'));
    expect(live.difference(_mayNotResize), isEmpty,
        reason: 'The shell already lifts its tabs, and on the root navigator '
            'nothing else will: `false` there leaves the keyboard over the '
            'screen. Keep the default, or add the file to _mayNotResize with '
            'the reason the page must not reflow.');
    expect(_mayNotResize.difference(live), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('the keyboard inset is read only through the primitives', () {
    final live =
        _matching(sources, RegExp(r'\bviewInsets\b|\bviewInsetsOf\('));
    expect(live.difference(_mayReadInset), isEmpty,
        reason: 'Lift a sheet with KeyboardSafeSheetBody or AboveKeyboard: '
            'inset padding inside a scroll view is cancelled by a height cap, '
            'and inside a tab the inset reads 0. Or add the file to '
            '_mayReadInset with its reason.');
    expect(_mayReadInset.difference(live), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('a KeyboardSafeSheetBody pins its buttons in actions:', () {
    final calls = {
      for (final entry in sources.entries)
        if (entry.key != _sheetBodyDefinition)
          entry.key: _sheetBodyCalls(entry.value, entry.key).toList(),
    }..removeWhere((_, found) => found.isEmpty);
    expect(calls, isNotEmpty,
        reason: 'The scan found no KeyboardSafeSheetBody call at all, so it '
            'checked nothing — it is the scan that broke, not the sheets.');

    final live = {
      for (final entry in calls.entries)
        if (entry.value
            .any((args) => !_argumentNames(args).contains('actions')))
          entry.key,
    };
    expect(live.difference(_mayOmitActions), isEmpty,
        reason: 'A button inside the scroll view sits under the keyboard while '
            'a field is in use, and below the fold once the body outgrows the '
            'cap. Pass the buttons as `actions: SheetActionBar(...)`, or add '
            'the file to _mayOmitActions with the reason it has none.');
    expect(_mayOmitActions.difference(live), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('the scan reads each call by its own arguments', () {
    const source = '''
      // KeyboardSafeSheetBody(child: commentedOut),
      KeyboardSafeSheetBody(
        child: Text('a ( stray bracket, and https://a.link'), // a ( comment
        actions: SheetActionBar(child: send),
      );
      KeyboardSafeSheetBody(
        child: Column(children: [Inner(actions: notTheSheets)]),
      );
    ''';
    expect(_sheetBodyCalls(_withoutComments(source)).map(_argumentNames), [
      {'child', 'actions'},
      {'child'},
    ]);
  });

  test('the scan refuses a call it cannot read instead of skipping it', () {
    expect(() => _sheetBodyCalls('KeyboardSafeSheetBody(child: x').toList(),
        throwsStateError);
  });
}
