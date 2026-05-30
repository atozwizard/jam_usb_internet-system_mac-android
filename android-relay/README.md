# Android Relay Skeleton

Purpose: persistent Android-side relay for Mac-wide USB internet mode.

Target path on device:

```text
/data/local/tmp/knock-relay
```

Target ABI:

```text
arm64-v8a
```

Initial protocol:

- SOCKS5 no-auth
- CONNECT only
- TCP only
- IPv4 and domain names
- Domain names resolve through DoH over HTTPS first, then fall back to direct DNS

Non-goals for the first relay:

- APK installation
- root
- background Android service
- UDP relay
- Android `VpnService`

Expected lifecycle:

```text
adb push knock-relay /data/local/tmp/knock-relay
adb shell chmod 755 /data/local/tmp/knock-relay
adb shell /data/local/tmp/knock-relay --listen 127.0.0.1:18080
adb forward tcp:18080 tcp:18080
```

Implementation candidates:

- Go cross-compiled to Android arm64. Selected for Stage 2.
- Rust cross-compiled to Android arm64
- C with Android NDK

Build:

```zsh
./build.sh
```

Output:

```text
bin/arm64-v8a/knock-relay
```
