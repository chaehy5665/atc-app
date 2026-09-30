#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build Annunciator.app on the Mac: release build, bundle, ad-hoc sign, install.
# Safe to re-run: the bundle and the installed copy are replaced each time.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app: needs macOS (this is $(uname -s))" >&2
  exit 1
fi

BUNDLE_ID="dev.atc.annunciator"
MIN_MACOS="14.0"
VERSION="0.1.0"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "build-app: swift build -c release"
swift build -c release --product Annunciator
bin="$(swift build -c release --show-bin-path)/Annunciator"

app="$root/dist/Annunciator.app"
echo "build-app: assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Annunciator"

echo "build-app: drawing the app icon"
mkdir -p "$app/Contents/Resources"
iconset="$(mktemp -d)/Annunciator.iconset"
swift Tools/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Annunciator.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Annunciator</string>
  <key>CFBundleDisplayName</key><string>Annunciator</string>
  <key>CFBundleExecutable</key><string>Annunciator</string>
  <key>CFBundleIconFile</key><string>Annunciator</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

echo "build-app: ad-hoc codesign"
codesign --force --sign - "$app"
codesign --verify --verbose=2 "$app"

dest="$HOME/Applications"
mkdir -p "$dest"
echo "build-app: installing to $dest/Annunciator.app"
if pgrep -x Annunciator >/dev/null; then
  echo "build-app: quitting the running Annunciator"
  pkill -x Annunciator || true
  sleep 1
fi
rm -rf "$dest/Annunciator.app"
ditto "$app" "$dest/Annunciator.app"

echo "build-app: done. Open it with: open \"$dest/Annunciator.app\""
