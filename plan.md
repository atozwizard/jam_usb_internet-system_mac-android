# jam_usb_internet-system_mac-android Plan

Date: 2026-05-30

## Table of Contents

1. Planning Principles
2. Current Architecture Plan
3. Stage 0: Baseline and Safety
4. Stage 1: Native USB Tethering Investigation
5. Stage 2: Browser/Proxy Fallback
6. Stage 3: Android Relay
7. Stage 4: Mac TUN System Mode
8. Stage 5: Route, DNS, and Reachability Reliability
9. Stage 6: Stop and Recovery
10. Stage 7: App Compatibility
11. Stage 8: Packaging
12. Stage 9: Git and GitHub Project Hygiene
13. Current Immediate Work Queue
14. Validation Matrix
15. Future Work

## 1. Planning Principles

1. Preserve normal Mac Wi-Fi first.
2. Never leave stale local DNS as the only resolver.
3. Never assume Android USB tethering equals a Mac network interface.
4. Verify lower layers before touching higher-risk route/DNS state.
5. Prefer explicit failure over silent partial success.
6. Treat KakaoTalk as an app-level reachability test, not merely a TCP test.
7. Delay packaging until the system behavior is stable.
8. Track all meaningful changes in git from this point forward.

## 2. Current Architecture Plan

Primary path:

```text
Mac apps
  -> macOS DNS / routing / reachability
  -> sing-box TUN
  -> local SOCKS outbound
  -> 127.0.0.1:18080
  -> adb forward over USB
  -> Android relay /data/local/tmp/knock-relay
  -> Galaxy Wi-Fi or LTE
  -> Internet
```

Control path:

```text
jam-usb-internet system
  -> preclean old state
  -> verify normal Mac internet
  -> install/start Android relay
  -> verify relay app endpoints
  -> generate sing-box config
  -> start TUN
  -> install default route + split routes
  -> install temporary DNS resolver
  -> run app-check
  -> monitor relay
```

Stop path:

```text
jam-usb-internet system-stop
  -> restore default route
  -> delete split routes
  -> remove temporary DNS resolver
  -> restore service DNS if needed
  -> stop sing-box
  -> stop Android relay
  -> remove adb forward
```

Recovery path:

```text
jam-usb-internet system-recover
  -> stronger stop
  -> stale DNS repair
  -> proxy cleanup
  -> connectivity check
```

## 3. Stage 0: Baseline and Safety

### 3.1 Goals

- Establish current Mac and Android environment.
- Ensure the Mac can recover to normal Wi-Fi.
- Provide diagnostics.

### 3.2 Deliverables

- `doctor`
- `status`
- `system-status`
- `app-check`
- `system-recover`

### 3.3 Current Status

Implemented.

### 3.4 Remaining Work

- Add more structured logs after route changes.
- Include route backup state in `system-status`.

## 4. Stage 1: Native USB Tethering Investigation

### 4.1 Goals

Determine whether Galaxy Note 9 native USB tethering can appear as a Mac network interface.

### 4.2 Findings

Native path appears blocked:

- No usable Android USB network interface appears on macOS.
- Google Android documentation states Mac computers cannot tether with Android by USB.

### 4.3 Deliverables

- `reference/usb-tethering-routing-reference.md`
- Native path documented as non-primary.

### 4.4 Current Status

Complete for current host/device combination.

### 4.5 Remaining Work

- Optional future hardware comparison with a phone or adapter exposing CDC-NCM.

## 5. Stage 2: Browser/Proxy Fallback

### 5.1 Goals

Prove that ADB can carry internet traffic through USB even if macOS does not expose Android as a network card.

### 5.2 Deliverables

- `adb-socks-proxy.py`
- `browser`
- `proxy`
- `proxy-stop`
- `Galaxy Browser Fallback.command`

### 5.3 Current Status

Implemented.

### 5.4 Limitations

- Browser-only mode is not sufficient.
- System proxy mode is not reliable when no active Mac network service exists.
- Apps that ignore macOS proxy settings may not work.

## 6. Stage 3: Android Relay

### 6.1 Goals

Replace per-connection shell/netcat proxy with a persistent Android relay.

### 6.2 Deliverables

- Go relay source:

  ```text
  android-relay/cmd/knock-relay/main.go
  ```

- Built binary:

  ```text
  android-relay/bin/arm64-v8a/knock-relay
  ```

- Relay commands:
  - `relay-install`
  - `relay-start`
  - `relay-stop`
  - `relay-clean`

### 6.3 Current Status

Implemented and validated by `system --check-only`.

### 6.4 Reliability Improvement Already Applied

Relay DNS now resolves through DoH over HTTPS first.

Why:

- Direct UDP DNS failed on Android in observed runs.
- Galaxy internet was working, but relay DNS resolution failed.

### 6.5 Remaining Work

- Add relay version output to `system-status`.
- Add structured relay errors for DNS fallback path.
- Consider UDP relay later.

## 7. Stage 4: Mac TUN System Mode

### 7.1 Goals

Make Mac-wide TCP/DNS traffic flow through Android relay.

### 7.2 Deliverables

- `system`
- `system-stop`
- `system-recover`
- `configs/sing-box.template.json`

### 7.3 Current Behavior

`system` currently:

1. Precleans old system-mode state.
2. Exits early if normal Mac internet works.
3. Installs and starts Android relay.
4. Runs relay app endpoint checks.
5. Starts `sing-box`.
6. Waits for TUN gateway:

   ```text
   172.19.0.1
   ```

7. Installs split IPv4 routes.
8. Attempts temporary default route.
9. Verifies route to `1.1.1.1`.
10. Installs temporary DNS resolver.
11. Runs a startup connectivity check.

Important distinction:

- `system` startup must keep a usable TCP/DNS tunnel alive when Chrome, Discord, and git checks pass.
- `app-check` remains the strict completion check and includes KakaoTalk/macOS reachability.

### 7.4 Current Block

Failure in target condition:

```text
Mac Wi-Fi: off
Galaxy Wi-Fi: connected
```

Observed:

```text
[warn] Temporary default route verification failed for utun4: route: writing to routing socket: not in table
[ok] IPv4 route verification passed through utun4.
```

Interpretation:

- Split routes can send real traffic through TUN.
- macOS default route / reachability path does not verify against `utun4`.
- KakaoTalk likely remains offline because reachability does not see the path as online.
- The previous startup logic was too strict because it cleaned up after a default-route warning even when split-route TCP/DNS could still work.

### 7.5 Current Patch

Default route installation had already changed from:

```zsh
route change default -interface "$tun_if"
route add default -interface "$tun_if"
```

to:

```zsh
route change default "$TUN_GATEWAY"
route add default "$TUN_GATEWAY"
```

with:

```text
TUN_GATEWAY=172.19.0.1
```

Latest behavior change:

- Default route verification failure is warning-only during `system` startup.
- Split route verification is still mandatory.
- DNS, Chrome/web, Discord, and git checks are still mandatory.
- KakaoTalk/macOS reachability is nonfatal during `system` startup but remains fatal in `app-check`.

Purpose:

- Keep the already-working USB TCP/DNS tunnel alive for real use and further diagnosis.
- Avoid throwing away Chrome/Discord/git connectivity because one reachability layer is incomplete.

### 7.6 Next Validation

Test with Mac Wi-Fi off and Galaxy Wi-Fi connected:

```zsh
./jam-usb-internet system
```

Expected:

```text
[ok] IPv4 route verification passed through utunX.
[ok] DNS works through current macOS resolver.
[ok] Chrome/web HTTPS reachable
[ok] Discord gateway API HTTPS reachable
[ok] git over HTTPS reachable
```

Then:

```zsh
./jam-usb-internet app-check
```

Expected:

```text
[ok] KakaoTalk macOS reachability: talk.kakao.com (Reachable)
```

If `system` stays up but `app-check` fails only at KakaoTalk reachability, the next task is route/reachability repair rather than Android relay repair.

## 8. Stage 5: Route, DNS, and Reachability Reliability

### 8.1 Route Work

Current plan:

- Always back up previous default route before TUN default route changes.
- Use TUN gateway `172.19.0.1` for default route installation.
- Keep split public IPv4 routes for actual traffic coverage.
- Restore previous default route on stop/recover.
- Add diagnostic output when verification fails.
- Do not stop system mode solely because default route verification failed, if split routes and DNS/TCP checks pass.

### 8.2 DNS Work

Current plan:

- Do not permanently change service DNS when avoidable.
- Use temporary dynamic resolver:

  ```text
  State:/Network/Service/jam-usb-internet/DNS
  ```

- Point resolver to:

  ```text
  127.0.0.1
  ```

- Ensure `sing-box` is listening before installing DNS.
- Remove temporary resolver on cleanup.
- Repair stale local service DNS if found.

### 8.3 Reachability Work

Current plan:

- App checks must include macOS reachability, not only TCP.
- KakaoTalk requires:

  ```zsh
  scutil -r talk.kakao.com
  ```

  to return reachable.
- System startup uses reachability as a warning, not a teardown trigger.
- `app-check` uses reachability as a completion gate.

### 8.4 Remaining Work

- Add `route -n get default` output to `system-status`.
- Add default route backup contents to `system-status`.
- Add failure advice when `scutil -r` fails but TCP works.

## 9. Stage 6: Stop and Recovery

### 9.1 Normal Stop

Command:

```zsh
./jam-usb-internet system-stop
```

Must:

- Restore default route.
- Delete split TUN routes.
- Remove dynamic DNS.
- Restore DNS backup if present.
- Stop `sing-box`.
- Stop Android relay.
- Remove ADB forward.

### 9.2 Strong Recovery

Command:

```zsh
./jam-usb-internet system-recover
```

Must:

- Do everything normal stop does.
- Stop SOCKS proxy mode too.
- Repair stale DNS.
- Check normal internet if Wi-Fi is connected.

### 9.3 Documentation

README now includes safe stop rule:

```zsh
./jam-usb-internet system-stop
```

and fallback:

```zsh
./jam-usb-internet system-recover
```

### 9.4 Remaining Work

- Add on/off `.command` naming once behavior is stable.
- Make command windows less scary for non-technical use.

## 10. Stage 7: App Compatibility

### 10.1 Current App Targets

Required:

- Chrome
- Discord
- KakaoTalk
- git

### 10.2 Current Checks

Chrome:

```text
https://www.google.com/generate_204
```

Discord:

```text
https://discord.com/api/v10/gateway
gateway.discord.gg:443
```

Kakao:

```text
https://talk.kakao.com
talk.kakao.com:443
scutil -r talk.kakao.com
```

git:

```text
git ls-remote https://github.com/git/git.git HEAD
```

### 10.3 Current Status

In normal Wi-Fi state:

```text
app-check passes.
```

In Mac Wi-Fi-off target state:

```text
relay checks pass; TUN starts; split routes pass; default route verification can fail.
```

### 10.4 Remaining Work

- Re-test after nonfatal default route patch.
- Confirm system mode remains running when default route verification fails but split routes pass.
- Confirm KakaoTalk app itself can send/receive.
- Confirm Discord text/API path.
- Defer Discord voice/video until UDP strategy exists.

## 11. Stage 8: Packaging

### 11.1 Packaging Boundary

Do not package yet.

Reason:

- System mode still fails in target Mac Wi-Fi-off condition.

### 11.2 First Packaging Step

After completion criteria pass:

- `Galaxy USB Internet.command` becomes explicit On.
- `Galaxy System Stop.command` becomes explicit Off.
- README uses on/off wording.

### 11.3 Later Packaging Step

Create a small macOS `.app` wrapper with:

- Start button
- Stop button
- Status display
- Recovery button

### 11.4 Not Yet Planned in Detail

- LaunchAgent
- Menu bar app
- Code signing
- Notarization

## 12. Stage 9: Git and GitHub Project Hygiene

### 12.1 Repository

Repository name:

```text
jam_usb_internet-system_mac-android
```

### 12.2 Files to Track

Track:

- Shell CLI
- `.command` launchers
- README and project docs
- sing-box config template
- Android relay source
- Android relay build script
- Android relay arm64 binary
- reference notes
- stage notes

Ignore:

- `.DS_Store`
- `.gocache/`
- logs
- temporary files

### 12.3 Initial Commit Plan

Completed initial commit after:

- route patch
- docs
- validation commands
- GitHub repository creation

Initial commit:

```text
961e73a Initial jam USB internet system prototype
```

### 12.4 GitHub Plan

Created GitHub repository:

```text
jam_usb_internet-system_mac-android
```

Repository URL:

```text
https://github.com/atozwizard/jam_usb_internet-system_mac-android
```

Visibility:

```text
PRIVATE
```

Remote:

```text
origin https://github.com/atozwizard/jam_usb_internet-system_mac-android.git
```

Push status:

```zsh
main tracks origin/main
```

### 12.5 Author Identity

GitHub repository ownership and Git commit authorship are separate.

Local Git config is now:

```text
user.name=atozwizard
user.email=251137756+atozwizard@users.noreply.github.com
```

Existing local commits were rewritten so both author and committer use that identity.

Completed publish step after the rewrite:

```zsh
git push --force-with-lease origin main
```

Remote `main` now points to the rewritten author history.

## 13. Current Immediate Work Queue

### 13.1 Code

1. Keep default route installation as gateway `172.19.0.1`.
2. Keep previous default route backup/restore.
3. Treat default route verification failure as warning-only during `system` startup.
4. Keep KakaoTalk reachability strict in `app-check`.
5. Verify syntax and config.

### 13.2 Docs

1. Create `project.md`.
2. Create `plan.md`.
3. Update README with safe stop usage.
4. Keep session logs appended as work continues.

### 13.3 Git

1. Keep local author identity as `atozwizard`.
2. Commit latest route/reachability behavior patch.
3. Push normally after the author-history force push.
4. Verify remote repository metadata.

### 13.4 User Validation

Run with:

```text
Mac Wi-Fi off
Galaxy Wi-Fi connected
USB/ADB connected
```

Command:

```zsh
./jam-usb-internet system
```

## 14. Validation Matrix

### 14.1 Normal Wi-Fi State

Mac Wi-Fi connected:

- `app-check` must pass.
- `system` should not start TUN unless forced.

### 14.2 Mac Wi-Fi Off, Galaxy Wi-Fi Connected

Expected:

- relay check passes.
- TUN starts.
- default route points through `utunX`.
- temporary DNS resolver active.
- app-check passes.
- KakaoTalk app works.

### 14.3 Mac Wi-Fi Off, Galaxy LTE Connected

Expected:

- same as Galaxy Wi-Fi path.
- `--mobile-only` may be used to force phone LTE.

### 14.4 Phone Internet Off, Mac Wi-Fi Connected

Expected:

- normal Mac Wi-Fi remains usable.
- system mode should not break Mac internet.

### 14.5 Phone Internet Off, Mac Wi-Fi Off

Expected:

- relay check fails.
- TUN should not be started or should fail closed.
- cleanup should leave no stale DNS/routes.

## 15. Future Work

### 15.1 UDP Relay

Needed for:

- Discord voice/video
- Some realtime apps

Possible approaches:

- SOCKS5 UDP ASSOCIATE in relay
- sing-box UDP support through relay
- Android VpnService bridge

### 15.2 NetworkExtension

Needed for production-quality Mac behavior:

- Better route/DNS ownership
- Cleaner start/stop lifecycle
- OS-native VPN status

### 15.3 App Packaging

Needed for daily usability:

- No terminal command memorization
- Clear on/off/status
- Safe recovery button

### 15.4 Observability

Needed for debugging:

- Unified log file
- Last failure reason
- Route/DNS snapshots
- App check history

### 15.5 Security Hardening

Needed before sharing broadly:

- Explain USB debugging risk
- Verify relay binary integrity
- Minimize phone-side lifetime
- Clear cleanup path for `/data/local/tmp/knock-relay`
