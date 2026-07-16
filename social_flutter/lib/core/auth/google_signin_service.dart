// core/auth/google_signin_service.dart — thin wrapper over google_sign_in v7.
//
// Isolating the plugin here keeps the repository and most of the login screen
// free of plugin types (and unit-testable). The v7 API differs sharply from v6:
// a singleton (GoogleSignIn.instance), a one-time initialize(), synchronous
// supportsAuthenticate()/authentication, and authenticate() replacing signIn().

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'package:social_flutter/core/api/api_endpoints.dart';

class GoogleSignInService {
  GoogleSignInService._();
  static final GoogleSignInService instance = GoogleSignInService._();

  Future<void>? _initFuture;

  /// initialize() must run exactly once before any auth call — cache the future
  /// so concurrent callers share a single initialization.
  Future<void> ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(
      // serverClientId = the web/server OAuth client id; makes the issued ID
      // token's `aud` equal the backend audience. Null when not configured.
      // Must be null on web — the plugin asserts serverClientId == null there
      // (web reads its client id from index.html's google-signin-client_id
      // meta tag, and the issued credential is already aud=web-client-id).
      serverClientId: kIsWeb || kGoogleServerClientId.isEmpty
          ? null
          : kGoogleServerClientId,
    );
  }

  /// Interactive authenticate() is supported on mobile/desktop but NOT on web —
  /// there the rendered button + [authenticationEvents] stream is used instead.
  bool get supportsInteractiveAuth =>
      GoogleSignIn.instance.supportsAuthenticate();

  /// Auth event stream — the web rendered-button flow reads the ID token from
  /// the emitted sign-in event.
  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      GoogleSignIn.instance.authenticationEvents;

  /// Run the interactive Google sign-in (mobile/desktop) and return the ID
  /// token to POST to the backend. Returns null when the user cancels.
  Future<String?> obtainIdToken() async {
    await ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      // Cancellation isn't an error worth surfacing to the user.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
