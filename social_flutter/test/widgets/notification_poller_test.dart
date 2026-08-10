// test/widgets/notification_poller_test.dart — the polling gate.
//
// NotificationPoller wraps the entire app from MaterialApp's builder, which
// means it is mounted on the login screen, on splash, and while the app sits
// backgrounded. Almost all of its logic is about NOT asking: a timer that
// survives any of those states is a battery drain and a 401 generator that
// nobody is watching.
//
// These tests pin the gate (foregrounded, online, signed in) and the timer
// lifecycle. The cue that plays on a rise is covered by poll()'s return value
// in test/providers/notification_poll_test.dart — reaching it here would mean
// constructing a real AudioPlayer under flutter_test.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/notifications/data/notification_repository.dart';
import 'package:social_flutter/features/notifications/presentation/widgets/notification_poller.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';

class _CountingRepo extends NotificationRepository {
  _CountingRepo() : super(Dio());

  int countCalls = 0;

  @override
  Future<int> getUnreadCount({bool forceRefresh = false}) async {
    countCalls++;
    // Flat on purpose: a rise would reach into SfxService for the cue.
    return 0;
  }
}

/// Mounts the poller with nothing but a box under it — it renders its child and
/// does all its work in initState and listeners.
Future<_CountingRepo> _pumpPoller(
  WidgetTester tester, {
  required bool signedIn,
  bool online = true,
}) async {
  final repo = _CountingRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
        hasSessionProvider.overrideWith((ref) async => signedIn),
      ],
      child: const NotificationPoller(child: SizedBox()),
    ),
  );
  // Let hasSessionProvider and the connectivity stream settle, then let the
  // first poll's own await chain finish.
  await tester.pump();
  await tester.pump();
  return repo;
}

/// Unmount so the periodic Timer is cancelled — flutter_test fails a test that
/// leaves one pending, which is itself the guarantee we want from dispose().
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  group('NotificationPoller', () {
    testWidgets(
        'Given nobody is signed in, '
        'When intervals elapse, '
        'Then nothing is ever requested', (tester) async {
      final repo = await _pumpPoller(tester, signedIn: false);

      await tester.pump(kNotificationPollInterval * 3);
      await tester.pump();

      // The poller is mounted above the router, so /login and /splash sit
      // inside it. Polling there is a guaranteed 401.
      expect(repo.countCalls, 0);
      await _unmount(tester);
    });

    testWidgets(
        'Given the device is offline, '
        'When intervals elapse, '
        'Then it stops asking once connectivity has settled', (tester) async {
      final repo = await _pumpPoller(tester, signedIn: true, online: false);
      // isOnlineNow is optimistic until the connectivity stream seeds — the
      // app-wide convention, deliberately, since a sync reader cannot await it.
      // So a launch poll may slip out before the first `false` arrives; it fails
      // harmlessly inside poll(). What matters is that the ticks after it don't.
      final afterLaunch = repo.countCalls;

      await tester.pump(kNotificationPollInterval * 2);
      await tester.pump();

      expect(repo.countCalls, afterLaunch);
      await _unmount(tester);
    });

    testWidgets(
        'Given a signed-in foregrounded app, '
        'When the interval elapses, '
        'Then it polls immediately and then once per interval', (tester) async {
      final repo = await _pumpPoller(tester, signedIn: true);

      // Immediately, without waiting out an interval: the badge is most likely
      // to be wrong at exactly the moment the user is looking at it.
      expect(repo.countCalls, 1);

      await tester.pump(kNotificationPollInterval);
      await tester.pump();
      expect(repo.countCalls, 2);

      await tester.pump(kNotificationPollInterval);
      await tester.pump();
      expect(repo.countCalls, 3);

      await _unmount(tester);
    });

    testWidgets(
        'Given the app is backgrounded, '
        'When intervals elapse, '
        'Then polling stops, and resuming polls at once', (tester) async {
      final repo = await _pumpPoller(tester, signedIn: true);
      expect(repo.countCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      await tester.pump(kNotificationPollInterval * 3);
      await tester.pump();
      // The timer is cancelled, not merely ignored — a backgrounded app has no
      // badge on screen to keep honest.
      expect(repo.countCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      // Coming back is the moment the badge is most likely stale — whatever
      // arrived during the pause is waiting.
      expect(repo.countCalls, 2);

      await _unmount(tester);
    });

    testWidgets(
        'Given a resumed app, '
        'When the interval elapses after a resume, '
        'Then the interval restarts from the resume poll', (tester) async {
      final repo = await _pumpPoller(tester, signedIn: true);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repo.countCalls, 2);

      // A full interval after the resume poll, not the remainder of the one
      // that was running when the app went away.
      await tester.pump(kNotificationPollInterval - const Duration(seconds: 1));
      await tester.pump();
      expect(repo.countCalls, 2);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(repo.countCalls, 3);

      await _unmount(tester);
    });
  });
}
