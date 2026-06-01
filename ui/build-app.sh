#!/bin/zsh
set -euo pipefail

UI_DIR="${0:a:h}"
SRC="${UI_DIR}/JamUSBInternet"
OUT="${UI_DIR}/build"
APP_NAME="Jam USB Internet"
APP="${OUT}/${APP_NAME}.app"
SDK="$(xcrun --show-sdk-path)"
VERSION="$(awk -F= '/^VERSION=/{gsub(/"/, "", $2); print $2; exit}' "${UI_DIR:h}/jam-usb-internet")"
SIGN_IDENTITY="${JAM_USB_SIGN_IDENTITY:--}"

if [[ -z "$VERSION" ]]; then
  VERSION="0.0.0"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

/usr/bin/swiftc \
  -O \
  -sdk "$SDK" \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -o "$APP/Contents/MacOS/JamUSBInternet" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework Combine \
  "${SRC}/Models.swift" \
  "${SRC}/CLIRunner.swift" \
  "${SRC}/AppViewModel.swift" \
  "${SRC}/ContentView.swift" \
  "${SRC}/LogTextEditor.swift" \
  "${SRC}/JamUSBInternetApp.swift"

cp "${SRC}/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist" >/dev/null

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign \
    --force \
    --sign - \
    "$APP"
  echo "Signed ad hoc for local testing."
else
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP"
  echo "Signed with: $SIGN_IDENTITY"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built: $APP"
