#!/usr/bin/env bash
# Build "BitchBoy Nano.app", sign it, notarize it, staple the ticket.
#
# One-time setup, since notarytool needs an app-specific password:
#   xcrun notarytool store-credentials bitchboy \
#     --apple-id you@example.com --team-id B5D2ACYWRR --password abcd-efgh-ijkl-mnop
#
# Skip notarization (local testing) with: ./make-app.sh --no-notarize
set -euo pipefail

IDENTITY="Developer ID Application: Meneer de Baas B.V. (B5D2ACYWRR)"
PROFILE="bitchboy"
APP="build/BitchBoy Nano.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64
swift run --quiet Flasher --check

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/firmware"
cp .build/apple/Products/Release/Flasher "$APP/Contents/MacOS/Flasher"
cp AppIcon.icns "$APP/Contents/Resources/"
cp firmware/keypad.bin "$APP/Contents/Resources/firmware/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>BitchBoy Nano</string>
  <key>CFBundleDisplayName</key>        <string>BitchBoy Nano</string>
  <key>CFBundleIdentifier</key>         <string>nl.afstkla.bitchboynano</string>
  <key>CFBundleExecutable</key>         <string>Flasher</string>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>            <string>1</string>
  <key>LSMinimumSystemVersion</key>     <string>13.0</string>
  <key>LSApplicationCategoryType</key>  <string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
PLIST

codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "${1:-}" = "--no-notarize" ]; then
  echo "Built $APP (signed, not notarized)"
  exit 0
fi

ditto -c -k --keepParent "$APP" build/BitchBoyNano.zip
xcrun notarytool submit build/BitchBoyNano.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f build/BitchBoyNano.zip
ditto -c -k --keepParent "$APP" build/BitchBoyNano.zip
echo "Notarized and stapled. Send build/BitchBoyNano.zip"
