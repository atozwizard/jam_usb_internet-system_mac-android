# Stage 3: Mac TUN Prototype

Goal: Mac-wide TCP/DNS internet through the phone relay.

Deliverables:

- TUN engine detection. Done with `sing-box`.
- Generated TUN config. Done.
- `system`. Implemented first prototype.
- `system-stop`. Implemented first prototype.
- cleanup on interrupt. Implemented for relay; full TUN cleanup requires live validation.

Acceptance tests:

```zsh
./jam-usb-internet system --mobile-only
curl https://example.com
git ls-remote https://github.com/git/git.git HEAD
./jam-usb-internet system-stop
```

This stage may require `sudo`.

Safe preflight:

```zsh
./jam-usb-internet system --mobile-only --check-only
```

Verified preflight:

```text
relay install/start: OK
relay HTTPS health check: OK
sing-box config validation: OK
relay cleanup: OK
```

Latest preflight:

```text
./jam-usb-internet system --mobile-only --check-only --timeout 5
Relay health check succeeded through 127.0.0.1:18080.
System mode check passed.
```

Route/DNS repair:

- Start now pre-cleans old `sing-box` instances to prevent mismatched `utun` routes.
- The script waits for `172.19.0.1` on TUN, then adds split IPv4 routes manually.
- macOS DNS is temporarily set to `127.0.0.1`.
- sing-box listens on `127.0.0.1:53` and hijacks DNS to its configured DoH resolver through the phone relay.
- Stop restores DNS and removes manual routes.

Recovery repair:

- `system-stop` repairs stale local-only DNS even if the DNS backup is missing.
- Full system mode now verifies local DNS before mutating macOS DNS.
- If local DNS fails, it cleans up and leaves normal Wi-Fi DNS untouched.

Next proof point:

- Run the full command with Mac administrator permission and verify ordinary Mac apps without proxy settings.

Completion indicators:

- `./jam-usb-internet app-check` passes.
- Full `system` mode runs `app-check` internally before declaring success.
- Failure exits through cleanup instead of leaving DNS or routes behind.

Fallback rule:

- Normal Mac internet is checked before starting TUN.
- If Mac Wi-Fi internet works, TUN is not started.
- Use `--force-tun` only to intentionally test the USB path while Mac Wi-Fi is still working.
