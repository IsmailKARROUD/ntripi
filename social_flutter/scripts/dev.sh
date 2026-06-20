#!/bin/bash
flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SHARE_BASE_URL=http://localhost:8000 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
# ^ Replace with your Web OAuth client id. On web the button actually reads the
#   client id from web/index.html's meta tag; this define is used on Android/iOS.