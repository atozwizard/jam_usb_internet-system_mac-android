# Jam USB Internet: System Tethering Specification

Date: 2026-05-29
Target device pair: macOS 26.5 arm64 MacBook + Samsung Galaxy Note 9 Android 10
Current MVP state: `browser` mode works through ADB-backed SOCKS for a dedicated Chrome window.
Current system prototype state: Android relay + sing-box TUN preflight passes; full privileged TUN run is ready for user-side validation.

## 1. Objective

Build a personal-use tool that lets the MacBook use the Galaxy Note 9 cellular network over USB when Wi-Fi/Bluetooth are unavailable or unreliable.

The final target is not browser-only access. The target is Mac-wide internet availability for ordinary apps:

- browsers
- terminal tools: `curl`, `ssh`, `git`, package managers
- messengers and productivity apps that use TCP/TLS
- DNS resolution for those apps
- graceful start/stop and cleanup

The first production-quality system target is TCP + DNS over a Mac virtual network path. UDP and VPN-sensitive apps are later-stage work.

## 2. Official Capability Boundaries

This design is based on official platform capabilities, combined into a custom workflow.

Apple platform capabilities:

- `NEPacketTunnelProvider` can provide a packet tunnel on macOS.
- `NEPacketTunnelFlow` can read and write IP packets for a packet tunnel.
- `NEPacketTunnelNetworkSettings` and route settings can direct traffic through the tunnel.
- Source references:
  - https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
  - https://developer.apple.com/documentation/networkextension/nepackettunnelflow
  - https://developer.apple.com/documentation/networkextension/nepackettunnelnetworksettings

Android and ADB capabilities:

- ADB supports USB-attached device discovery, `adb shell`, `adb push`, and port forwarding.
- These are enough to copy a temporary relay executable to `/data/local/tmp`, run it, and connect to it from the Mac through USB.
- Source reference:
  - https://developer.android.com/tools/adb

Android VPN capability:

- Android `VpnService` can create a VPN-style tunnel inside Android.
- This is not required for the preferred design, because the Mac will own the virtual network interface and the phone will act as an outbound relay.
- It remains a fallback if we later need an APK-based relay with richer Android network binding.
- Source reference:
  - https://developer.android.com/reference/android/net/VpnService

Boundary conclusion:

The overall system is theoretically feasible inside official platform boundaries. Apple does not provide a direct API for "use Android ADB as a network interface"; we create that by combining a Mac packet tunnel with an Android-side relay reachable over official ADB transport.

## 3. Current Findings

Native USB tethering path:

- Note 9 can switch to `rndis,adb`.
- Android side exposes `rndis0`.
- macOS 26.5 arm64 sees `SAMSUNG_Android` over USB.
- macOS does not expose the Note 9 RNDIS function as a usable network service.
- Conclusion: native USB tethering is not a reliable path on this Mac.

Current successful path:

- ADB can reach the phone over USB.
- ADB-backed local SOCKS can give Chrome internet access.
- This proves the phone can perform outbound internet traffic while connected by USB.
- File Transfer / Android Auto USB mode keeps ADB stable for the relay path.

Current limitation:

- macOS service-level SOCKS proxy only helps apps that honor system proxy settings and only when macOS considers the relevant network service usable.
- If Wi-Fi is on but disconnected, system proxy behavior is not enough for Mac-wide connectivity.
- Android USB tethering mode is not the preferred state for this design because it can switch USB functions and break ADB visibility.

## 4. Target Architecture

### 4.1 Prototype Architecture

```text
Mac app / CLI
  |
  | starts and supervises
  v
Mac TUN engine: sing-box or tun2socks
  |
  | SOCKS5 outbound to localhost
  v
ADB forward: 127.0.0.1:<mac_relay_port> -> device tcp:<device_relay_port>
  |
  v
Android relay: /data/local/tmp/knock-relay
  |
  | outbound TCP/DNS via phone cellular network
  v
Internet
```

### 4.2 Product Architecture

```text
macOS NetworkExtension Packet Tunnel
  |
  | packet flow
  v
Mac relay client
  |
  | ADB USB transport
  v
Android relay process or APK
  |
  v
Cellular internet
```

The prototype may use `sing-box` or `tun2socks` because it is faster to validate. The productized version should use `NetworkExtension` for a cleaner macOS permission and lifecycle model.

## 5. Android Relay Design

Preferred relay type:

- Temporary executable for Android arm64.
- Uploaded by the Mac tool with `adb push`.
- Stored at `/data/local/tmp/knock-relay`.
- Executed with `adb shell chmod +x` and `adb shell`.
- No APK install.
- No root.
- No persistent service.
- Removed by `jam-usb-internet relay-clean` or on demand.

Relay responsibilities:

- Listen on `127.0.0.1:<device_relay_port>` inside Android.
- Speak SOCKS5 initially.
- For each CONNECT request, open an outbound TCP connection from Android.
- Relay bytes bidirectionally.
- Bind outbound traffic to the phone default network initially.
- Later optional enhancement: explicitly bind to cellular via Android APIs, likely requiring APK or privileged context.

Initial relay protocol:

- SOCKS5 no-auth.
- CONNECT command required.
- IPv4, IPv6, and domain names supported.
- UDP ASSOCIATE not supported in Stage 2.

Rationale:

- If the phone relay is a SOCKS5 server, Mac-side TUN engines can point to it through `adb forward`.
- This avoids spawning `adb shell nc` per connection.
- It reduces latency, connection churn, and ADB process contention.

## 6. Mac System Routing Design

Prototype path:

- Generate a local TUN config for `sing-box` or `tun2socks`.
- Route `0.0.0.0/0` and eventually `::/0` through the TUN engine.
- DNS is handled by the TUN engine or local DNS proxy.
- Outbound proxy target is `socks5://127.0.0.1:<mac_relay_port>`.

Expected command:

```zsh
./jam-usb-internet system
```

Expected stop command:

```zsh
./jam-usb-internet system-stop
```

Required cleanup:

- Stop TUN engine.
- Remove generated config state.
- Remove `adb forward`.
- Kill Android relay process.
- Restore DNS/proxy/routing settings changed by the tool.
- Remove any manual split routes added when no macOS default interface exists.

## 7. Command Specification

Existing commands:

- `browser --mobile-only`
  - Opens a dedicated Chrome instance through a SOCKS proxy.
  - Used as field-safe fallback and connectivity proof.

- `proxy --mobile-only`
  - Starts local SOCKS and optionally configures macOS service-level proxy.
  - Useful only for apps that honor system proxy settings.

- `connect --mobile-only`
  - Tries native RNDIS USB tethering.
  - Not recommended on this target Mac because it can disrupt ADB.

Planned commands:

- `relay-install`
  - Detect Android ABI.
  - Select relay binary.
  - Push to `/data/local/tmp/knock-relay`.
  - `chmod +x`.
  - Verify checksum or version.

- `relay-start`
  - Start relay on Android.
  - Create `adb forward`.
  - Verify SOCKS handshake through forwarded port.

- `relay-stop`
  - Stop Android relay.
  - Remove ADB forward.

- `relay-clean`
  - Stop relay.
  - Remove `/data/local/tmp/knock-relay`.

- `system`
  - Run `relay-install` if needed.
  - Run `relay-start`.
  - Start TUN engine.
  - Verify DNS and HTTPS.
  - Keep foreground process alive for supervision.

- `system-stop`
  - Stop TUN engine.
  - Stop relay.
  - Restore local settings.

- `doctor --deep`
  - Check ADB.
  - Check USB device.
  - Check Android ABI.
  - Check cellular connectivity.
  - Check relay binary availability.
  - Check TUN engine availability.
  - Check DNS route.

## 8. Staged Roadmap

### Stage 0: Stabilize Current MVP

Status: implemented as fallback

Deliverables:

- Keep `browser` mode as reliable field fallback.
- Make `proxy-stop` idempotent.
- Avoid `connect` unless explicitly requested.
- Document observed RNDIS limitation.

Acceptance criteria:

- `browser --mobile-only` opens Chrome through the phone.
- Closing the terminal stops the proxy.
- `proxy-stop` leaves macOS SOCKS disabled unless it was user-configured before.

### Stage 1: Relay Skeleton

Status: implemented

Deliverables:

- `android-relay/` source skeleton.
- Relay protocol test cases.
- Android ABI detection in `jam-usb-internet`.
- `relay-install`, `relay-start`, `relay-stop`, `relay-clean` commands.

Acceptance criteria:

- Tool can identify `arm64-v8a` on the Note 9.
- Tool can push the relay binary.
- Tool can create and remove `adb forward`.
- No system routing changes yet.

Current verification:

```text
relay-install verified:
  device: samsung SM-N960N, Android 10 / SDK 29
  ABI: arm64-v8a
  relay binary: android-relay/bin/arm64-v8a/knock-relay
```

Stage 1 is complete.

### Stage 2: Android SOCKS Relay

Status: implemented for Android arm64 and validated through ADB forward

Deliverables:

- Static Android arm64 relay binary.
- SOCKS5 CONNECT support.
- TCP bidirectional relay.
- Local integration test through `adb forward`.

Acceptance criteria:

```zsh
curl --socks5-hostname 127.0.0.1:<mac_relay_port> https://example.com
```

works while Mac Wi-Fi is disconnected, as long as ADB and cellular are available.

Current verification:

```text
android-relay/bin/arm64-v8a/knock-relay built successfully.
relay-install pushed it to /data/local/tmp/knock-relay.
relay-start created adb forward tcp:18080 -> tcp:18080.
curl --socks5-hostname 127.0.0.1:18080 http://example.com succeeded.
curl --socks5-hostname 127.0.0.1:18080 https://example.com succeeded.
system --mobile-only --check-only revalidated HTTPS after Android relay DNS repair.
```

### Stage 3: Mac TUN Prototype

Status: implemented as first `sing-box` prototype path; privileged full run still needs user-driven test

Deliverables:

- Generated `sing-box` or `tun2socks` config.
- `system` command starts relay and TUN engine.
- `system-stop` restores state.
- TCP and DNS validated.

Acceptance criteria:

- With Mac Wi-Fi disconnected, these work:

```zsh
curl https://example.com
git ls-remote https://github.com/git/git.git HEAD
python3 -m pip index versions requests
```

The exact package-manager test may change to avoid side effects.

Current verification:

```text
sing-box 1.13.12 installed.
configs/sing-box.template.json validates with sing-box check.
system --mobile-only --check-only passed:
  relay install
  relay start
  HTTPS health check through 127.0.0.1:18080
  generated config validation
  relay cleanup
```

Runtime repair:

- Before full start, stop any previous `sing-box` instance that used this config.
- Start `sing-box` under script supervision instead of handing over the foreground immediately.
- Wait for the TUN gateway address `172.19.0.1`.
- Add split IPv4 routes manually if `sing-box` cannot infer a macOS default interface.
- Temporarily set macOS DNS servers to `127.0.0.1`.
- Add a local `direct` DNS inbound on `127.0.0.1:53` and route DNS packets with `hijack-dns`.
- Restore DNS settings and remove manual routes on stop.

Full TUN run requires administrator permission:

```zsh
./jam-usb-internet system --mobile-only
```

### Stage 4: Reliability and Recovery

Status: planned

Deliverables:

- Detect ADB disconnect and retry.
- Detect relay death and restart.
- Detect TUN engine death and stop cleanly.
- State directory lock file to prevent double starts.
- Structured logs.

Acceptance criteria:

- USB unplug produces clear state and cleanup.
- Replug can recover without rebooting the Mac or phone.
- Re-running `system` does not stack duplicate routes or proxy state.

### Stage 5: UDP and App Compatibility

Status: planned

Deliverables:

- UDP strategy decision.
- DNS over TCP or DoH stabilization.
- QUIC policy: block, downgrade, or relay.
- Compatibility matrix.

Acceptance criteria:

- DNS is reliable.
- Common TCP apps work.
- UDP limitations are explicit and testable.

### Stage 6: Native macOS Packet Tunnel

Status: later

Deliverables:

- Xcode project or Swift Package for a NetworkExtension host app.
- Packet tunnel provider.
- User-approved VPN profile.
- ADB relay client integration.

Acceptance criteria:

- User can start/stop from a Mac app.
- No external TUN engine dependency.
- Clean permission lifecycle.

## 9. Test Matrix

Connectivity tests:

- ADB device authorized.
- Android cellular ping works.
- Relay SOCKS handshake works.
- HTTP through relay works.
- HTTPS through relay works.
- DNS through system path works.
- Mac default route is restored after stop.

Network state tests:

- Wi-Fi connected.
- Wi-Fi on but disconnected.
- Wi-Fi off.
- USB unplug during active connection.
- Phone screen locked.
- Phone rebooted.

Traffic tests:

- `curl`
- Chrome/web HTTPS after system mode
- `git`
- Discord gateway HTTPS/TCP
- Kakao HTTPS/TCP
- package-manager metadata request
- Slack or similar TCP-heavy desktop app

## 10. Risks and Mitigations

Risk: ADB is not a high-performance network transport.

- Mitigation: keep relay persistent, avoid per-connection `adb shell nc`, batch diagnostics, and set expectations.

Risk: macOS TUN setup requires elevated permission.

- Mitigation: use explicit `sudo` boundary in Stage 3; productize with NetworkExtension in Stage 6.

Risk: Android process is killed by power management.

- Mitigation: foreground ADB shell supervision; automatic restart; keep phone charging over USB.

Risk: UDP-based apps fail.

- Mitigation: TCP/DNS first; document UDP matrix; add UDP only after core stability.

Risk: DNS leaks or fails when Wi-Fi is disconnected.

- Mitigation: route DNS through TUN engine; prefer DoH or DNS-over-TCP through relay.

Risk: `connect` mode disrupts ADB by changing USB functions.

- Mitigation: keep `connect` as explicit legacy/native test command; default to `browser` and later `system`.

## 11. Self-Critique

The original plan overvalued native USB tethering. On this Mac, RNDIS is visible only as a USB device, not as a macOS network service. Continuing to invest there is low leverage.

The `proxy` mode is useful but insufficient for the user's stated goal. It depends on app proxy behavior and macOS service state. It should remain a fallback, not the main path.

The `browser` mode is successful but should not be mistaken for system networking. It proves relay feasibility only.

The next serious risk is building too much custom networking at once. The staged plan must force proof points:

1. persistent Android SOCKS relay
2. forwarded relay works with `curl --socks5-hostname`
3. TUN routes ordinary `curl` without app proxy settings
4. only then broaden app coverage

## 12. Self-Repair Decisions

Decision 1:

- Stop treating `connect` as the primary command.
- Keep it for native tethering experiments only.

Decision 2:

- Make `browser` the field-safe fallback.
- It avoids macOS disconnected-service proxy behavior.

Decision 3:

- Do not build the NetworkExtension first.
- Build `sing-box` or `tun2socks` prototype first to prove routing and relay.

Decision 4:

- Do not rely on `adb shell nc` per connection for system mode.
- Build a persistent relay binary and use `adb forward`.

Decision 5:

- Treat UDP as a later compatibility feature.
- TCP + DNS is the first complete system milestone.

## 13. Immediate Next Work Items

1. Run full `system --mobile-only` from the user Terminal and enter the Mac admin password.
2. Verify ordinary Mac commands without per-app proxy flags:
   - `curl https://example.com`
   - `git ls-remote https://github.com/git/git.git HEAD`
3. Add deep doctor checks for:
   - Android ABI
   - ADB forward support
   - available TUN engine
   - relay DNS path
4. Add relay protocol tests for domain, IPv4, and IPv6 CONNECT requests.
5. Improve recovery if ADB disconnects while system mode is running.

## 14. Review Pass 1: Implementation Feedback Incorporated

Observed user feedback:

- Browser-only access is not enough.
- Wi-Fi on but disconnected breaks system-proxy expectations.
- The final objective is Mac-wide internet, not web surfing only.

Corrections made:

- `browser` mode remains a fallback, not the final architecture.
- `system` mode is specified as the target.
- Stage 1 relay lifecycle commands were added without changing system routes.
- `connect` is explicitly de-emphasized because it can disturb ADB by switching USB functions.
- The roadmap now requires a persistent Android relay before attempting TUN routing.

Remaining design debt:

- Full TUN run still needs live admin-permission validation.
- UDP behavior is intentionally unresolved.
- macOS NetworkExtension productization is deferred until the prototype path is proven.

## 15. Review Pass 2: Relay and TUN Prototype Feedback

Self-critique:

- The relay plan would have been too theoretical without a real binary and ADB-forward test.
- The `system` command would be unsafe if it jumped straight to route mutation without a dry run.
- The sing-box template initially used deprecated fields, which would have failed at runtime.

Repairs:

- Built a real Android arm64 relay in Go.
- Validated HTTP and HTTPS through the relay using `curl --socks5-hostname`.
- Added `system --check-only` to verify relay and config without starting privileged TUN mode.
- Migrated the sing-box DNS config to the non-legacy server format and removed deprecated inbound sniffing.
- Removed the fixed `interface_name` from the sing-box TUN template after macOS rejected `jamusb0` with `bad tun name`; macOS should allocate a valid `utunX` interface.

Next unresolved proof point:

- Run full `system --mobile-only` with administrator permission and verify ordinary Mac commands without per-app proxy settings.

## 16. Review Pass 3: Android Relay DNS Repair

Observed failure:

```text
connect example.com:443: dial tcp: lookup example.com on [::1]:53: read: connection refused
```

Self-critique:

- The relay depended on Go's default resolver inside Android shell.
- On this Note 9 environment, that resolver attempted `[::1]:53`, which is not a usable DNS server.
- The earlier relay validation was too narrow because it did not preserve this as an explicit regression check.

Repairs:

- Added a custom Go resolver in `knock-relay`.
- DNS lookups now use known external DNS servers through the phone's own outbound network path.
- Domain results are ordered IPv4-first before dialing, which avoids avoidable IPv6 failures on mobile networks that do not provide stable IPv6.
- Rebuilt and uploaded the Android arm64 relay.
- Re-ran `system --mobile-only --check-only --timeout 5`; relay health check and sing-box config validation passed.

Status:

- The temporary relay upload to `/data/local/tmp/knock-relay` is automatic and working.
- The current user-facing next step is full privileged TUN validation through `Galaxy USB Internet.command` or `./jam-usb-internet system --mobile-only`.

## 17. Review Pass 4: macOS TUN Route and DNS Repair

Observed failure:

```text
ERROR[0000] network: missing default interface
INFO[0000] inbound/tun[tun-in]: started at utun6
INFO[0000] sing-box started
```

User result:

- Galaxy LTE on, Mac Wi-Fi on but not connected: no internet.
- Galaxy LTE on, Mac Wi-Fi off: no internet.

Self-critique:

- The first TUN prototype assumed `sing-box` could always infer a macOS default interface.
- The tool allowed repeated starts, which produced multiple `sing-box` processes and mismatched `utun` routes.
- DNS was under-specified: when Wi-Fi is disconnected, macOS may not have a usable resolver even if TUN routes exist.

Repairs:

- Added pre-start cleanup for old `sing-box`, ADB forward, and Android relay state.
- Changed `system` mode to supervise `sing-box` in the background after `sudo -v`.
- Added manual split-route installation toward `172.19.0.1` after the TUN address appears.
- Added temporary macOS DNS override to `127.0.0.1`.
- Added sing-box `direct` DNS inbound on `127.0.0.1:53` plus `hijack-dns` route action.
- Added DNS and route restoration to `system-stop` and process-exit cleanup.

Remaining proof point:

- User-run full system mode again and test:
  - `curl https://example.com`
  - `dig example.com` or `nslookup example.com`
  - one non-Chrome app.

## 18. Review Pass 5: Fail-Closed Wi-Fi Recovery

Observed failure:

- Normal Wi-Fi stopped resolving names after system-mode experiments.
- The route to the internet was present, but DNS queries timed out.
- No `sing-box`, relay, or ADB forward was active.

Self-critique:

- The previous design allowed DNS mutation before proving the replacement DNS listener was working.
- Restore code hid failures and could delete the backup too early.
- The tool needed a recovery path for "backup missing but DNS is clearly stale local DNS."

Repairs:

- `system-stop` now detects stale local-only DNS and resets it to DHCP/empty.
- DNS restore now keeps the backup if any service fails to restore.
- `system` now starts `sing-box`, waits for TUN, installs routes, then verifies `127.0.0.1` DNS before changing macOS DNS.
- If that DNS check fails, the tool cleans up and leaves Wi-Fi DNS unchanged.

Current safe baseline:

```text
Wi-Fi DNS: DHCP/empty
scutil DNS: 168.126.63.1, 168.126.63.2
default route: en0 via 172.30.1.254
curl https://example.com: OK
```

## 19. Review Pass 6: Completion Criteria and UDP Containment

Completion target:

- Chrome-style HTTPS works.
- Discord gateway HTTPS/TCP works.
- Kakao HTTPS/TCP works.
- git over HTTPS works.
- `system-stop` or `system-recover` returns normal Wi-Fi to a working state.

Self-critique:

- The relay is TCP-only. Allowing arbitrary UDP to flow toward a SOCKS5 CONNECT-only Android relay creates noisy failures and unreliable app behavior.
- App compatibility needs explicit checks instead of relying on a single `curl example.com`.

Repairs:

- Added `app-check` for Chrome/web, Discord, Kakao, and git indicators.
- Added `system-recover` as a stronger panic-button recovery path.
- Updated `Galaxy System Stop.command` to call `system-recover`.
- Added sing-box route rules:
  - local DNS inbound is hijacked into sing-box DNS
  - DNS protocol traffic is hijacked
  - other UDP is rejected so QUIC-capable apps can fall back to TCP
- Full `system` now runs app checks after DNS switch and cleans up if any indicator fails.

Known boundary:

- Discord text/gateway connectivity is in scope for this TCP/DNS milestone.
- Discord voice/video and other UDP-native features require a later UDP relay or a Mac-side UDP-over-TCP shim.

## 20. Review Pass 7: Fallback Semantics

Required behavior:

- If Mac Wi-Fi has working internet, Mac traffic must continue to use Mac Wi-Fi regardless of Galaxy Wi-Fi/LTE state.
- If Mac Wi-Fi is off or unassociated and the Galaxy has Wi-Fi or LTE internet, USB should provide Mac-wide TCP/DNS internet.
- If the phone path dies while USB TUN is active, the tool should stop TUN and restore normal Mac networking.

Self-critique:

- The previous design treated USB as a forced primary route.
- That made phone connectivity failures more damaging than the original problem.

Repairs:

- `system` now behaves as fallback by default:
  - pre-clean stale state
  - verify normal Mac internet
  - if normal internet works, do not start TUN
  - otherwise start USB TUN
- Added `--force-tun` for deliberate testing only.
- Added active phone relay monitoring while TUN runs.
- If relay health fails twice, the tool stops `sing-box`; cleanup restores routes and DNS.
