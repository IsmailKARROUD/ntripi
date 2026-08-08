// core/auth/google_signin_service.dart — thin wrapper over google_sign_in v7.
//
// Isolating the plugin here keeps the repository and most of the login screen
// free of plugin types (and unit-testable). The v7 API differs sharply from v6:
// a singleton (GoogleSignIn.instance), a one-time initialize(), synchronous
// supportsAuthenticate()/authentication, and authenticate() replacing signIn().

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'package:social_flutter/core/api/api_endpoints.dart';

/// Google's sensitive scope for reading the profile birthday. Sensitive means
/// the OAuth client must pass Google's verification review before non-test
/// users can grant it; until then this call fails and the consent sheet is
/// what collects the date.
const String kGoogleBirthdayScope =
    'https://www.googleapis.com/auth/user.birthday.read';

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
      _lastAccount = account;
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      // Cancellation isn't an error worth surfacing to the user.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// The account from the most recent authenticate(), kept so the birthday
  /// scope can be requested against the SAME account. GoogleSignIn.instance
  /// .authorizationClient is built with a null user, so on a device with
  /// several Google accounts it can mint a token for the wrong one; the
  /// account-scoped client cannot.
  GoogleSignInAccount? _lastAccount;

  /// An OAuth access token for the birthday scope, or null if we cannot get
  /// one — the user declined the consent screen, the platform has no scoped
  /// client (web), or the plugin threw.
  ///
  /// Null is an ORDINARY outcome, not an error: the caller then asks for the
  /// date of birth directly. Call this only once the server has said the token
  /// means a signup — prompting for a sensitive scope on every sign-in would
  /// nag every returning Google user forever.
  Future<String?> obtainBirthdayAccessToken() async {
    await ensureInitialized();
    final client =
        _lastAccount?.authorizationClient ?? GoogleSignIn.instance.authorizationClient;
    try {
      final authz = await client.authorizeScopes([kGoogleBirthdayScope]);
      return authz.accessToken;
    } on GoogleSignInException {
      return null;
    } catch (_) {
      // Web in particular can reject the scoped-token flow outright; the
      // consent sheet covers it.
      return null;
    }
  }
}
