#!/usr/bin/env bash
#
# Builds release artifacts for the Flutter port on the current host.
#
#   Linux   -> build/linux/x64/release/bundle, plus an APK/AAB if an Android
#              SDK is available
#   Windows -> build/windows/x64/runner/Release
#   macOS   -> build/macos/Build/Products/Release
#
# Usage: scripts/build_release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
cd app

flutter pub get
flutter analyze
flutter test

case "$(uname -s)" in
  Linux)
    flutter build linux --release
    if command -v flutter >/dev/null 2>&1 && flutter doctor --list 2>/dev/null | grep -q 'Android toolchain'; then
      flutter build apk --release || true
      flutter build appbundle --release || true
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    flutter build windows --release
    ;;
  Darwin)
    flutter build macos --release
    ;;
  *)
    echo "Unsupported host: $(uname -s)" >&2
    exit 1
    ;;
esac

echo "Done. Artifacts are under app/build/."
