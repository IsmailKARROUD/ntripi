#!/bin/bash
# Build the Play Store bundle (run from social_flutter/). A bare
# `flutter build appbundle` compiles in api_endpoints.dart's localhost defaults,
# which is why android/app/build.gradle.kts now refuses a release build without
# API_BASE_URL. Signing comes from android/key.properties (gitignored).
# Bump the +build number in pubspec.yaml before every upload — Play rejects a
# versionCode it has already seen.
# GOOGLE_SERVER_CLIENT_ID is the WEB OAuth client, never an Android one — Android
# clients are matched by package name + SHA-1 and never go in the app.
flutter build appbundle \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com
