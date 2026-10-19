// test/widgets/parked_link_notice_test.dart
//
// A share page's "See the full trip" lands a signed-out visitor on the sign-in
// screen with the link parked. A bare form would not say what it is for, so
// both sign-in screens carry ParkedLinkNotice — and it follows the parked link
// live: a link tapped while the screen is open shows it, and the sign-in that
// takes the link clears it.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/router/app_links.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/auth/data/auth_repository.dart';
import 'package:ntripi/features/auth/presentation/login_screen.dart';
import 'package:ntripi/features/auth/presentation/register_screen.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';

const _trip = '/itineraries/3fa85f64-5717-4562-b3fc-2c963f66afa6';
const _tripLine =
    'Sign in or create a free account to open the trip you were sent.';
const _profileLine =
    'Sign in or create a free account to open the profile you were sent.';

/// Serves the documents the register screen fetches on build; nothing else
/// is called before a submit.
class _QuietAuthRepository extends AuthRepository {
  _QuietAuthRepository() : super(Dio(), Dio());

  @override
  Future<Map<String, dynamic>> fetchTos({String? lang}) async => {
        'version': '3.0',
        'summary': 'Terms',
        'guidelines': 'Guidelines',
        'privacy': 'Privacy',
        'notice_terms': '',
        'notice_guidelines': '',
        'notice_privacy': '',
      };
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  FlutterSecureStorage.setMockInitialValues({});

  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_QuietAuthRepository()),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  await tester.pump();
}

void main() {
  tearDown(takeParkedAppLink);

  group('parkedLinkKind', () {
    test('reads every location appLinkLocation can answer', () {
      expect(parkedLinkKind(_trip), ParkedLinkKind.trip);
      expect(parkedLinkKind('/unavailable/trip'), ParkedLinkKind.trip);
      expect(parkedLinkKind('/u/wanderer'), ParkedLinkKind.profile);
      expect(parkedLinkKind('/unavailable/profile'), ParkedLinkKind.profile);
      expect(parkedLinkKind(null), isNull);
      expect(parkedLinkKind('/notifications'), isNull);
    });
  });

  group('Sign-in screen', () {
    testWidgets(
        'Given no parked link, When the screen opens, '
        'Then it says nothing about one', (tester) async {
      await _pump(tester, const LoginScreen());

      expect(find.text(_tripLine), findsNothing);
      expect(find.text(_profileLine), findsNothing);
    });

    testWidgets(
        'Given a parked trip link, When the screen opens, '
        'Then it says a trip is waiting', (tester) async {
      parkAppLink(_trip);
      await _pump(tester, const LoginScreen());

      expect(find.text(_tripLine), findsOneWidget);
    });

    testWidgets(
        'Given a parked profile link, When the screen opens, '
        'Then it says a profile is waiting', (tester) async {
      parkAppLink('/u/wanderer');
      await _pump(tester, const LoginScreen());

      expect(find.text(_profileLine), findsOneWidget);
    });

    testWidgets(
        'Given the screen is open, When a link is parked and then taken, '
        'Then the line comes and goes with it', (tester) async {
      await _pump(tester, const LoginScreen());

      parkAppLink(_trip);
      await tester.pump();
      expect(find.text(_tripLine), findsOneWidget);

      takeParkedAppLink();
      await tester.pump();
      expect(find.text(_tripLine), findsNothing);
    });
  });

  group('Sign-up screen', () {
    testWidgets(
        'Given a parked trip link, When the screen opens, '
        'Then it says a trip is waiting too', (tester) async {
      parkAppLink(_trip);
      await _pump(tester, const RegisterScreen());

      expect(find.text(_tripLine), findsOneWidget);
    });
  });
}
