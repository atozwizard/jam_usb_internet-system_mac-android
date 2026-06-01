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

### 7.4 Resolved Route/Reachability Block

Previous failure in target condition:

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

User validation after the nonfatal route patch:

```text
Mac Wi-Fi off + Galaxy Wi-Fi connected: internet works, KakaoTalk works.
Mac Wi-Fi off + Galaxy LTE connected: initially inconsistent; later Session 15 validation passed for KakaoTalk and app-check.
```

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

### 7.6 Current Validation Status

Validated by user with:

```text
Mac Wi-Fi off
Galaxy Wi-Fi connected
USB/ADB connected
```

Validated by user with:

```text
Mac Wi-Fi off
Galaxy LTE connected
USB/ADB connected
```

Passed outcomes:

- Internet works.
- Chrome works.
- Claude works.
- Discord works after the latest validation.
- KakaoTalk works on Galaxy Wi-Fi and Galaxy LTE after the latest validation.

Strict completion check now passed:

```text
DNS works through current macOS resolver.
Chrome/web HTTPS reachable.
Discord gateway API HTTPS reachable.
Discord gateway TCP reachable.
Kakao HTTPS reachable.
Kakao TCP reachable.
KakaoTalk macOS reachability reachable.
git over HTTPS reachable.
App connectivity check passed.
```

The TCP/DNS app milestone is complete for the current MacBook + Galaxy Note 9 workflow.

Remaining reliability work:

- Forced terminal close still requires manual `system-recover`.
- Mid-session Galaxy LTE/Wi-Fi switching can terminate the active tunnel.

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
- Disarm the abnormal-exit cleanup guard after cleanup completes.

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
- Disarm any stale cleanup guard.

### 9.3 Abnormal Exit Guard

Current implementation:

- `system` starts a cleanup guard before modifying TUN routes or DNS.
- The preferred guard launch path is `sudo launchctl submit`, which runs outside the closing Terminal's process group.
- The older `nohup` background guard remains as fallback if `launchctl submit` fails.
- The guard runs with administrator privileges so it can recover routes/DNS without a terminal prompt.
- The guard monitors the main system-mode process.
- Normal shutdown writes an explicit disarm token.
- If the main process disappears without that matching disarm token, the guard runs recovery cleanup automatically.
- Terminal `HUP`/`TERM` paths clean up local state but do not disarm the guard.
- After abnormal exit, the guard repeats route/DNS/proxy repair and internet verification for up to about two minutes.
- The guard removes its own launchd label before exit to avoid restart loops.
- Startup removes stale guard jobs before launching a new guard.
- Cleanup also repairs stale local SOCKS proxies when they point to this tool's local ports.
- `system-status` reports guard pid, launchctl label, session state, and log path.

Current validation state:

- Unit-style disarm test passed with a temporary state directory.
- First field validation with the original guard failed.
- Second local unit test with explicit disarm token passed.
- Field validation showed the guard runs cleanup, but one pass is not enough when Wi-Fi reconnects later.
- Field validation showed repeated cleanup is still ineffective if the main process disarms the guard during `HUP`/`TERM`.
- Field validation after keeping the guard armed on `HUP`/`TERM` still showed general internet can remain unavailable until manual `system-recover`.

Current product stance:

- Do not block the core USB internet milestone on forced-close auto-recovery.
- Keep improving the guard later.
- Make recovery a visible first-class control in packaging.

### 9.4 Documentation

README now includes safe stop rule:

```zsh
./jam-usb-internet system-stop
```

and fallback:

```zsh
./jam-usb-internet system-recover
```

### 9.5 Remaining Work

- Improve forced terminal close recovery.
- Keep explicit on/off/recover `.command` controls.
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
Galaxy Wi-Fi path carries general internet and KakaoTalk.
Galaxy LTE path carries general internet and KakaoTalk.
app-check passes.
```

### 10.4 Remaining Work

- Preserve the current passing app-check state while making reliability changes.
- Improve abnormal-close cleanup guard.
- Handle mid-session Galaxy LTE/Wi-Fi switching without terminating the tunnel.
- Defer Discord voice/video until UDP strategy exists.

## 11. Stage 8: Packaging

### 11.1 Packaging Boundary

Minimal command packaging is allowed now.

Reason:

- System mode now works in target Mac Wi-Fi-off conditions.
- Forced-close automatic recovery is still unreliable, so recovery must be visible.
- Full `.app` packaging should still wait until the workflow has more field time.

### 11.2 First Packaging Step

Implemented explicit controls:

- `Galaxy USB Internet ON.command`
- `Galaxy USB Internet OFF.command`
- `Galaxy USB Internet RECOVER.command`
- README uses on/off/recover wording.

Implemented portable distribution workspace:

- `pkg/README.md`
- `pkg/GALAXY_SETUP.md`
- `pkg/MAC_SETUP.md`
- `pkg/USAGE.md`
- `pkg/PREINSTALL_SECURITY_REVIEW.md`
- `pkg/RELEASE_CHECKLIST.md`
- `pkg/build-dist.sh`
- generated local artifact under `pkg/dist/`

Dependency/security policy:

- Required runtime installs:

  ```zsh
  brew install --cask android-platform-tools
  brew install sing-box
  ```

- Explicitly not required:
  - Android File Transfer
  - RNDIS driver
  - Recovery Reduced Security
  - SIP off
  - Gatekeeper off

Compatibility:

- `Galaxy USB Internet.command` remains the original start command.
- `Galaxy System Stop.command` remains available as the older strong recovery-style stop command.

### 11.3 Later Packaging Step

The small macOS `.app` wrapper now exists with:

- Start button
- Stop button
- Status display
- Recovery button

Current GUI wrapper status:

- SwiftUI wrapper exists under `ui/`.
- Completed app bundle now receives an explicit structural signature.
- Distribution build verifies signature integrity before and after zip extraction.
- Default signature is ad-hoc for local testing.
- Developer ID Application signing and Apple notarization remain required for a Gatekeeper-clean external release.

### 11.4 Remaining Packaging Work

- LaunchAgent
- Menu bar app
- Developer ID Application certificate provisioning
- Apple notarization credential setup and release flow

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

1. Preserve the passing system-mode app connectivity.
2. Keep previous default route backup/restore.
3. Keep KakaoTalk reachability strict in `app-check`.
4. Improve forced-close recovery without risking normal stop/recover.
5. Later, add relay resilience for Galaxy LTE/Wi-Fi switching.
6. Keep packaging build reproducible.
7. Verify syntax and config after each change.

### 13.2 Docs

1. Keep `project.md` current with field session results.
2. Keep `plan.md` current with milestone state and future work.
3. Update README with on/off/recover usage.
4. Keep `pkg/` setup docs current for Note 9, Fold, and Apple Silicon Mac.
5. Keep preinstall/security policy current as dependencies change.
6. Keep session logs appended as work continues.

### 13.3 Git

1. Keep local author identity as `atozwizard`.
2. Commit latest package workspace.
3. Push normally.
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

Current result:

```text
Core app connectivity passed for Galaxy Wi-Fi and LTE.
Forced-close recovery still requires manual system-recover.
Phone-side LTE/Wi-Fi switching during an active session is deferred.
```

## 14. Validation Matrix

### 14.1 Normal Wi-Fi State

Mac Wi-Fi connected:

- `app-check` must pass.
- `system` should not start TUN unless forced.

### 14.2 Mac Wi-Fi Off, Galaxy Wi-Fi Connected

Expected and validated:

- relay check passes.
- TUN starts.
- temporary DNS resolver active.
- internet works.
- KakaoTalk works.
- `app-check` passes.

### 14.3 Mac Wi-Fi Off, Galaxy LTE Connected

Expected and validated:

- Chrome/general internet works.
- Discord text/API works.
- KakaoTalk works.
- `app-check` passes.
- `--mobile-only` may be used to force phone LTE.

### 14.4 Abnormal Close

Current result:

- Force-closing the system-mode terminal triggers cleanup guard.
- General Mac internet may still remain broken after Wi-Fi reconnects.
- KakaoTalk can continue working while other internet fails, which points to stale route/DNS/proxy state rather than total network loss.
- Manual `system-recover` restores normal internet.
- Packaging must expose Recover clearly.

### 14.5 Phone Internet Off, Mac Wi-Fi Connected

Expected:

- normal Mac Wi-Fi remains usable.
- system mode should not break Mac internet.

### 14.6 Phone Internet Off, Mac Wi-Fi Off

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
- Developer ID certificate setup
- Apple notarization flow

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
