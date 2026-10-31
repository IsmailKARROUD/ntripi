#!/bin/bash
# Build the App Store .ipa (run from social_flutter/). A bare `flutter build ipa`
# compiles in api_endpoints.dart's localhost defaults, which is why
# ios/scripts/require_release_defines.sh now refuses a Release build without
# API_BASE_URL. Signing is Xcode's automatic signing (team K8G92959RF).
# Bump the +build number in pubspec.yaml before every upload — App Store Connect
# rejects a CFBundleVersion it has already seen for the same version.
# GOOGLE_SERVER_CLIENT_ID is ignored on iOS (see ios.sh) — passed for parity.
flutter build ipa \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=29126714665-9pgodn1nt1ikf6goo71a6b7634sknna4.apps.googleusercontent.com
