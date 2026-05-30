# Stage 2: Android SOCKS Relay

Goal: replace per-connection `adb shell nc` with a persistent relay.

Deliverables:

- Android arm64 `knock-relay` binary. Done.
- SOCKS5 no-auth CONNECT. Done.
- Domain-name CONNECT with custom DNS resolver. Done.
- `adb forward tcp:18080 tcp:18080`. Done.
- Relay health check. Done.

Acceptance tests:

```zsh
curl --socks5-hostname 127.0.0.1:18080 http://example.com
curl --socks5-hostname 127.0.0.1:18080 https://example.com
```

The Mac may still require per-app proxy config in this stage.

Verified:

```text
HTTP through relay: OK
HTTPS through relay: OK
HTTPS through relay after Android DNS resolver repair: OK
ADB forward cleanup: OK
```

Implementation note:

- The Android shell resolver attempted `[::1]:53` on this Note 9, so the relay now uses an explicit Go resolver and dials resolved addresses IPv4-first.
