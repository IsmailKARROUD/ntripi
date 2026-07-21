#!/bin/bash
flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SHARE_BASE_URL=http://localhost:8000 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com \
  --dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSyD8gF4G_w7voK0YPHA_Y234sgXInsrU__8
# ^ Replace with your Web OAuth client id. On web the button actually reads the
#   client id from web/index.html's meta tag; this define is used on Android/iOS.