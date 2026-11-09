// Every field whose text the server stores is held to the server's rules
// before Save — its cap, and no link where none is allowed — through one
// mechanism, shared/widgets/text_rules.dart (2026-11-08 and 2026-11-09). A
// field outside it gets the server's 422 instead, and until 2026-11-09 some
// cut what was typed at their own cap (a `maxLength`), saving a shortened text
// without a word.
//
// This holds it for code nobody has written yet, file by file: a file in lib/
// that draws a text field names its rules — a RuledField, a validator calling
// textRuleBreak, or the cap read from TextLimits — or is listed below with the
// reason its fields store nothing a cap applies to. A second, unruled field in
// a file that already names its rules is past what this can see.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files whose text fields send nothing the server stores as user text.
const _storesNoText = {
  // A typed confirmation, compared on the device and never sent.
  'lib/core/ui/destructive_actions.dart',
  // An email address, held by the email validator; nothing is stored.
  'lib/features/auth/presentation/forgot_password_screen.dart',
  // An email address and a password, checked by their validators.
  'lib/features/auth/presentation/login_screen.dart',
  // A username search for whom to grant edit rights.
  'lib/features/itineraries/presentation/editors_screen.dart',
  // An OpenStreetMap search to place the pin; only coordinates are saved.
  'lib/features/itineraries/presentation/map_picker_screen.dart',
  // A filter over the saved list, on the device.
  'lib/features/itineraries/presentation/saved_itineraries_screen.dart',
  // A username search for the allowlist.
  'lib/features/itineraries/presentation/visibility_screen.dart',
  // The editor itself: each screen that uses it names the RuledField.
  'lib/features/itineraries/presentation/widgets/markdown_notes_editor.dart',
  // Passwords, held to bcrypt's 72 bytes — under the server's 128 cap.
  'lib/features/profile/presentation/change_password_screen.dart',
  // A filter over the country list, on the device.
  'lib/features/profile/presentation/country_picker_screen.dart',
  // The password that confirms a deletion; nothing is stored.
  'lib/features/profile/presentation/delete_account_screen.dart',
  // A filter over the language list, on the device.
  'lib/features/profile/presentation/language_picker_sheet.dart',
  // A search for trips and people; nothing is stored.
  'lib/features/search/presentation/search_screen.dart',
};

final _field = RegExp(r'\b(TextField|TextFormField)\(');
final _rules = RegExp(r'\bRuledField\(|\btextRuleBreak\(|\bTextLimits\.');

void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.startsWith('lib/l10n/'))
      .toList();

  test('every file with a text field names its rules, or is listed', () {
    final unruled = <String>[
      for (final file in dartFiles)
        if (_field.hasMatch(file.readAsStringSync()) &&
            !_rules.hasMatch(file.readAsStringSync()) &&
            !_storesNoText.contains(file.path))
          file.path,
    ];
    expect(unruled, isEmpty,
        reason: 'hold each field to the server\'s rules with a RuledField '
            '(shared/widgets/text_rules.dart) and its TextLimits cap, or list '
            'the file in _storesNoText with the reason it stores no text');
  });

  test('every listed file still exists and still has a text field', () {
    for (final path in _storesNoText) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is gone — unlist it');
      expect(_field.hasMatch(file.readAsStringSync()), isTrue,
          reason: '$path has no text field any more — unlist it');
    }
  });

  test('no text field cuts what is typed at a cap (maxLength)', () {
    // A cap is shown and held back by TextRulesNote / TextRulesGate; a
    // maxLength would silently cut a paste instead.
    final cutting = <String>[
      for (final file in dartFiles)
        if (RegExp(r'\bmaxLength:\s*\d').hasMatch(file.readAsStringSync()) ||
            file.readAsStringSync().contains('LengthLimitingTextInputFormatter'))
          file.path,
    ];
    expect(cutting, isEmpty);
  });
}
