# Release Checklist

## Preflight

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
git status --short
```

작업 중 변경이 있으면 먼저 의도한 변경인지 확인한다.

## Static Checks

```zsh
zsh -n jam-usb-internet
for f in *.command; do zsh -n "$f"; done
python3 -m json.tool configs/sing-box.template.json >/dev/null
sing-box check -c configs/sing-box.template.json
```

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
pkg/dist/jam-usb-internet-<version>.zip
pkg/dist/jam-usb-internet-<version>.zip.sha256
```

## Known Non-Blocking Limitations

- Forced terminal close may still require manual `RECOVER`.
- LTE/Wi-Fi switching on the Galaxy during an active session can terminate the tunnel.
- Discord voice/video is not covered by the current TCP/DNS milestone.
- Native Android USB tethering remains non-primary on Mac.

