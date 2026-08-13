// core/push/push_service.dart — FCM registration, permission, and tap routing.
//
// Push is a LATENCY IMPROVEMENT over NotificationPoller's 60 s badge poll, not
// a replacement for it. FCM delivery is best-effort — OEM battery managers kill
// background processes, iOS throttles, a token can go stale without telling
// anyone. The poller is what makes the feed eventually correct; this makes it
// arrive now. Nothing here may be load-bearing for correctness.
//
// MOBILE ONLY. Every entry point returns early on web: web push needs a service
// worker and a VAPID key this build does not ship, and the poller already gets
// the browser's visibilitychange for free.
//
// FAILS SILENT, ALWAYS. A denied permission, a Firebase that never initialised,
// a /devices call that 500s — all of it leaves an app that behaves exactly as it
// did before push existed. There is nothing here worth showing an error for.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/notifications/domain/app_notification.dart';

/// Set once Firebase.initializeApp has succeeded. Everything below refuses to
/// run without it — a missing google-services.json must degrade to "no push",
/// never to a crash on launch.
bool _firebaseReady = false;

/// The token currently registered with the backend, so sign-out can name the
/// device to unregister. One device, one token; a refresh replaces it.
String? _registeredToken;

/// Where a tap should navigate, parked until a router exists to consume it.
///
/// A cold start from a terminated app delivers the tap through
/// getInitialMessage() before the widget tree — and therefore go_router — is
/// built. Navigating then is a no-op that silently swallows the tap, which is
/// the single most common real-world path.
String? _pendingRoute;

/// Must be top-level (not a closure or a method): Flutter spawns a separate
/// isolate for background messages and can only reach an entry point by name.
///
/// Deliberately empty. The OS has already drawn the tray notification by the
/// time this runs, and anything we did here would touch a provider tree that
/// does not exist in this isolate. It exists because firebase_messaging
/// requires a registered handler for background delivery to work at all.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Bring Firebase up. Called from main() before runApp, and never throws.
Future<void> initFirebase() async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _firebaseReady = true;
  } catch (e) {
    // Almost always a missing google-services.json / GoogleService-Info.plist.
    // The app is fully functional without push; say so and carry on.
    debugPrint('Firebase unavailable — push disabled: $e');
  }
}

/// Ask the OS for permission, then register the token with the backend.
///
/// iOS gives exactly ONE prompt per install: a denial can only be undone in
/// Settings. So this is called at a moment where the user has shown they want
/// notifications (opening the notification screen), never at launch.
///
/// Returns true when the device ended up registered.
Future<bool> registerForPush({required String locale}) async {
  if (kIsWeb || !_firebaseReady) return false;

  try {
    final messaging = FirebaseMessaging.instance;
    // Also drives the Android 13+ POST_NOTIFICATIONS runtime permission, so no
    // permission_handler dependency is needed.
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }

    final token = await messaging.getToken();
    if (token == null) return false;
    await _sendToken(token, locale: locale);
    return true;
  } catch (e) {
    debugPrint('Push registration failed: $e');
    return false;
  }
}

/// Wire up token rotation and the two tap paths. Called once, from main().
void attachPushListeners({
  required String Function() currentLocale,
  required void Function(String route) onRoute,
}) {
  if (kIsWeb || !_firebaseReady) return;

  final messaging = FirebaseMessaging.instance;

  // FCM rotates tokens on its own schedule. A token we never re-sent is one the
  // server keeps pushing to after it stopped working — silently, since a stale
  // token still returns 200 for a while.
  messaging.onTokenRefresh.listen((token) {
    // Only if this device was already registered: a refresh must not register a
    // device whose owner declined, or never reached the permission prompt.
    if (_registeredToken == null) return;
    _sendToken(token, locale: currentLocale());
  });

  // Warm start: the app was backgrounded and the user tapped the tray entry.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final route = _routeFor(message);
    if (route != null) onRoute(route);
  });

  // Cold start: the app was terminated. Parked rather than navigated — see
  // _pendingRoute.
  messaging.getInitialMessage().then((message) {
    if (message == null) return;
    _pendingRoute = _routeFor(message);
  });

  // Foreground messages are deliberately unhandled. Android suppresses the tray
  // entry while the app is open, and NotificationPoller's badge and SFX cue
  // already announce the arrival — a second cue would double up.
}

/// Hand over a route parked by a cold start, if any. Consumes it.
String? takePendingRoute() {
  final route = _pendingRoute;
  _pendingRoute = null;
  return route;
}

/// Stop pushing to this device. MUST be called on sign-out: a token that
/// outlives the session delivers the previous user's notifications — including
/// moderation notices — to whoever signs in next on the same phone.
Future<void> unregisterForPush() async {
  final token = _registeredToken;
  _registeredToken = null;
  if (kIsWeb || token == null) return;

  try {
    // Server first: the local token is worthless if the row survives, and the
    // request needs the access token that sign-out is about to discard.
    await dio.delete(deviceEndpoint(token));
  } catch (e) {
    debugPrint('Device unregister failed: $e');
  }
  try {
    // Also drop it on the device, so the next account gets a fresh token
    // rather than inheriting one the server has just forgotten.
    if (_firebaseReady) await FirebaseMessaging.instance.deleteToken();
  } catch (_) {
    // Best-effort: the server-side row is what actually stops delivery.
  }
}

/// Re-register after an in-app language change, so the server renders this
/// device's push text in the language now on screen. No-op when unregistered.
Future<void> updatePushLocale(String locale) async {
  final token = _registeredToken;
  if (token == null) return;
  await _sendToken(token, locale: locale);
}

Future<void> _sendToken(String token, {required String locale}) async {
  try {
    await dio.post(kDevicesEndpoint, data: {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
      'locale': locale,
    });
    _registeredToken = token;
  } catch (e) {
    // Leave _registeredToken alone: on a failed refresh the previously
    // registered token is still what the server knows about.
    debugPrint('Device registration failed: $e');
  }
}

/// Map an FCM `data` payload onto the same route the feed row would use.
///
/// Reuses notificationRoute so a tray tap and a feed tap can never disagree.
String? _routeFor(RemoteMessage message) {
  final data = message.data;
  return notificationRoute(
    type: NotificationType.fromString(data['type'] as String?),
    actorId: data['actor_id'] as String?,
    entityId: data['entity_id'] as String?,
  );
}

/// Whether push is available at all on this build/platform. Lets the UI avoid
/// offering an opt-in it cannot honour.
bool get pushAvailable => !kIsWeb && _firebaseReady;

/// True once this device has a token registered with the backend.
bool get pushRegistered => _registeredToken != null;
