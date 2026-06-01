#!/bin/zsh
set -euo pipefail

PKG_DIR="${0:a:h}"
ROOT="${PKG_DIR:h}"
VERSION="$(awk -F= '/^VERSION=/{gsub(/"/, "", $2); print $2; exit}' "$ROOT/jam-usb-internet")"

if [[ -z "$VERSION" ]]; then
  echo "Could not read VERSION from jam-usb-internet" >&2
  exit 1
fi

BUNDLE_NAME="jam-usb-internet-${VERSION}"
DIST_DIR="${PKG_DIR}/dist"
BUNDLE_DIR="${DIST_DIR}/${BUNDLE_NAME}"
ZIP_PATH="${DIST_DIR}/${BUNDLE_NAME}.zip"
SHA_PATH="${ZIP_PATH}.sha256"

rm -rf "$BUNDLE_DIR" "$ZIP_PATH" "$SHA_PATH"
mkdir -p "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/configs"
mkdir -p "$BUNDLE_DIR/android-relay/bin/arm64-v8a"
mkdir -p "$BUNDLE_DIR/docs/reference"

cp "$ROOT/jam-usb-internet" "$BUNDLE_DIR/"
cp "$ROOT/jam-usb-askpass" "$BUNDLE_DIR/"
cp "$ROOT/adb-socks-proxy.py" "$BUNDLE_DIR/"
cp "$ROOT"/*.command "$BUNDLE_DIR/"
cp "$ROOT/configs/sing-box.template.json" "$BUNDLE_DIR/configs/"
cp "$ROOT/android-relay/bin/arm64-v8a/knock-relay" "$BUNDLE_DIR/android-relay/bin/arm64-v8a/"

cp "$ROOT/README.md" "$BUNDLE_DIR/docs/PROJECT_README.md"
cp "$PKG_DIR/README.md" "$BUNDLE_DIR/README_PACKAGE.md"
cp "$PKG_DIR/GALAXY_SETUP.md" "$BUNDLE_DIR/docs/GALAXY_SETUP.md"
cp "$PKG_DIR/MAC_SETUP.md" "$BUNDLE_DIR/docs/MAC_SETUP.md"
cp "$PKG_DIR/USAGE.md" "$BUNDLE_DIR/docs/USAGE.md"
cp "$PKG_DIR/PREINSTALL_SECURITY_REVIEW.md" "$BUNDLE_DIR/docs/PREINSTALL_SECURITY_REVIEW.md"
cp "$PKG_DIR/CODE_SIGNING.md" "$BUNDLE_DIR/docs/CODE_SIGNING.md"
cp "$PKG_DIR/RELEASE_CHECKLIST.md" "$BUNDLE_DIR/docs/RELEASE_CHECKLIST.md"

if [[ -d "$ROOT/reference" ]]; then
  cp "$ROOT/reference"/*.md "$BUNDLE_DIR/docs/reference/" 2>/dev/null || true
fi

chmod +x "$BUNDLE_DIR/jam-usb-internet"
chmod +x "$BUNDLE_DIR/jam-usb-askpass"
chmod +x "$BUNDLE_DIR"/*.command

UI_BUILD="${ROOT}/ui/build-app.sh"
APP_NAME="Jam USB Internet.app"
if [[ -x "$UI_BUILD" ]]; then
  "$UI_BUILD"
  if [[ -d "${ROOT}/ui/build/${APP_NAME}" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${ROOT}/ui/build/${APP_NAME}"
    if command -v ditto >/dev/null 2>&1; then
      ditto "${ROOT}/ui/build/${APP_NAME}" "${BUNDLE_DIR}/${APP_NAME}"
    else
      cp -R "${ROOT}/ui/build/${APP_NAME}" "$BUNDLE_DIR/"
    fi
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${BUNDLE_DIR}/${APP_NAME}"
    echo "Included: ${APP_NAME}"
  else
    echo "Warning: UI build did not produce ${APP_NAME}" >&2
  fi
else
  echo "Warning: ${UI_BUILD} not found; skipping GUI app" >&2
fi

cat > "$BUNDLE_DIR/START_HERE.txt" <<EOF
jam-usb-internet ${VERSION}

1. Read docs/GALAXY_SETUP.md and docs/MAC_SETUP.md.
2. Read docs/PREINSTALL_SECURITY_REVIEW.md.
3. For app-signing details, read docs/CODE_SIGNING.md.
4. Install only required dependencies: android-platform-tools and sing-box.
5. Do not install Android File Transfer for this tool unless you separately need GUI file browsing.
6. Do not lower macOS security policy, disable SIP, or install RNDIS drivers.
7. Connect Galaxy by USB data cable.
8. Set Galaxy USB mode to File Transfer / Android Auto.
9. Authorize USB debugging.
10. Double-click: Jam USB Internet.app
   Fallback: Galaxy USB Internet ON.command
11. Stop safely with the app's [끄기] button or Galaxy USB Internet OFF.command
12. If normal Mac internet does not recover, use the app's [복구] button or Galaxy USB Internet RECOVER.command

Current milestone: TCP/DNS internet for Chrome, Discord text/API, KakaoTalk, and git.
Known limits: forced close may need RECOVER; Discord voice/video UDP is not covered.
EOF

if command -v zip >/dev/null 2>&1; then
  (cd "$DIST_DIR" && zip -X -qry "$ZIP_PATH" "$BUNDLE_NAME")
elif command -v ditto >/dev/null 2>&1; then
  (cd "$DIST_DIR" && ditto -c -k --keepParent "$BUNDLE_NAME" "$ZIP_PATH")
else
  echo "Neither zip nor ditto is available" >&2
  exit 1
fi

if unzip -l "$ZIP_PATH" | awk '{print $4}' | grep -E '(^|/)\._|^__MACOSX/' >/dev/null 2>&1; then
  echo "Packaged zip contains macOS metadata files" >&2
  exit 1
fi

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jam-usb-internet-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$ZIP_PATH" -d "$VERIFY_DIR"
if [[ -d "${VERIFY_DIR}/${BUNDLE_NAME}/${APP_NAME}" ]]; then
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${VERIFY_DIR}/${BUNDLE_NAME}/${APP_NAME}"
fi

shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "Built:"
echo "  $BUNDLE_DIR"
echo "  $ZIP_PATH"
echo "  $SHA_PATH"
