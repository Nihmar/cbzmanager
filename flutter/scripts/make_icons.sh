#!/usr/bin/env bash
#
# Regenerates the Flutter app icons from the shared Lazarus artwork, so both
# applications are branded identically. The Lazarus sources stay authoritative:
#
#   cbzmanager.ico     -> Windows application icon (7 frames, 16..256)
#   pkg/cbzmanager.svg -> Android launcher icons (and the Linux .desktop icon
#                         installed by the Lazarus Makefile/PKGBUILD)
#
# Usage: scripts/make_icons.sh   (requires rsvg-convert)
set -euo pipefail

cd "$(dirname "$0")/../.."
root=$(pwd)
svg="$root/pkg/cbzmanager.svg"
ico="$root/cbzmanager.ico"
android_res="$root/flutter/app/android/app/src/main/res"
windows_ico="$root/flutter/app/windows/runner/resources/app_icon.ico"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "rsvg-convert is required (package librsvg)" >&2
  exit 1
}
[ -f "$svg" ] || { echo "missing icon source: $svg" >&2; exit 1; }
[ -f "$ico" ] || { echo "missing icon source: $ico" >&2; exit 1; }

# Android launcher icon, one PNG per density bucket.
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${pair%%:*}
  size=${pair##*:}
  out="$android_res/mipmap-$density/ic_launcher.png"
  rsvg-convert -w "$size" -h "$size" -o "$out" "$svg"
  echo "android  mipmap-$density/ic_launcher.png ${size}x${size}"
done

# Windows: copy rather than re-encode, so the two apps stay byte-identical.
cp "$ico" "$windows_ico"
echo "windows  runner/resources/app_icon.ico (copy of cbzmanager.ico)"

echo
echo "Linux uses the same artwork through pkg/cbzmanager.svg, installed as"
echo "hicolor/scalable/apps/cbzmanager.svg; the GTK runner looks the icon up by"
echo "the 'cbzmanager' theme name (see linux/runner/my_application.cc)."
