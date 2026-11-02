#!/bin/bash
# Baut HAKiosk unsigniert für ein echtes iOS-Gerät und packt es als .ipa.
# Muss auf einem Mac mit einer Xcode-Version laufen, die iOS 12.0 noch als
# Deployment Target erlaubt (z.B. Xcode 13.x oder 14.x). Aktuelle Xcode-
# Versionen (ab ca. 2026) haben die Untergrenze angehoben und lehnen den
# Build mit "range of supported deployment target versions is X to Y" ab.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild (Release, unsigniert, iphoneos)"
rm -rf build
xcodebuild \
  -project HAKiosk.xcodeproj \
  -scheme HAKiosk \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_PATH="build/Build/Products/Release-iphoneos/HAKiosk.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Build-Ausgabe nicht gefunden: $APP_PATH" >&2
  exit 1
fi

echo "==> Fakesigning (ldid) für AppSync Unified / Jailbreak-Install"
# AppSync Unified akzeptiert ungültige Signaturen, verlangt aber trotzdem eine
# vorhandene Signatur mit application-identifier-Entitlement. Ohne das bricht
# installd mit "ApplicationVerificationFailed ... missing the
# application-identifier entitlement" ab.
if ! command -v ldid >/dev/null 2>&1; then
  echo "ldid nicht gefunden. Installieren mit: brew install ldid" >&2
  exit 1
fi
ldid -Sfakesign-entitlements.plist "$APP_PATH/HAKiosk"

echo "==> Payload packen"
rm -rf Payload HAKiosk.ipa
mkdir Payload
cp -r "$APP_PATH" Payload/
zip -r -q HAKiosk.ipa Payload
rm -rf Payload

echo "==> Fertig: $(pwd)/HAKiosk.ipa"
