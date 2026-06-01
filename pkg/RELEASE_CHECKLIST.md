# Release Checklist

## Preflight

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
git status --short
```

작업 중 변경이 있으면 먼저 의도한 변경인지 확인한다.

## Dependency Policy

Runtime required:

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

Runtime not required:

- Android File Transfer
- Reduced Security
- SIP off
- Gatekeeper off
- RNDIS driver

## Static Checks

```zsh
zsh -n jam-usb-internet
for f in *.command; do zsh -n "$f"; done
python3 -m json.tool configs/sing-box.template.json >/dev/null
sing-box check -c configs/sing-box.template.json
./jam-usb-internet doctor --json >/dev/null
./jam-usb-internet system-status --json >/dev/null
ui/build-app.sh
codesign --verify --deep --strict --verbose=2 "ui/build/Jam USB Internet.app"
```

`ui/build-app.sh` 기본값은 local test용 ad-hoc signing이다.

## Android Relay Check

```zsh
cd android-relay
GOCACHE="$PWD/.gocache" go test ./...
cd ..
```

## Normal Network Check

Mac Wi-Fi가 정상 연결된 상태:

```zsh
./jam-usb-internet app-check
./jam-usb-internet system-status
```

## Target Device Check

Galaxy 연결 후:

```zsh
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.product.cpu.abilist
./jam-usb-internet system --check-only
```

Mac Wi-Fi off 또는 disconnected 상태:

```zsh
./jam-usb-internet system
./jam-usb-internet app-check
./jam-usb-internet system-stop
```

## Package Build

```zsh
pkg/build-dist.sh
```

결과:

```text
pkg/dist/jam-usb-internet-<version>/
  Jam USB Internet.app
  jam-usb-internet
  Galaxy USB Internet ON.command
  ...
pkg/dist/jam-usb-internet-<version>.zip
pkg/dist/jam-usb-internet-<version>.zip.sha256
```

Unzip integrity:

```zsh
unzip -t pkg/dist/jam-usb-internet-<version>.zip
rm -rf /tmp/jam-usb-internet-release-check
mkdir -p /tmp/jam-usb-internet-release-check
unzip -q pkg/dist/jam-usb-internet-<version>.zip -d /tmp/jam-usb-internet-release-check
codesign --verify --deep --strict --verbose=2 \
  "/tmp/jam-usb-internet-release-check/jam-usb-internet-<version>/Jam USB Internet.app"
```

## Developer ID Release

Ad-hoc signing is sufficient only for local structural testing.

External distribution without manual bypass:

```text
Developer ID Application signing
Apple notarization
```

Build with a configured Developer ID certificate:

```zsh
JAM_USB_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  pkg/build-dist.sh
```

Then follow:

```text
pkg/CODE_SIGNING.md
```

GUI smoke check after unzip:

1. Open `Jam USB Internet.app`.
2. Confirm preflight checks render (ADB, sing-box).
3. Confirm status header refreshes.
4. If Galaxy is connected, ON/OFF/RECOVER buttons are enabled.
5. Fallback: `Galaxy USB Internet ON.command` still works.

## Known Non-Blocking Limitations

- Forced terminal close may still require manual `RECOVER`.
- LTE/Wi-Fi switching on the Galaxy during an active session can terminate the tunnel.
- Discord voice/video is not covered by the current TCP/DNS milestone.
- Native Android USB tethering remains non-primary on Mac.
