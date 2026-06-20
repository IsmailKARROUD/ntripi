#!/bin/bash
flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
# ^ Replace with your Web OAuth client id (same one for dev and prod). On web the
#   button reads the client id from web/index.html's meta tag; this is for Android/iOS.