#!/bin/sh
# Refuse a Release build (flutter build ipa, or Xcode ▸ Archive) that would call
# localhost — the iOS twin of the API_BASE_URL guard in android/app/build.gradle.kts.
case "$CONFIGURATION" in
  Release*) ;;
  *) exit 0 ;;
esac

# Flutter hands each --dart-define to Xcode base64-encoded, comma-joined, as DART_DEFINES.
api_base_url=$(printf '%s' "$DART_DEFINES" | tr ',' '\n' | while read -r define; do
  [ -n "$define" ] && printf '%s' "$define" | base64 -D && echo
done | sed -n 's/^API_BASE_URL=//p')

case "$api_base_url" in
  https://*) exit 0 ;;
esac
echo "error: No --dart-define=API_BASE_URL=https://… — this build would call localhost. Use scripts/release_ios.sh."
exit 1
