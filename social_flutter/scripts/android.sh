#!/bin/bash
# Run on a connected Android device/emulator with the Google sign-in client id.
# GOOGLE_SERVER_CLIENT_ID is the WEB OAuth client id (Android's ID token uses it
# as `aud`). It is NOT a secret — the backend reads its own copy from .env/Railway.
#
# API_BASE_URL: pick the one matching how the phone reaches your backend:
#   • Deployed:        https://ntripi.app
#   • Android emulator http://10.0.2.2:8000   (10.0.2.2 = host's localhost)
#   • Physical device  http://<your-LAN-IP>:8000
flutter run \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com
