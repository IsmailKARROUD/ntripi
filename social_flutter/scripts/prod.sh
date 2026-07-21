#!/bin/bash
flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com \
  --dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSyD8gF4G_w7voK0YPHA_Y234sgXInsrU__8
# ^ Replace with your Web OAuth client id (same one for dev and prod). On web the
#   button reads the client id from web/index.html's meta tag; this is for Android/iOS.