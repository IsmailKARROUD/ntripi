// test/core/storage/web_session_hint_test.dart
//
// On the web the share pages read one localStorage entry the app keeps while
// somebody is signed in (web_session_hint.dart), and send that reader straight
// into the web app. It must follow the session exactly: written whenever the
// tokens are, gone whenever they are — or a signed-out reader is sent to a
// sign-in they did not ask for, and a signed-in one sees the teaser again.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/storage/secure_storage.dart';
import 'package:ntripi/core/storage/web_session_hint.dart';

class _RecordingHint implements WebSessionHint {
  final calls = <String>[];

  @override
  void mark(DateTime? until) => calls.add('mark ${until?.toUtc()}');

  @override
  void clear() => calls.add('clear');
}

void main() {
  late WebSessionHint original;
  late _RecordingHint hint;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    original = webSessionHint;
    hint = _RecordingHint();
    webSessionHint = hint;
  });
  tearDown(() => webSessionHint = original);

  test('the key is the one the share pages read', () {
    // social_api app/services/app_links.py WEB_SESSION_HINT_KEY.
    expect(kWebSessionHintKey, 'ntripi_web_session_until');
  });

  test('every token save says until when somebody is signed in', () async {
    final until = DateTime.utc(2026, 11, 25, 9);

    await saveTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      refreshExpiresAt: until,
    );

    expect(hint.calls, ['mark $until']);
  });

  test('every way a session ends takes the hint with it', () async {
    await clearAllTokens();

    expect(hint.calls, ['clear']);
  });

  test('at launch, a session from before the hint gets one', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ntripi_refresh_token': 'refresh',
      'ntripi_refresh_expires_at': '2100-01-01T00:00:00.000Z',
    });

    await syncWebSessionHint();

    expect(hint.calls, ['mark ${DateTime.utc(2100)}']);
  });

  test('at launch, no live session leaves no hint behind', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ntripi_refresh_token': 'refresh',
      'ntripi_refresh_expires_at': '2000-01-01T00:00:00.000Z',
    });

    await syncWebSessionHint();

    expect(hint.calls, ['clear']);
  });
}
