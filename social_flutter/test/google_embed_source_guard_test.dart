// Every Google map in the app is a page on our own server.
//
// The Maps Embed key lives on the server (GOOGLE_MAPS_EMBED_API_KEY), which
// builds Google's URL inside /embed/* (routers/embed.py). The app only builds
// the address of that page, in one place: data/google_embed_urls.dart. Before,
// the key was a build constant typed into the Dockerfile and six scripts, and
// a phone's WebView sent Google no site to check it against.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The builder, and the WebView's navigation lock that admits its pages.
const _mayNameEmbedPages = {
  'lib/features/itineraries/data/google_embed_urls.dart',
  'lib/features/itineraries/presentation/widgets/google_map_embed.dart',
};

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test("the app never builds Google's embed URL or holds its key", () {
    for (final file in _dart('lib')) {
      final text = file.readAsStringSync();
      expect(text.contains('maps/embed/v1'), isFalse, reason: file.path);
      expect(text.contains('GOOGLE_MAPS_EMBED_API_KEY'), isFalse,
          reason: file.path);
    }
  });

  test('no build passes an Embed key any more', () {
    final builds = [
      File('../Dockerfile'),
      ...Directory('scripts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sh')),
    ];
    expect(builds, isNotEmpty);
    for (final file in builds) {
      expect(file.readAsStringSync().contains('GOOGLE_MAPS_EMBED_API_KEY'),
          isFalse, reason: file.path);
    }
  });

  test('only the builder writes the address of an /embed page', () {
    final writers = {
      for (final file in _dart('lib'))
        if (RegExp(r"""['"/]embed/""").hasMatch(file.readAsStringSync()))
          file.path,
    };
    expect(writers, _mayNameEmbedPages);
  });
}
