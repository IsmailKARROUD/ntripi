// On iOS an FCM token is minted from Apple's APNs device token, which arrives
// asynchronously after launch. getToken() asked first throws
// `apns-token-not-set`, and every caller used to catch that and quietly give
// up — an iPhone that raced Apple never registered and never got a push.
// _fetchToken waits for APNs; this keeps every getToken() going through it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/push/push_service.dart';

void main() {
  group('waitForApnsToken', () {
    test('answers at once when APNs has already delivered', () async {
      var reads = 0;
      final ok = await waitForApnsToken(() async {
        reads++;
        return 'apns';
      });
      expect(ok, isTrue);
      expect(reads, 1);
    });

    test('keeps asking until a late APNs token arrives', () async {
      var reads = 0;
      final ok = await waitForApnsToken(
        () async => ++reads < 4 ? null : 'apns',
        timeout: const Duration(seconds: 1),
        interval: const Duration(milliseconds: 1),
      );
      expect(ok, isTrue);
      expect(reads, 4);
    });

    test('gives up once the timeout has elapsed', () async {
      var reads = 0;
      final ok = await waitForApnsToken(
        () async {
          reads++;
          return null;
        },
        timeout: const Duration(milliseconds: 5),
        interval: const Duration(milliseconds: 1),
      );
      expect(ok, isFalse);
      // One read per interval up to the timeout, plus the one at zero.
      expect(reads, 6);
    });
  });

  test('getToken() is called only from _fetchToken', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      final calls = RegExp(r'\.getToken\(').allMatches(source).length;
      // _fetchToken's own call is the one allowed.
      final allowed =
          file.path.endsWith('lib/core/push/push_service.dart') ? 1 : 0;
      if (calls != allowed) offenders.add('${file.path}: $calls');
    }
    expect(offenders, isEmpty,
        reason: 'On iOS a bare getToken() throws apns-token-not-set until '
            'Apple has delivered the APNs token. Go through _fetchToken, '
            'which waits for it.');
  });
}
