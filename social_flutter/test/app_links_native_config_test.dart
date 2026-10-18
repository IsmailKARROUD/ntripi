// Which links open the app is decided in four places that cannot see each
// other: the Android intent filter, the iOS associated domain, the server's
// /.well-known files, and lib/core/router/app_links.dart. The server is a
// separate codebase (social_api test_app_links.py pins its half); this pins the
// client's three to each other and to the host the release builds share.
//
// The failure each one guards is silent. A host that differs from
// SHARE_BASE_URL claims links nobody sends; a prefix the router does not map
// opens the app on go_router's error page; and without singleTask a link tapped
// in Gmail starts a second copy of the app instead of reaching this one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/router/app_links.dart';

String _read(String path) => File(path).readAsStringSync();

/// The host of SHARE_BASE_URL in every release script — what shared links say.
Set<String> _releaseShareHosts() => {
      for (final script in const [
        'scripts/release_android.sh',
        'scripts/release_ios.sh',
      ])
        Uri.parse(RegExp(r'--dart-define=SHARE_BASE_URL=(\S+)')
                .firstMatch(_read(script))!
                .group(1)!)
            .host,
    };

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final entitlements = _read('ios/Runner/Runner.entitlements');
  final infoPlist = _read('ios/Runner/Info.plist');

  final verifiedFilter = RegExp(
    r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
    dotAll: true,
  ).firstMatch(manifest)?.group(1);
  final claimed = [
    for (final m in RegExp(
      r'android:scheme="https" android:host="([^"]+)" '
      r'android:pathPrefix="([^"]+)"',
    ).allMatches(verifiedFilter ?? ''))
      (host: m.group(1)!, prefix: m.group(2)!),
  ];

  test('both release builds share links on one host', () {
    expect(_releaseShareHosts(), hasLength(1));
  });

  test('Android verifies exactly the share links of that host', () {
    expect(verifiedFilter, isNotNull,
        reason: 'no android:autoVerify="true" intent filter');
    for (final part in const [
      'android.intent.action.VIEW',
      'android.intent.category.DEFAULT',
      'android.intent.category.BROWSABLE',
    ]) {
      expect(verifiedFilter, contains(part));
    }
    expect({for (final c in claimed) c.host}, _releaseShareHosts());
    // Share links only: emailed reset and verification links are web forms.
    expect({for (final c in claimed) c.prefix}, {'/share/i/', '/share/u/'});
  });

  test('Android hands a link to the running app, not a second copy', () {
    expect(manifest, contains('android:launchMode="singleTask"'));
    expect(manifest,
        matches(RegExp(r'flutter_deeplinking_enabled"\s+android:value="true"')));
  });

  test('iOS claims the same host', () {
    final host = _releaseShareHosts().single;
    expect(entitlements, contains('com.apple.developer.associated-domains'));
    expect(entitlements, contains('<string>applinks:$host</string>'));
    expect(infoPlist,
        matches(RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<true/>')));
  });

  test('every path the app claims opens something in it', () {
    for (final c in claimed) {
      final link = Uri.parse('https://${c.host}${c.prefix}anything');
      expect(appLinkLocation(link), isNotNull,
          reason: '${c.prefix} is claimed but app_links.dart maps nothing');
    }
  });
}
