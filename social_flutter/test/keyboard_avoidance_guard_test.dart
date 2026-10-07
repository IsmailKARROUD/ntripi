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

/// Every Dart file under lib/, comments removed — a mention in prose (or the
/// commented-out segment_form_screen.dart) is not a use.
Map<String, String> _sources() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: file
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//[^\n]*'), ''),
    };

Set<String> _matching(Map<String, String> sources, RegExp pattern) => {
      for (final entry in sources.entries)
        if (pattern.hasMatch(entry.value)) entry.key,
    };

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
}
