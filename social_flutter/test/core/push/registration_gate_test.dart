// Sign-out deletes this device's push registration, and a registration can be
// waiting seconds on APNs when it does. RegistrationGate keeps the two from
// crossing: a POST that lands after the DELETE re-creates the row, and the next
// person on the phone receives this user's notifications.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/push/push_service.dart';

/// A Dart source file with its comments removed — a mention is not a use.
String _code(File file) => file
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('RegistrationGate', () {
    test('sends while the session is current', () async {
      final gate = RegistrationGate();
      var sent = 0;
      expect(await gate.post(gate.session, () async => sent++), isTrue);
      expect(sent, 1);
    });

    test('refuses a registration that began before sign-out', () async {
      final gate = RegistrationGate();
      // Read at the start of a registration, which then waited on APNs.
      final session = gate.session;
      await gate.endSession();
      var sent = 0;
      expect(await gate.post(session, () async => sent++), isFalse);
      expect(sent, 0);
    });

    test('sign-out waits for every registration already on the wire',
        () async {
      final gate = RegistrationGate();
      final first = Completer<void>();
      final second = Completer<void>();
      final posts = [
        gate.post(gate.session, () => first.future),
        gate.post(gate.session, () => second.future),
      ];
      var ended = false;
      final ending = gate.endSession().then((_) => ended = true);

      // The later one first: tracking only the latest request would pass here.
      second.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(ended, isFalse, reason: 'the first POST is still in flight');

      first.complete();
      await ending;
      // Both landed after sign-out began, so neither counts as registered.
      expect(await Future.wait(posts), [false, false]);
    });

    test('a failed registration rethrows and does not hold up sign-out',
        () async {
      final gate = RegistrationGate();
      final request = Completer<void>();
      final failed = expectLater(
        gate.post(gate.session, () => request.future),
        throwsStateError,
      );
      request.completeError(StateError('offline'));
      await failed;
      await gate.endSession();
    });
  });

  test('every POST /devices goes through the gate', () {
    final senders = [
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('lib/core/api/api_endpoints.dart')))
        for (final _ in RegExp(r'\bkDevicesEndpoint\b').allMatches(_code(file)))
          file.path,
    ];
    expect(senders, ['lib/core/push/push_service.dart'],
        reason: 'Register through _sendToken, which posts via RegistrationGate. '
            'A POST that bypasses it can land after sign-out\'s DELETE and '
            're-register the device for an account that has left it.');
  });

  test('a session start re-adopts push, as a cold start does', () {
    final source =
        _code(File('lib/features/auth/providers/auth_provider.dart'));
    final body = RegExp(r'void setAuthenticated\([^)]*\)\s*\{([\s\S]*?)\n  \}')
        .firstMatch(source)
        ?.group(1);
    expect(body, isNotNull, reason: 'setAuthenticated not found');
    expect(body, contains('readoptPushRegistration('),
        reason: 'Sign-out deletes the device row. Without re-adopting on '
            'sign-in, the next account on the phone gets no push until a '
            'cold start.');
  });
}
