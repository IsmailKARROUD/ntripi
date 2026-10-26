// test/services/share_service_test.dart
//
// A Share button hands out one link two ways: to another app with its caption,
// and — from the share popup's added Copy link row — alone. The row itself is
// native (MainActivity.kt, AppDelegate.swift); what it is given, and what the
// app says after it, is decided on this side of the channel.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/share_service.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/share_link_action.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/trip_json.dart';

const _shareChannel = MethodChannel('ntripi/share');
// share_plus's own, which a build without ours falls back to.
const _sharePlusChannel = MethodChannel('dev.fluttercommunity.plus/share');

final _l10n = lookupAppLocalizations(const Locale('en'));

Itinerary _trip() => Itinerary.fromJson(tripJson(
      title: 'Coast walk',
      totalDurationMin: 180,
      tracks: [
        trackJson('t1', [stopJson('s1'), stopJson('s2', placeName: 'Cliffs')]),
      ],
    ));

/// Answers [channel] with [answer] and keeps every call it gets.
List<MethodCall> _answer(MethodChannel channel, Object? answer) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return answer;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('What a Share button hands out', () {
    test('a trip: the link, and for other apps the caption above it', () {
      final link = ShareService().itineraryLink(_trip(), _l10n);

      expect(link.url, shareUrlFor(kTripId));
      expect(link.subject, 'Coast walk');
      expect(link.caption, contains('Coast walk'));
      expect(link.caption, contains(_l10n.stopCount(2)));
      expect(link.caption, isNot(contains(link.url)));
      expect(link.text, '${link.caption}\n${link.url}');
    });

    test('a profile: the link by handle, and its caption', () {
      final user = User.fromJson({
        'id': 'u1',
        'username': 'aminad',
        'display_name': 'Amina',
        'followers_count': 0,
        'following_count': 0,
        'is_private': false,
        'created_at': '2026-10-01T00:00:00Z',
      });
      final link = ShareService().profileLink(user, _l10n);

      expect(link.url, profileShareUrlFor('aminad'));
      expect(link.caption, _l10n.shareProfileCaption('Amina'));
      expect(link.text, '${link.caption}\n${link.url}');
    });
  });

  group('The share popup with a Copy link row', () {
    const link = ShareLink(
      url: 'https://ntripi.app/share/i/abc',
      caption: 'Check out "Coast walk" on Ntripi',
      subject: 'Coast walk',
    );

    test('other apps get the caption and the link; the row, the link alone',
        () async {
      final calls = _answer(_shareChannel, null);

      final copied = await ShareService().shareWithCopyLink(
        link,
        copyLinkLabel: 'Copy link',
        copiedLabel: 'Link copied',
        origin: const Rect.fromLTWH(300, 40, 40, 40),
      );

      expect(copied, isFalse);
      expect(calls.single.method, 'share');
      expect(calls.single.arguments, {
        'text': link.text,
        'url': link.url,
        'subject': 'Coast walk',
        'copyLinkLabel': 'Copy link',
        'copiedLabel': 'Link copied',
        // What an iPad's popup points at: the button that was tapped.
        'origin': [300.0, 40.0, 40.0, 40.0],
      });
    });

    test('the row picked on an iPhone is reported, for the app to say so',
        () async {
      _answer(_shareChannel, 'copiedLink');

      final copied = await ShareService().shareWithCopyLink(
        link,
        copyLinkLabel: 'Copy link',
        copiedLabel: 'Link copied',
      );

      expect(copied, isTrue);
    });

    test('a build without the channel still shares — without the row',
        () async {
      final calls = _answer(_sharePlusChannel, 'dev.fluttercommunity.plus/share/unavailable');

      final copied = await ShareService().shareWithCopyLink(
        link,
        copyLinkLabel: 'Copy link',
        copiedLabel: 'Link copied',
      );

      expect(copied, isFalse);
      expect(calls.single.arguments['text'], link.text);
      expect(calls.single.arguments['subject'], 'Coast walk');
    });

    test('Copy link puts the link, and nothing else, on the clipboard',
        () async {
      final calls = _answer(SystemChannels.platform, null);

      await ShareService().copyLink(link);

      final set = calls.singleWhere((c) => c.method == 'Clipboard.setData');
      expect(set.arguments, {'text': link.url});
    });
  });

  group('What the app says after it', () {
    const link = ShareLink(
      url: 'https://ntripi.app/share/i/abc',
      caption: 'Check out "Coast walk" on Ntripi',
      subject: 'Coast walk',
    );

    Future<void> pumpShareButton(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Consumer(
                builder: (_, ref, _) => Builder(
                  builder: (button) => TextButton(
                    onPressed: () => shareLink(button, ref, link),
                    child: const Text('Share'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets(
        'Given the Copy link row picked, When the popup closes, '
        'Then "Link copied" shows', (tester) async {
      final calls = _answer(_shareChannel, 'copiedLink');
      await pumpShareButton(tester);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.shareLinkCopied), findsOneWidget);
      final args = calls.single.arguments as Map;
      expect(args['copyLinkLabel'], _l10n.shareCopyLink);
      // The popup points at the button: its box, in global coordinates.
      final box = tester.getRect(find.byType(TextButton));
      expect(args['origin'], [box.left, box.top, box.width, box.height]);
    });

    testWidgets(
        'Given another app picked, When the popup closes, '
        'Then the app says nothing', (tester) async {
      _answer(_shareChannel, null);
      await pumpShareButton(tester);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
