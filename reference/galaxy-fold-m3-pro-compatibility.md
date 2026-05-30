# Galaxy Fold + MacBook Pro M3 Pro Compatibility Review

Date: 2026-05-30

## Scope

This note reviews whether `jam-usb-internet` can be used with:

- Samsung Galaxy Fold / Galaxy Z Fold family
- MacBook Pro with Apple M3 Pro

The review separates two different paths:

1. Native Android USB tethering recognized by macOS as a USB network interface.
2. ADB relay + sing-box TUN, which is the current project path.

## Source Summary

### Android USB Tethering and Mac

Google Android Help states that Android phones can tether by Wi-Fi, Bluetooth, or USB, but it explicitly warns:

```text
Mac computers can't tether with Android by USB.
```

Source:

- https://support.google.com/android/answer/9059108

Interpretation:

- Native Android USB tethering should not be treated as supported on Mac.
- If a specific Android phone exposes a USB network class that macOS happens to support, that is device/OS-specific luck rather than a reliable project baseline.

### Samsung Galaxy USB Modes

Samsung documents that Galaxy USB connections include:

- file transfer / Android Auto
- USB tethering
- image transfer
- charge only

Samsung also notes that the selected USB function requires support on both devices.

Source:

- https://www.samsung.com/us/support/answer/ANS10002546/

Interpretation:

- Galaxy Fold devices are expected to expose the USB modes needed for file transfer and ADB.
- Galaxy USB tethering existing on the phone does not guarantee macOS will expose it as a usable network service.
- For this project, the preferred phone mode is `Transferring files / Android Auto`, not `USB tethering`.

### ADB over USB

Android Developers documents that ADB can communicate with devices over USB when USB debugging is enabled. It also documents the RSA authorization prompt that requires the user to unlock and authorize the device.

Source:

- https://developer.android.com/tools/adb

Interpretation:

- The project path is compatible with Galaxy Fold devices if ADB over USB works.
- The required phone-side setup remains:
  - enable Developer options
  - enable USB debugging
  - connect with a data-capable cable
  - unlock and approve the Mac's RSA debugging key
  - keep USB mode in `Transferring files / Android Auto`

### Android Native Binary ABI

Android NDK documentation lists `arm64-v8a` as the ABI for 64-bit ARM CPUs.

Source:

- https://developer.android.com/ndk/guides/abis

Interpretation:

- The existing Android relay binary for `arm64-v8a` is the right first target for modern Galaxy Fold devices.
- Final confirmation should still be done on the actual phone:

```zsh
adb shell getprop ro.product.cpu.abilist
```

Expected passing condition:

```text
arm64-v8a
```

must appear in the ABI list.

### MacBook Pro M3 Pro USB Hardware and Accessory Approval

Apple documents the MacBook Pro M3 Pro as having Thunderbolt 4 / USB 4 ports.

Source:

- https://support.apple.com/en-ie/117736

Apple also documents that Apple silicon Mac laptops may require user approval before new USB or Thunderbolt accessories can communicate with the Mac.

Source:

- https://support.apple.com/en-us/102282

Interpretation:

- MacBook Pro M3 Pro has suitable physical USB-C/Thunderbolt ports for the ADB relay path.
- The first connection may require clicking `Allow` on macOS before ADB can see the phone.
- If macOS does not recognize the phone for data, check:
  - cable is data-capable
  - Mac is unlocked
  - accessory approval prompt was accepted
  - phone USB mode is file transfer / Android Auto
  - ADB authorization prompt was accepted on the phone

## Compatibility Decision

### Native USB Tethering

Status:

```text
Not reliable / not supported as the project baseline.
```

Reason:

- Google Android Help explicitly says Mac computers cannot tether with Android by USB.
- Samsung documents USB tethering on Galaxy phones, but macOS must also support the selected USB function.
- Therefore Galaxy Fold + MacBook Pro M3 Pro should not be expected to create a usable Android USB LAN interface.

Project implication:

```text
Do not make native USB tethering the primary path for Galaxy Fold + M3 Pro.
```

### ADB Relay + TUN

Status:

```text
Theoretically compatible and likely usable, subject to live validation.
```

Reason:

- The project does not depend on macOS recognizing Android as USB Ethernet.
- It depends on:
  - USB data connection
  - ADB authorization
  - Android `arm64-v8a` relay binary
  - phone internet through Wi-Fi or mobile data
  - macOS TUN route/DNS handling through `sing-box`
- All of these are expected to be available on Galaxy Fold + MacBook Pro M3 Pro.

Project implication:

```text
Galaxy Fold + MacBook Pro M3 Pro should use the same ON/OFF/RECOVER workflow as the Note 9 setup.
```

## Required Validation Checklist

Run on the actual Galaxy Fold + M3 Pro pair:

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.product.cpu.abilist
./jam-usb-internet doctor
./jam-usb-internet system --check-only
```

Expected:

- `adb devices` shows the phone as `device`, not `unauthorized`.
- ABI list includes `arm64-v8a`.
- `system --check-only` passes relay checks:
  - Chrome/web
  - Discord
  - Kakao
  - git

Then test the system mode:

```zsh
./jam-usb-internet system
./jam-usb-internet app-check
./jam-usb-internet system-stop
```

Expected completion:

- Mac Wi-Fi off or disconnected.
- Galaxy Fold Wi-Fi or mobile data connected.
- Chrome/web works.
- Discord text/API works.
- KakaoTalk works.
- git over HTTPS works.
- `app-check` passes.
- `system-stop` restores normal Mac networking.

## Known Carryover Limitations

These limitations are not Fold-specific; they carry over from the current prototype:

- Forced terminal close can still require manual `RECOVER`.
- Mid-session phone network switching, for example LTE to Wi-Fi, can interrupt the tunnel.
- Discord voice/video is not guaranteed because UDP is outside the current TCP/DNS milestone.
- Native Android USB tethering should remain non-primary on Mac.

## Bottom Line

The Galaxy Fold + MacBook Pro M3 Pro combination is not a good candidate for native USB tethering as a Mac USB LAN device.

It is a good candidate for the current ADB relay + sing-box TUN design, provided that:

- the Mac approves the USB accessory,
- the phone authorizes ADB,
- `arm64-v8a` is present,
- `system --check-only` passes,
- `app-check` passes in system mode.

