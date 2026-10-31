// The add/edit stop form never fetches a pasted Google Maps link.
//
// Fetching Google's page as the user pastes or types is scraping. The form
// reads a link only as a string (data/google_maps_links.dart); the one
// fetcher, link_preview_service.dart, serves the stop page's preview alone —
// the user kept that one. This holds the form to it for code nobody has
// written yet: no import of the fetcher, no reference to it or to the card
// that drives it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _form = 'lib/features/itineraries/presentation/stop_form_screen.dart';

/// Every way the form could reach the fetcher.
const _forbidden = [
  'link_preview_service.dart',
  'link_preview_card.dart',
  'linkPreviewProvider',
  'linkPreviewServiceProvider',
  'LinkPreviewService',
  'LinkPreviewCard',
];

void main() {
  test('the stop form never reaches the link fetcher', () {
    // Comments may name the rule; only code is held to it.
    final code = File(_form)
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    for (final name in _forbidden) {
      expect(code.contains(name), isFalse,
          reason: '$_form must not use $name: pasting a link would fetch '
              "Google's page. Read the link's text with google_maps_links.dart.");
    }
  });

  test('the fetcher is reached only from the stop page', () {
    Set<String> filesUsing(String name) => {
          for (final file in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
            if (file.readAsStringSync().contains(name)) file.path,
        };
    // Only the card watches the fetcher, and only the stop page shows it.
    expect(filesUsing('linkPreviewProvider('), {
      'lib/features/itineraries/presentation/widgets/link_preview_card.dart',
    });
    expect(filesUsing('LinkPreviewCard('), {
      'lib/features/itineraries/presentation/widgets/link_preview_card.dart',
      'lib/features/itineraries/presentation/stop_detail_screen.dart',
    });
  });
}
