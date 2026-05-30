# Stage 1: Relay Skeleton

Goal: prepare persistent Android relay lifecycle without changing Mac routes.

Deliverables:

- Add `relay-install`. Done.
- Add `relay-start`. Done as skeleton.
- Add `relay-stop`. Done as skeleton.
- Add `relay-clean`. Done as skeleton.
- Add Android ABI detection. Done.
- Add ADB forward creation/removal. Done as skeleton.

Acceptance tests:

```zsh
adb shell getprop ro.product.cpu.abi
./jam-usb-internet relay-install
./jam-usb-internet relay-start
adb forward --list
./jam-usb-internet relay-stop
./jam-usb-internet relay-clean
```

No TUN engine is started in this stage.

Current expected failure:

```text
relay-install fails until android-relay/bin/arm64-v8a/knock-relay exists.
```

Verified device:

```text
samsung SM-N960N
Android 10 / SDK 29
ABI arm64-v8a
```
