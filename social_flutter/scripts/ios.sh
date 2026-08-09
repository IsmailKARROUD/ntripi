#!/bin/bash
# Run on a connected iOS device/simulator.
#
# GOOGLE_SERVER_CLIENT_ID is passed for parity with android.sh but is IGNORED on
# iOS: google_sign_in_ios discards initialize()'s serverClientId unless it also
# gets a clientId, which we do not pass. The iOS ids live in ios/Runner/
# Info.plist (GIDClientID / GIDServerClientID / the reversed URL scheme).
#
# API_BASE_URL: pick the one matching how the device reaches your backend:
#   • Deployed:        https://ntripi.app
#   • Simulator        http://localhost:8000
#   • Physical device  http://<your-LAN-IP>:8000
flutter run \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com \
  --dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSyD8gF4G_w7voK0YPHA_Y234sgXInsrU__8
