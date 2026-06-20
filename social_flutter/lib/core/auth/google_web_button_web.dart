// Web implementation of [GoogleWebButton].
//
// Renders Google Identity Services' official button and listens to the auth
// event stream; when the user signs in, it hands the ID token back to the
// caller (the login screen POSTs it to the backend).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

import 'package:social_flutter/core/auth/google_signin_service.dart';

class GoogleWebButton extends StatefulWidget {
  final void Function(String idToken) onIdToken;
  final void Function(Object error)? onError;
  const GoogleWebButton({super.key, required this.onIdToken, this.onError});

  @override
  State<GoogleWebButton> createState() => _GoogleWebButtonState();
}

class _GoogleWebButtonState extends State<GoogleWebButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;

  @override
  void initState() {
    super.initState();
    GoogleSignInService.instance.ensureInitialized().then((_) {
      if (!mounted) return;
      _sub = GoogleSignInService.instance.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            final idToken = event.user.authentication.idToken;
            if (idToken != null) widget.onIdToken(idToken);
          }
        },
        onError: (Object e) => widget.onError?.call(e),
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => web.renderButton();
}
