# Implementation Review

Date: 2026-05-29

## Review Scope

Files reviewed:

- `jam-usb-internet`
- `adb-socks-proxy.py`
- `SYSTEM_TETHERING_SPEC.md`
- stage documents
- relay and Mac system skeleton directories

## Findings

### Finding 1: System proxy is not a system network substitute

Severity: high

User feedback showed that Wi-Fi on but disconnected does not make system proxy mode sufficient. This confirms that `proxy` mode is not a Mac-wide internet solution.

Repair:

- Keep `browser` mode for field fallback.
- Specify `system` mode as TUN-based.
- Avoid claiming that system SOCKS equals full Mac networking.

### Finding 2: Native RNDIS path is low-leverage on this Mac

Severity: high

The phone can expose `rndis,adb`, but macOS does not expose a usable network service.

Repair:

- `connect` remains available but is not the default path.
- Future work moves to relay + TUN.

### Finding 3: Per-connection `adb shell nc` does not scale

Severity: high

It can prove browser connectivity but is not appropriate for Mac-wide traffic.

Repair:

- Stage 2 requires a persistent Android relay.
- Stage 3 cannot begin until relay is validated with `curl --socks5-hostname`.

### Finding 4: Stage 1 must not mutate routes

Severity: medium

Jumping directly into TUN routing before relay proof risks hard-to-debug network state.

Repair:

- Stage 1 commands only inspect, upload, start, stop, and forward.
- `system` is enabled only after relay proof and still offers `--check-only` before privileged routing.

## Verification Performed

```zsh
zsh -n jam-usb-internet
python3 -m py_compile adb-socks-proxy.py
./jam-usb-internet --help
./jam-usb-internet relay-install --timeout 3
./jam-usb-internet system --mobile-only --check-only --timeout 5
```

Observed result:

```text
ADB connected: samsung SM-N960N, Android 10 / SDK 29
Detected Android ABI: arm64-v8a
Relay health check succeeded through 127.0.0.1:18080
System mode check passed.
```

This is the expected state after the relay and TUN preflight work.

## Next Repair Target

Completed:

```zsh
curl --socks5-hostname 127.0.0.1:18080 https://example.com
./jam-usb-internet system --mobile-only --check-only --timeout 5
```

through `adb forward`, without Chrome-specific proxy flags.

Next repair target:

Run full TUN mode with administrator permission:

```zsh
./jam-usb-internet system --mobile-only
```

Then verify ordinary Mac commands without proxy flags:

```zsh
curl https://example.com
git ls-remote https://github.com/git/git.git HEAD
```

## Review Pass 3: macOS TUN Interface Name

Observed failure:

```text
FATAL start inbound/tun[tun-in]: configure tun interface: bad tun name: jamusb0
```

Repair:

- Removed `interface_name: "jamusb0"` from `configs/sing-box.template.json`.
- Let macOS and sing-box allocate a valid `utunX` interface automatically.

Expected next result:

- `sing-box` should pass the TUN interface creation step.
- If another failure appears, it should be a later routing/DNS/capture issue rather than TUN name creation.

## Review Pass 4: Android Relay DNS Resolver

Observed failure:

```text
lookup example.com on [::1]:53: read: connection refused
```

Repair:

- Added a custom resolver inside `android-relay/cmd/knock-relay/main.go`.
- The relay now resolves domain targets through external DNS servers instead of Android shell's unusable `[::1]:53` resolver path.
- Rebuilt `android-relay/bin/arm64-v8a/knock-relay`.

Verification:

```zsh
gofmt -w android-relay/cmd/knock-relay/main.go
go test ./...
./android-relay/build.sh
zsh -n jam-usb-internet
sing-box check -c configs/sing-box.template.json
./jam-usb-internet system --mobile-only --check-only --timeout 5
```

Observed result:

```text
Relay health check succeeded through 127.0.0.1:18080
System mode check passed.
```

Remaining proof point:

- User-run full TUN mode with administrator permission.

## Review Pass 5: Disconnected Wi-Fi Route and DNS

Observed failure:

```text
network: missing default interface
inbound/tun[tun-in]: started at utun6
sing-box started
```

Repair:

- Stop previous `sing-box` instances before full start to avoid multiple `utun` routes.
- Run `sing-box` under script supervision so the script can repair routes after TUN creation.
- Add manual split routes to `172.19.0.1` after the TUN gateway appears.
- Add local DNS listener on `127.0.0.1:53` and `hijack-dns` routing in the sing-box config.
- Temporarily set macOS DNS to `127.0.0.1` and restore previous DNS settings on stop.

Verification:

```zsh
zsh -n jam-usb-internet
sing-box check -c configs/sing-box.template.json
./jam-usb-internet system --mobile-only --check-only --timeout 5
./jam-usb-internet system-status
```

Observed result:

```text
Relay health check succeeded through 127.0.0.1:18080
System mode check passed.
Processes: none
ADB forwards: none
Android relay process: not running
```

## Review Pass 6: Wi-Fi Recovery Must Be Fail-Closed

Observed failure:

- After a failed system-mode run, normal Wi-Fi had a route but DNS resolution timed out.
- `sing-box` and Android relay were not running.
- The network service DNS had been left pointing at local DNS, while no local DNS server was alive.

Root cause:

- The prototype changed macOS DNS before proving that local DNS was actually answering.
- DNS restore ignored failures and removed the backup even if restoration did not truly recover the service.
- A later run could save already-stale `127.0.0.1` DNS as the "previous" state.

Repairs:

- Restore logic now detects stale local-only DNS and resets it to DHCP/empty.
- DNS restore keeps its backup if any service fails to restore.
- Full `system` mode starts `sing-box` first, waits for the TUN gateway, installs routes, and checks `nslookup example.com 127.0.0.1` before changing macOS DNS.
- If local DNS does not answer, the tool stops and refuses to change macOS DNS.

Recovery verification:

```text
Wi-Fi DNS: DHCP/empty
scutil DNS: 168.126.63.1, 168.126.63.2 on en0
route to 1.1.1.1: default via en0
nslookup example.com: OK
curl -4I https://example.com: HTTP/2 200
processes: none
```

## Review Pass 7: App Completion Indicators and UDP Containment

User completion target:

- Chrome web traffic works.
- Discord basic connectivity works.
- KakaoTalk basic connectivity works.
- git over HTTPS works.
- Normal Mac Wi-Fi still works after stop/recovery.

Self-critique:

- A generic `curl example.com` is too weak as a completion signal.
- Android relay supports SOCKS5 CONNECT only, so UDP/QUIC flowing to the relay causes failures such as `only CONNECT is supported`.
- Discord voice/video should not be promised until a UDP strategy exists.

Repairs:

- Added `app-check`.
- Added `system-recover` as a strong recovery command and wired the double-click stop command to it.
- Full `system` mode now runs app connectivity checks after DNS is switched; if checks fail, it cleans up.
- Updated sing-box route rules to hijack traffic from the local DNS inbound and reject remaining UDP so apps fall back to TCP where possible.

Verification:

```text
zsh -n jam-usb-internet: OK
sing-box check -c configs/sing-box.template.json: OK
go test ./...: OK
app-check on normal Wi-Fi: OK
system --mobile-only --check-only --timeout 5: OK
system-recover: OK
```

## Review Pass 8: Mac Wi-Fi Must Win

Observed failure matrix:

- Mac Wi-Fi connected should keep working even if Galaxy Wi-Fi/LTE are off.
- Mac Wi-Fi unavailable should use the Galaxy USB path if the phone has either Wi-Fi or LTE internet.
- The prototype violated this by installing a full split-route TUN whenever system mode started, so phone failure could break otherwise healthy Mac Wi-Fi.

Self-critique:

- `system` was implemented as a forced route takeover, not as a fallback path.
- `system-recover` ran long app checks, which is wrong for a panic-button command.
- DNS backup lines were saved with literal `\t`, causing restore parsing warnings.

Repairs:

- `system` now checks normal Mac internet first. If it works, USB TUN is not started.
- `--force-tun` was added for deliberate USB-path testing only.
- `Galaxy USB Internet.command` now calls `system`, not `system --mobile-only`.
- While TUN is active, a phone-relay health monitor stops TUN if the phone path fails, allowing normal Mac networking to recover.
- `system-recover` now performs fast recovery checks only; detailed app checks live in `app-check`.
- DNS backup save/restore was repaired to handle both proper tab-separated rows and older literal `\t` rows.

Verification:

```text
Mac Wi-Fi working + ./jam-usb-internet system:
  Normal Mac internet is already working. USB TUN was not started.
  no sing-box process
  no ADB forward
  DNS remains DHCP/empty
  route to 1.1.1.1 remains en0

system --check-only:
  relay health check OK
  sing-box config OK

system-recover:
  completes quickly
  backup removed after successful parse
  normal app-check OK
```
