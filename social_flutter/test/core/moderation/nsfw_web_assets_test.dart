// The web pre-check's vendored assets and its glue must agree, or the
// pre-check is off without a sound: the glue's load failure lands in a catch
// that keeps the upload working.
//
// Regression (2026-11-07): the glue loaded the vendored *graph* model without
// `type: 'graph'`, NSFWJS read it as a layers model and threw ("Improper config
// format"), and the web let every picture through while phones refused it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final glue = File('web/nsfw/nsfw_glue.js').readAsStringSync();
  final model = jsonDecode(File('web/nsfw/model/model.json').readAsStringSync())
      as Map<String, dynamic>;
  final load = RegExp(r"nsfwjs\.load\('([^']+)'([^)]*)\)").firstMatch(glue);

  test('the glue loads the model', () {
    expect(load, isNotNull, reason: 'no nsfwjs.load(...) call in the glue');
  });

  test('a graph model is loaded as a graph model', () {
    final asGraph = RegExp(r"type:\s*'graph'").hasMatch(load!.group(2)!);
    expect(asGraph, model['format'] == 'graph-model',
        reason: 'model.json says "${model['format']}"; NSFWJS needs '
            "{ type: 'graph' } exactly when it is a graph model");
  });

  test('every script the glue loads and every weight shard is vendored', () {
    for (final script in RegExp(r"loadScript\('([^']+)'\)").allMatches(glue)) {
      expect(File('web/${script.group(1)}').existsSync(), isTrue,
          reason: '${script.group(1)} is loaded but not in web/');
    }
    for (final group in model['weightsManifest'] as List) {
      for (final shard in (group as Map)['paths'] as List) {
        expect(File('web/${load!.group(1)}$shard').existsSync(), isTrue,
            reason: 'model.json names $shard, which is missing');
      }
    }
  });

  test('TensorFlow.js is loaded once — nsfwjs.min.js carries its own', () {
    expect(glue.contains('tf.min.js'), isFalse,
        reason: 'a second copy registers every kernel twice');
    expect(File('web/nsfw/tf.min.js').existsSync(), isFalse);
  });

  test('the glue reports every score the shared decision reads', () {
    // nsfw_precheck.dart decides on porn, hentai and sexy for both platforms.
    for (final className in ['Porn', 'Hentai', 'Sexy']) {
      expect(glue.contains("p.className === '$className'"), isTrue,
          reason: '$className is not passed to the Dart side');
    }
  });
}
