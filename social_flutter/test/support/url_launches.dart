// test/support/url_launches.dart — every link the app hands url_launcher, and
// how it asked for it to open.
//
// No platform plugin registers under test, so url_launcher falls back to its
// method channel; answering that channel here opens nothing and keeps each link,
// which turns "Google Maps gets this route" into an exact assertion.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('plugins.flutter.io/url_launcher');

/// One link handed to url_launcher.
typedef UrlLaunch = ({
  Uri url,
  // In an in-app browser view, rather than handed to the app that claims it.
  bool inApp,
  // Only by an app that claims it, with no browser to fall back to.
  bool appOnly,
});

/// Answers every launch until the test ends, opening nothing, and keeps it.
List<UrlLaunch> recordUrlLaunches() {
  final launches = <UrlLaunch>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    if (call.method == 'launch') {
      final args = call.arguments as Map<Object?, Object?>;
      launches.add((
        url: Uri.parse(args['url']! as String),
        inApp: args['useWebView'] == true || args['useSafariVC'] == true,
        appOnly: args['universalLinksOnly'] == true,
      ));
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  return launches;
}
