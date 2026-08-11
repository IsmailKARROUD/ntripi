// features/notifications/presentation/widgets/notification_poller.dart
//
// Keeps the bell badge honest while the app is open.
//
// There is no push channel — no FCM, no APNs, no WebSocket — so the server has
// no way to tell the client anything. Without this, both notification providers
// build once per launch and a hot restart is the only way to see a new row.
//
// Polling is cheap by design rather than by luck: GET /notifications/unread-count
// returns a single integer behind an ETag with `Cache-Control: private, no-cache`,
// so an unchanged count is a 304 with an empty body. One request a minute per
// signed-in, foregrounded user is an order of magnitude under the lightest rate
// limit the backend applies anywhere else.
//
// Everything here is about NOT polling: backgrounded, offline, and signed-out
// are all silent, because a timer that survives any of those is a battery and
// 401 generator that nobody is watching.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/notifications/providers/notification_provider.dart';

/// How often the badge re-checks itself while the app is in the foreground.
///
/// The interval only bounds the *worst* case: resume, reconnect and login each
/// poll immediately, which covers the moments a stale badge is actually visible.
const kNotificationPollInterval = Duration(seconds: 60);

/// Drives the foreground badge poll. Wraps the whole app from MaterialApp's
/// builder, above the shell, so pushed root-level routes stay covered.
class NotificationPoller extends ConsumerStatefulWidget {
  final Widget child;

  const NotificationPoller({super.key, required this.child});

  @override
  ConsumerState<NotificationPoller> createState() => _NotificationPollerState();
}

class _NotificationPollerState extends ConsumerState<NotificationPoller>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    // Not skipped on web, unlike ShakeToReport: Flutter web drives this same
    // lifecycle callback from the browser's visibilitychange, so a backgrounded
    // tab stops polling and a refocused one polls at once — which is exactly
    // the behaviour wanted there, with no JS interop to write.
    WidgetsBinding.instance.addObserver(this);
    // The session is still a pending read on the first frame; the listener in
    // build() arms the timer the moment it settles.
    _sync(pollNow: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    // Coming back is the single most likely moment for the badge to be wrong —
    // poll before the user has finished looking at it.
    _sync(pollNow: resumed);
  }

  /// Start or stop the timer to match the current gate, optionally polling now.
  void _sync({bool pollNow = false}) {
    if (!_shouldPoll) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    // Recreated rather than left alone when pollNow: the next tick should be a
    // full interval after the poll that just ran, not the remainder of one.
    if (pollNow || _timer == null) {
      _timer?.cancel();
      _timer = Timer.periodic(kNotificationPollInterval, (_) => _poll());
    }
    if (pollNow) unawaited(_poll());
  }

  /// Foregrounded, signed in, and settled on both counts.
  ///
  /// `hasSessionProvider` rather than `authNotifierProvider`: splash restores a
  /// session without ever setting the notifier, so the returning users this
  /// exists for would never poll. `isLoading` is refused separately because an
  /// invalidated FutureProvider keeps serving its previous value while it
  /// reloads — after logout that value is still `true` for a frame or two.
  bool get _shouldPoll {
    if (!mounted || !_resumed) return false;
    final session = ref.read(hasSessionProvider);
    return !session.isLoading && session.value == true;
  }

  Future<void> _poll() async {
    if (!_shouldPoll) return;
    // Offline is checked inside poll() too; short-circuiting here keeps a
    // captive-portal Dio timeout from being retried once a minute forever.
    if (!isOnlineNow(ref)) return;

    final arrived =
        await ref.read(notificationBadgeProvider.notifier).poll();
    if (!mounted || !arrived) return;
    // Gated on the user's sound toggle inside SfxService, and swallowed there
    // if the platform refuses — a cue has no failure worth surfacing.
    unawaited(ref.read(sfxServiceProvider).play(Sfx.newNotification));
  }

  @override
  Widget build(BuildContext context) {
    // Logging in arms the timer; logging out disarms it. Only settled values
    // count, or the loading frame after an invalidate would toggle it twice.
    ref.listen(hasSessionProvider, (previous, next) {
      if (next.isLoading) return;
      _sync(pollNow: next.value == true && previous?.value != true);
    });

    // Coming back online: whatever arrived during the outage is waiting, and
    // every poll made while offline returned early without asking.
    ref.listen(isOnlineProvider, (previous, next) {
      if (next.value == true && previous?.value == false) _sync(pollNow: true);
    });

    return widget.child;
  }
}
