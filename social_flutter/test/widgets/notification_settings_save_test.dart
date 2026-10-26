// test/widgets/notification_settings_save_test.dart — a switch whose save fails
// says so and stays where it was.
//
// The switches save through MyProfileNotifier.updateProfile, which used to
// write a failed save into the profile itself: the whole settings list was
// swapped for an error message, and the screen took "still mounted" as its
// only sign of success. updateProfile now throws and leaves the profile, so a
// failed flip shows its reason in a SnackBar, the switch stays as the server
// has it, and only a save that landed is acknowledged with the toggle cue.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/services/sfx_service.dart';
import 'package:ntripi/features/notifications/presentation/notification_settings_screen.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';

import '../support/recording_dio.dart';

const _offline =
    'No internet connection. Please check your network and try again.';

Map<String, dynamic> _me({required bool notifyRatings}) => {
      'id': 'me-1',
      'username': 'me',
      'email': 'me@example.com',
      'is_private': false,
      'followers_count': 0,
      'following_count': 0,
      'created_at': '2026-01-01T00:00:00Z',
      'notify_ratings': notifyRatings,
      'notify_saves': true,
      'notify_follow_accepted': true,
    };

/// Records the cues instead of playing them.
class _RecordingSfx extends SfxService {
  _RecordingSfx(super.ref);

  final played = <Sfx>[];

  @override
  Future<void> play(Sfx sfx) async => played.add(sfx);
}

Future<_RecordingSfx> _pump(WidgetTester tester, RecordingDio api) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});

  late _RecordingSfx sfx;
  api.adapter.onGet(
      kMyProfileEndpoint, (server) => server.reply(200, _me(notifyRatings: true)));
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      profileRepositoryProvider.overrideWithValue(ProfileRepository(api.dio)),
      sfxServiceProvider.overrideWith((ref) => sfx = _RecordingSfx(ref)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NotificationSettingsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  // Read once so the recorder exists before anything plays.
  ProviderScope.containerOf(tester.element(find.byType(NotificationSettingsScreen)))
      .read(sfxServiceProvider);
  return sfx;
}

/// The Ratings switch: the first of the three.
Switch _ratings(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch).first);

void main() {
  testWidgets(
      'Given the Ratings switch on, When turning it off fails, '
      'Then the reason shows, the switch stays on, and no cue plays',
      (tester) async {
    final api = RecordingDio();
    final sfx = await _pump(tester, api);
    expect(_ratings(tester).value, isTrue);

    api.adapter.onPatch(
      kMyProfileEndpoint,
      (server) => server.throws(
        408,
        DioException(
          requestOptions: RequestOptions(path: kMyProfileEndpoint),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
      data: Matchers.any,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // The list is still here — it used to be swapped for an error message.
    expect(find.byType(Switch), findsNWidgets(3));
    expect(_ratings(tester).value, isTrue);
    expect(_ratings(tester).onChanged, isNotNull, reason: 'no longer busy');
    expect(find.text(_offline), findsOneWidget);
    expect(sfx.played, isEmpty);
  });

  testWidgets(
      'Given the Ratings switch on, When turning it off lands, '
      'Then it shows off and the toggle cue plays', (tester) async {
    final api = RecordingDio();
    final sfx = await _pump(tester, api);

    api.adapter.onPatch(kMyProfileEndpoint,
        (server) => server.reply(200, _me(notifyRatings: false)),
        data: Matchers.any);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(_ratings(tester).value, isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(sfx.played, [Sfx.toggle]);
  });
}
