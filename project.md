# jam_usb_internet-system_mac-android Project

Date: 2026-05-30
Primary workspace: `/Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet`
Target host: MacBook, macOS 26.5, arm64
Target phone: Samsung Galaxy Note 9 SM-N960N, Android 10 / SDK 29

## Table of Contents

1. Project Identity
2. Problem Definition
3. Purpose
4. Requirements
5. Goals
6. Completion Criteria
7. Architecture Boundary
8. Operating Rules
9. Session Log
10. Current Known State
11. Current Blockers
12. Risk Register
13. Decisions

## 1. Project Identity

Repository name:

```text
jam_usb_internet-system_mac-android
```

Working name:

```text
jam-usb-internet
```

Project type:

```text
macOS + Android USB internet helper
```

The project is a local utility for making a Mac use a Galaxy Note 9 internet connection through USB when ordinary Mac Wi-Fi internet is unavailable or unusable.

## 2. Problem Definition

The user needs the MacBook to access the internet in a constrained or jammed networking environment by using a Galaxy Note 9 connected over USB.

The initial assumption was native Android USB tethering:

```text
Galaxy USB tethering -> macOS USB network interface -> Mac default route
```

Observed reality:

```text
macOS does not expose a usable Android USB network interface for this Galaxy Note 9.
```

This moves the problem from native tethering into a relay/tunnel problem:

```text
Mac apps
  -> macOS route/DNS/TUN
  -> sing-box
  -> local SOCKS port
  -> ADB forward over USB
  -> Android relay binary
  -> Galaxy Wi-Fi or LTE
  -> Internet
```

The core technical problem is no longer "turn on Android USB tethering"; it is:

```text
Build a reliable Mac-wide TCP/DNS internet path over USB using ADB relay and TUN,
while preserving normal Mac Wi-Fi behavior and providing safe cleanup.
```

## 3. Purpose

The purpose is practical personal use:

- Run one local tool after connecting the Galaxy by USB.
- Use Galaxy Wi-Fi or LTE as the Mac's internet source.
- Keep normal Mac Wi-Fi behavior intact when Mac Wi-Fi is working.
- Avoid manual recovery steps after failed attempts.
- Make Chrome, Discord, KakaoTalk, git, and common app traffic work as normal Mac internet consumers.

## 4. Requirements

### 4.1 Functional Requirements

The tool must:

1. Detect and use an authorized Android device over ADB.
2. Upload the Android relay binary to:

   ```text
   /data/local/tmp/knock-relay
   ```

3. Start the Android relay on:

   ```text
   127.0.0.1:18080
   ```

4. Create an ADB forward:

   ```text
   Mac tcp:18080 -> Android tcp:18080
   ```

5. Verify Android relay connectivity before touching privileged Mac route/DNS state.
6. Start a Mac TUN engine through `sing-box`.
7. Route Mac TCP/DNS traffic through the Android relay.
8. Install temporary DNS state only while system mode is active.
9. Install temporary route state only while system mode is active.
10. Cleanly stop all temporary state on stop/recovery.

### 4.2 Connectivity Requirements

The following must work through the intended USB path when Mac Wi-Fi is off or disconnected and Galaxy has Wi-Fi or LTE:

- Chrome/web HTTPS
- Discord gateway HTTP/TCP connectivity
- KakaoTalk-compatible network reachability and TCP/HTTPS connectivity
- git over HTTPS

### 4.3 Safety Requirements

The tool must:

1. Preserve normal Mac Wi-Fi when Wi-Fi internet is healthy.
2. Avoid leaving DNS stuck at `127.0.0.1` after a failed run.
3. Avoid leaving stale TUN split routes after a failed run.
4. Avoid leaving stale default route state after a failed run.
5. Provide `system-stop` for normal shutdown.
6. Provide `system-recover` as a panic/recovery command.
7. Keep the terminal window open while system mode is active.
8. Document that closing the window usually triggers cleanup but explicit stop is safer.

### 4.4 Phone-Side Requirements

The Galaxy side must be:

- Connected by a data-capable USB cable.
- Unlocked when ADB authorization is needed.
- USB mode set to `File Transfer / Android Auto`.
- USB debugging enabled and authorized.
- Galaxy Wi-Fi or LTE connected.
- Android `USB tethering` kept off for the ADB relay path.

### 4.5 Non-Requirements for Current Milestone

Not required yet:

- Native Android USB tethering through macOS USB Ethernet.
- UDP relay.
- Discord voice/video reliability.
- A packaged `.app` on/off switch.
- NetworkExtension implementation.
- Fully unattended launch daemon.

## 5. Goals

### 5.1 Immediate Goal

Make the current script usable for Mac-wide internet over USB when:

```text
Mac Wi-Fi: off or disconnected
Galaxy internet: Wi-Fi or LTE connected
USB: connected with ADB authorized
```

### 5.2 Medium Goal

Package the working behavior into a safer local user interface:

- `On.command`
- `Off.command`
- then possibly a small `.app` with on/off controls

### 5.3 Long-Term Goal

Replace the shell/TUN prototype with a native macOS NetworkExtension packet tunnel app if the prototype proves useful and stable.

## 6. Completion Criteria

The project is not complete until the following pass in the real field workflow.

### 6.1 Required Device State

Test state:

```text
Mac Wi-Fi: off or not connected
Galaxy Wi-Fi: connected
Galaxy LTE: optional
USB: connected
ADB: authorized
```

Alternative test state:

```text
Mac Wi-Fi: off or not connected
Galaxy Wi-Fi: off
Galaxy LTE: connected
USB: connected
ADB: authorized
```

### 6.2 Required App Outcomes

All of the following must work:

- Chrome opens normal HTTPS websites.
- Discord text/API gateway works.
- KakaoTalk reports online and can send/receive messages.
- git can run:

  ```zsh
  git ls-remote https://github.com/git/git.git HEAD
  ```

### 6.3 Required Tool Outcomes

The following command must pass:

```zsh
./jam-usb-internet app-check
```

Required output categories:

- DNS works through current macOS resolver.
- Chrome/web HTTPS reachable.
- Discord gateway API reachable.
- Discord gateway TCP reachable.
- Kakao HTTPS reachable.
- Kakao TCP reachable.
- KakaoTalk macOS reachability reports reachable.
- git over HTTPS reachable.

### 6.4 Required Cleanup Outcomes

After:

```zsh
./jam-usb-internet system-stop
```

or:

```zsh
./jam-usb-internet system-recover
```

the following must be true:

- No `sing-box` system-mode process remains.
- No ADB forward on `tcp:18080` remains.
- Android relay is not running.
- Temporary DNS resolver is inactive.
- Mac normal Wi-Fi works when Wi-Fi is connected.
- No stale TUN routes remain.
- Previous default route is restored.

## 7. Architecture Boundary

### 7.1 Native USB Tethering Path

Status:

```text
Not viable on current Mac + Galaxy Note 9 combination.
```

Reason:

macOS does not expose the Galaxy Note 9 Android USB tethering function as a usable network interface.

Reference:

```text
reference/usb-tethering-routing-reference.md
```

### 7.2 ADB Relay Path

Status:

```text
Viable for TCP/DNS relay.
```

Current evidence:

- `system --check-only` passes.
- Android relay can reach Chrome/web, Discord, Kakao HTTPS, git over HTTPS.

### 7.3 Mac TUN Path

Status:

```text
Partially working. TCP/DNS path is proven; default route / reachability behavior remains incomplete.
```

Evidence:

- `sing-box` starts TUN at `utun4`.
- Split route to `1.1.1.1` passes.
- DNS resolver at `127.0.0.1` starts.
- Temporary default route verification can still fail for `utun4`.
- Startup now treats default-route verification as nonfatal when split routes pass.
- KakaoTalk/macOS reachability remains the unresolved app-level blocker.

## 8. Operating Rules

### 8.1 Start

Run:

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
./jam-usb-internet system
```

or double-click:

```text
Galaxy USB Internet.command
```

### 8.2 Stop

Preferred stop:

```zsh
./jam-usb-internet system-stop
```

Double-click stop:

```text
Galaxy System Stop.command
```

### 8.3 Recover

If normal Wi-Fi does not recover:

```zsh
./jam-usb-internet system-recover
```

### 8.4 Window Close Rule

Closing the system-mode terminal window usually triggers cleanup, but explicit `system-stop` is safer because system mode modifies:

- TUN routes
- default route
- temporary DNS resolver
- ADB forward
- Android relay process

## 9. Session Log

### Session 0: Native USB Tethering Attempt

User goal:

```text
Connect Galaxy Note 9 by USB and make the Mac use internet through USB tethering.
```

Observed:

- Mac did not expose a usable Android USB network interface.
- USB tethering did not create a Mac network service.

Outcome:

- Native USB tethering path considered blocked for current device/host combination.

### Session 1: Browser-Only Proxy

Implemented:

- ADB SOCKS proxy path.
- Chrome-only fallback.

Outcome:

- Chrome could use internet through the phone path.
- System-wide Mac apps did not all use the path.

### Session 2: Android Relay Skeleton

Implemented:

- Android relay lifecycle commands:
  - `relay-install`
  - `relay-start`
  - `relay-stop`
  - `relay-clean`
- ABI detection for `arm64-v8a`.
- Binary target:

  ```text
  android-relay/bin/arm64-v8a/knock-relay
  ```

Outcome:

- Relay can be pushed to `/data/local/tmp/knock-relay`.
- ADB forward can expose relay on Mac `127.0.0.1:18080`.

### Session 3: Android Relay DNS Failure

Observed failure:

```text
Relay health check failed through 127.0.0.1:18080
```

Relay log showed:

```text
resolve example.com: lookup example.com ... dial udp ... network is unreachable
```

Cause:

- Relay used direct UDP DNS.
- Android had usable internet, but relay DNS path failed.

Fix:

- Relay now resolves domains through DoH over HTTPS first.
- Direct DNS remains fallback.

Outcome:

`system --check-only` passed with:

- Chrome/web through Android relay
- Discord through Android relay
- Kakao HTTPS through Android relay
- git through Android relay

### Session 4: Mac DNS Safety Recovery

Observed failure:

- DNS was left pointing at `127.0.0.1` while no DNS service was running.
- Normal Mac Wi-Fi stopped resolving names.

Fix:

- DNS restore made visible and safer.
- Stale local DNS detection added.
- `system-recover` added as panic button.

Outcome:

- Normal Wi-Fi could be restored.
- `app-check` passes in normal Wi-Fi state.

### Session 5: Mac TUN Prototype

Implemented:

- `sing-box` TUN config.
- Temporary DNS resolver through `scutil` dynamic store.
- Split IPv4 routes through active `utunX`.
- Route verification for `1.1.1.1`.

Outcome:

- TUN starts.
- DNS server starts on `127.0.0.1:53`.
- Split route can route public IPv4 destinations through TUN.

### Session 6: KakaoTalk Reachability Failure

Observed:

Chrome and Discord worked, but KakaoTalk did not.

Command evidence:

```zsh
scutil -r talk.kakao.com
```

returned:

```text
Not Reachable
```

even though TCP/HTTPS to Kakao worked.

Cause hypothesis:

- KakaoTalk uses macOS reachability API before opening network sockets.
- Split routes are enough for traffic, but not enough for app-level reachability when default route is missing or stale.

Fix attempted:

- Add temporary default route through `utunX`.
- Add KakaoTalk macOS reachability to `app-check`.

Outcome:

- In normal Wi-Fi state, `app-check` passes.
- In Wi-Fi-off system mode, default route verification still fails.

### Session 7: 2026-05-30 Default Route Verification Failure

Test condition:

```text
Mac Wi-Fi: off
Galaxy Wi-Fi: connected
USB/ADB: connected and authorized
```

Observed repeated failure:

```text
ERROR[0000] network: missing default interface
INFO[0000] inbound/tun[tun-in]: started at utun4
INFO[0000] inbound/direct[dns-in-udp]: udp server started at 127.0.0.1:53
INFO[0000] inbound/direct[dns-in-tcp]: tcp server started at 127.0.0.1:53
INFO[0000] sing-box started (0.00s)
[info] Installing IPv4 split routes through utun4.
[warn] Temporary default route verification failed for utun4.
[ok] IPv4 route verification passed through utun4.
```

Then cleanup ran:

```text
[ok] Stopped Android relay if it was running.
[ok] Removed ADB forward tcp:18080 if it existed.
```

Important detail:

- Android relay checks all pass before TUN start.
- Failure is specifically Mac default route installation/verification.

Current fix applied after this session:

- Temporary default route installation now uses TUN gateway:

  ```text
  172.19.0.1
  ```

  instead of only:

  ```text
  -interface utunX
  ```

- Verification warning now prints the current `route -n get default` output for better diagnosis.

Next required validation:

Run system mode again with Mac Wi-Fi off and Galaxy Wi-Fi connected.

Expected success signal:

```text
[ok] Installed temporary default route through utunX for macOS app reachability.
```

Required absence:

```text
Temporary default route verification failed for utunX
```

### Session 8: 2026-05-30 Git and GitHub Project Start

User request:

```text
이제부터 깃으로 관리하고 깃헙에도 올리자.
레포 이름은 jam_usb_internet-system_mac-android.
```

Implemented:

- Initialized local git repository in:

  ```text
  /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
  ```

- Created `.gitignore`.
- Added `project.md`.
- Added `plan.md`.
- Created initial commit:

  ```text
  961e73a Initial jam USB internet system prototype
  ```

- Created GitHub repository:

  ```text
  https://github.com/atozwizard/jam_usb_internet-system_mac-android
  ```

Repository visibility:

```text
PRIVATE
```

Git remote:

```text
origin https://github.com/atozwizard/jam_usb_internet-system_mac-android.git
```

Current branch:

```text
main
```

### Session 9: 2026-05-30 Git Author Correction and Nonfatal Default Route Patch

User observation:

```text
GitHub commit author appeared as twentyflags / knocklab instead of atozwizard.
```

Cause:

- GitHub repository owner and Git commit author are separate.
- Commit author comes from local Git config:

  ```zsh
  git config user.name
  git config user.email
  ```

- The first commits were created while local/global Git identity still pointed at the previous `twentyflags` identity.

Correction applied locally:

```text
user.name=atozwizard
user.email=251137756+atozwizard@users.noreply.github.com
```

Existing local commits were rewritten so author and committer are both:

```text
atozwizard <251137756+atozwizard@users.noreply.github.com>
```

Remote correction:

- Rewritten history was pushed to GitHub with `--force-with-lease`.
- Remote `main` now uses the `atozwizard` author/committer identity.

Latest target-condition log:

```text
Mac Wi-Fi: off
Galaxy Wi-Fi: connected
USB/ADB: connected and authorized
```

Relay stage:

- ADB device detected.
- Android relay uploaded.
- ADB forward created.
- Relay health check passed.
- Chrome/web through Android relay passed.
- Discord through Android relay passed.
- Kakao HTTPS through Android relay passed.
- git over Android relay passed.

TUN stage:

```text
ERROR[0000] network: missing default interface
INFO[0000] inbound/tun[tun-in]: started at utun4
INFO[0000] inbound/direct[dns-in-udp]: udp server started at 127.0.0.1:53
INFO[0000] inbound/direct[dns-in-tcp]: tcp server started at 127.0.0.1:53
[warn] Temporary default route verification failed for utun4: route: writing to routing socket: not in table
[ok] IPv4 route verification passed through utun4.
```

Interpretation:

- `network: missing default interface` is expected when Mac Wi-Fi is off and no normal default route exists.
- This message is from `sing-box`; it does not mean the Android relay failed.
- The split route verification proves packets such as `1.1.1.1` can be routed through `utun4`.
- The previous startup logic was too strict: it stopped the whole system when default-route verification failed, even though TCP/DNS traffic could still work through split routes.

Patch applied:

- Default route verification failure is now nonfatal during `system` startup.
- `system` now keeps running if DNS/TCP checks pass.
- KakaoTalk macOS reachability is still strict in `app-check`.
- In `system` startup, KakaoTalk reachability failure now warns but does not immediately tear down Chrome/Discord/git-capable connectivity.

Reason for this change:

- The immediate goal is to make USB internet usable first.
- KakaoTalk reachability remains a completion blocker, but it should not prevent testing or using the already-working TCP/DNS path.

### Session 10: 2026-05-30 Target Connectivity Passed, Abnormal Exit Recovery Fails

User validation result:

```text
Mac Wi-Fi off
Galaxy Wi-Fi connected
Internet works
KakaoTalk works
```

Earlier user validation result:

```text
Mac Wi-Fi off
Galaxy LTE connected
Internet works
KakaoTalk reported working in this run
```

Later Session 11 results temporarily superseded the LTE KakaoTalk conclusion because LTE could carry general internet while KakaoTalk failed. Session 15 supersedes that again: LTE now passes KakaoTalk and strict `app-check`.

Normal stop result:

```text
Mac Wi-Fi on and connected
Galaxy USB disconnected
Normal Mac internet works only when system mode was stopped with system-stop
```

Failure found:

```text
If the system-mode session is closed abnormally, cleanup does not reliably run.
Normal Mac internet can become unavailable until manual recovery.
```

Cause hypothesis:

- Shell `trap ... EXIT/HUP` is not enough for all Terminal/window-kill paths.
- A forced close can interrupt cleanup before route/DNS state is restored.
- Previous startup preclean did not explicitly restore/delete manual TUN routes before stopping old `sing-box`.

Patch applied:

- Added a root cleanup guard process for `system` mode.
- The guard starts before TUN routes or DNS are modified.
- The guard monitors the main system-mode process.
- If the main process disappears without a normal disarm, the guard runs recovery cleanup:
  - restore/delete TUN routes
  - remove temporary DNS resolver
  - restore DNS backup or repair stale local DNS
  - stop `sing-box`
  - stop Android relay if possible
- Normal cleanup disarms the guard after cleanup completes.
- `preclean_system_mode` now restores routes before stopping old `sing-box`.
- `system-status` now reports cleanup guard state and log path.

Status after this session:

- Primary connectivity milestone is met for Galaxy Wi-Fi and LTE.
- Normal stop path works.
- Abnormal close recovery has code support and needs field validation by force-closing a system-mode window.

### Session 11: 2026-05-30 LTE App Variance and Guard Failure

User validation order:

1. Mac Wi-Fi off, Galaxy Wi-Fi connected:
   - Internet works.
2. Mac Wi-Fi off, Galaxy LTE connected:
   - Chrome works.
   - Claude works.
   - KakaoTalk fails.
   - Discord initially fails.
3. Mac Wi-Fi connected, Galaxy USB disconnected, system session force-closed by closing Terminal:
   - General internet fails.
   - KakaoTalk still works.
4. Mac Wi-Fi connected, USB reconnected, `system-recover` run:
   - General internet recovers.
   - USB can then be disconnected and normal internet still works.
5. Mac Wi-Fi off, Galaxy LTE connected, after retry/recovery:
   - Chrome works.
   - Claude works.
   - Discord works.
   - KakaoTalk fails.
6. Normal `system-stop`, USB disconnected, Mac Wi-Fi connected:
   - Normal internet works.

Interpretation:

- Galaxy Wi-Fi path is now the best validated target path.
- Galaxy LTE path can carry general internet and Discord, but KakaoTalk was unreliable in this session. Session 15 later resolved this, so it is no longer a current blocker.
- Normal stop is reliable.
- The first cleanup guard implementation did not reliably recover after a real Terminal force-close.
- The force-close symptom may include stale route/DNS state and/or stale local SOCKS proxy state because `system-recover` fixed the condition.

Patch applied after this session:

- Guard launch changed from background `nohup` to `sudo launchctl submit`.
- The guard now runs outside the closing Terminal's process group.
- The old `nohup` guard remains as fallback if `launchctl submit` fails.
- Guard label is recorded in state and shown by `system-status`.
- Cleanup now repairs stale local SOCKS proxies only when they point to this tool's local ports.
- Preclean, normal cleanup, guard cleanup, `system-stop`, and `system-recover` all run the targeted stale SOCKS repair.

Next validation:

- Start system mode and confirm the log says:

  ```text
  Started abnormal-exit cleanup guard (... label com.atozwizard.jam-usb-internet.guard...)
  ```

- Force-close Terminal.
- Wait 5-10 seconds.
- Reconnect Mac Wi-Fi.
- Confirm general internet works without manual recovery.
- If it fails, run `system-recover` and inspect:

  ```zsh
  ./jam-usb-internet system-status
  tail -80 ~/.jam-usb-internet/system-guard.log
  ```

### Session 12: 2026-05-30 Guard Restart Loop Root Cause

New evidence:

```text
system-status:
Cleanup guard:
  pid: none
  session: active
  label: com.atozwizard.jam-usb-internet.guard.87938
```

Guard log showed repeated `launchctl submit` restarts:

```text
cleanup guard started for parent ...
cleanup guard disarmed after parent exit
cleanup guard started for parent ...
cleanup guard disarmed after parent exit
```

Root cause:

- `launchctl submit` left the guard label registered after the guard process exited.
- The submitted job could restart repeatedly.
- The first guard design treated missing session state as a normal disarm condition.
- During a real Terminal force-close, parent disappearance plus partial cleanup could make the guard exit without running recovery.

Patch applied:

- Added explicit disarm token file:

  ```text
  ~/.jam-usb-internet/system-guard.disarm
  ```

- The guard now treats only a matching disarm token as normal shutdown.
- If the parent process disappears and the disarm token is absent, the guard runs recovery even if the session file is missing.
- The guard removes its own `launchctl` label before exit to prevent restart loops.
- Startup removes stale guard jobs with the project label prefix before launching a new guard.
- Existing stale guard labels were removed from the local launchd state.

Validation:

- `zsh -n jam-usb-internet` passed.
- `sing-box check` passed.
- Android relay `go test ./...` passed.
- Normal Wi-Fi `app-check` passed.
- Guard explicit-disarm unit test passed.

Remaining field test:

- Real Terminal forced close with the explicit-disarm guard.
- Galaxy LTE KakaoTalk diagnosis with `app-check` and `system-status`.

### Session 13: 2026-05-30 Guard Ran Once But Wi-Fi Recovery Still Needed Manual Recover

User validation:

```text
Force-close system-mode terminal
Connect Mac Wi-Fi
KakaoTalk works
Other internet fails
Run system-recover
Other internet recovers
```

Guard evidence:

```text
[warn] System session exited without disarming cleanup guard; recovering normal networking.
[ok] Cleanup guard finished.
```

System status after manual recovery:

- No `sing-box` process.
- No temporary DNS resolver.
- No cleanup guard session.
- Route to `1.1.1.1` goes through normal Wi-Fi gateway `192.168.55.1`.

Interpretation:

- The guard now detects abnormal exit and runs cleanup.
- The remaining failure is timing: guard cleanup can finish while Mac Wi-Fi is still off or reconnecting.
- Later Wi-Fi connection may still require a second cleanup pass, which manual `system-recover` provides.

Patch applied:

- Added repeated guard recovery loop.
- After abnormal exit, guard now repeats route/DNS/proxy cleanup and internet verification for up to about two minutes.
- The loop is intended to catch delayed Mac Wi-Fi reconnection after Terminal has already closed.
- Manual `system-recover` uses a shorter repeated repair so it remains responsive.
- Stale TUN default route deletion was strengthened when the gateway is `172.19.0.1`.

Next validation:

- Force-close system mode.
- Turn on/connect Mac Wi-Fi.
- Wait 10-20 seconds first, then test internet.
- If still broken, wait up to 2 minutes once before running `system-recover`, so the repeated guard loop can be observed.
- Check:

  ```zsh
  tail -120 ~/.jam-usb-internet/system-guard.log
  ```

### Session 14: 2026-05-30 Forced Close Still Needed Manual Recover

User validation:

```text
Force-close system-mode terminal
Connect Mac Wi-Fi
KakaoTalk works
Other internet remains unavailable after two minutes
Run system-recover
Other internet recovers
```

Additional user finding:

```text
Galaxy Wi-Fi path can also fail KakaoTalk.
```

Guard/system status after manual recovery:

- No `sing-box` process.
- No temporary DNS resolver.
- No active guard session.
- Normal default route points through Wi-Fi gateway.
- Wi-Fi SOCKS proxy is disabled, but retains this tool's local proxy server/port value while disabled.

Root cause refinement:

- The guard itself can run recovery.
- However, Terminal close can deliver `HUP`/`TERM` to the main script.
- The main script's signal trap previously used the same cleanup path as normal shutdown.
- That path disarmed the guard after cleanup.
- If Mac Wi-Fi was still off or reconnecting, disarming the guard too early left no process to repeat cleanup after Wi-Fi came back.

Patch applied:

- `INT` and normal `EXIT` still perform normal cleanup and disarm the guard.
- `TERM` and `HUP` now perform cleanup but keep the guard armed.
- The guard remains responsible for repeated recovery after abnormal terminal/window close.
- TUN default route installation now falls back from gateway route to `route add default -interface utunX` to improve macOS reachability for KakaoTalk.

Next validation:

- Start system mode.
- Confirm guard starts.
- Force-close Terminal.
- Reconnect Mac Wi-Fi.
- Wait for the guard log to show either:

  ```text
  Cleanup guard verified normal internet after N recovery pass(es).
  ```

  or:

  ```text
  Cleanup guard finished repeated repair, but normal internet was not verified.
  ```

- Test KakaoTalk on Galaxy Wi-Fi again after the default-route fallback.

### Session 15: 2026-05-30 Core Connectivity Milestone Reached

User validation:

```text
Mac Wi-Fi off
Galaxy Wi-Fi connected
Chrome/web works
KakaoTalk works
```

User validation:

```text
Mac Wi-Fi off
Galaxy LTE connected
Chrome/web works
Claude works
Discord works
KakaoTalk works
```

Strict app check while system mode was active:

```text
[ok] DNS works through current macOS resolver.
[ok] Chrome/web HTTPS reachable (204): https://www.google.com/generate_204
[ok] Discord gateway API HTTPS reachable (200): https://discord.com/api/v10/gateway
[ok] Discord gateway TCP reachable: gateway.discord.gg:443
[ok] Kakao HTTPS reachable (404): https://talk.kakao.com
[ok] Kakao TCP reachable: talk.kakao.com:443
[ok] KakaoTalk macOS reachability: talk.kakao.com (Reachable)
[ok] git over HTTPS reachable: github.com/git/git.git
[ok] App connectivity check passed.
```

Outcome:

- The core TCP/DNS app milestone is met for both Galaxy Wi-Fi and Galaxy LTE.
- KakaoTalk is no longer the immediate blocker after the latest route/reachability fixes and field validation.
- Normal `system-stop` restores ordinary Mac Wi-Fi internet.
- Manual `system-recover` restores ordinary Mac Wi-Fi internet after abnormal terminal close.

Remaining reliability issue:

```text
Force-closing the system-mode terminal can still leave general Mac internet unavailable until system-recover is run.
```

Accepted near-term handling:

- Do not treat forced-close auto-recovery as a blocker for core USB internet usability.
- Package visible controls so the daily workflow has:
  - ON
  - OFF
  - RECOVER
- Continue improving the guard later.

Deferred issue:

```text
Switching the Galaxy's own internet connection from LTE to Wi-Fi during an active session can briefly interrupt the phone path and terminate the tunnel process.
```

This is recorded as future reliability work, not part of the core connectivity completion gate.

### Session 16: 2026-05-30 Distribution Packaging Started

User request:

```text
배포용 패키징 합시다, pkg 디렉토리 생성해서 그곳에 진행
갤럭시쪽 셋팅 방법과 맥쪽 셋팅 방법 필수사항들로 사용방법도 기록
```

Implemented:

- Created packaging workspace:

  ```text
  pkg/
  ```

- Added portable distribution build script:

  ```text
  pkg/build-dist.sh
  ```

- Added Galaxy setup guide:

  ```text
  pkg/GALAXY_SETUP.md
  ```

- Added Mac setup guide:

  ```text
  pkg/MAC_SETUP.md
  ```

- Added usage guide:

  ```text
  pkg/USAGE.md
  ```

- Added release checklist:

  ```text
  pkg/RELEASE_CHECKLIST.md
  ```

- Added packaging overview:

  ```text
  pkg/README.md
  ```

- Updated `.gitignore` so generated distribution artifacts under `pkg/dist/` are not committed.
- Updated `doctor` wording from Note 9-only to Galaxy phone, including Note 9 and Fold.
- Bumped project version to:

  ```text
  0.4.3
  ```

Packaging format:

```text
Portable folder + zip
```

Reason:

- The user must see `ON`, `OFF`, and `RECOVER` directly.
- Current forced-close recovery still requires an obvious manual recovery path.
- A signed/notarized `.app` or installer `.pkg` is a later packaging stage.

Generated package:

```text
pkg/dist/jam-usb-internet-0.4.3/
pkg/dist/jam-usb-internet-0.4.3.zip
pkg/dist/jam-usb-internet-0.4.3.zip.sha256
```

The generated zip is not tracked in git and should be attached to a GitHub Release when a public/private release artifact is needed.

### Session 17: 2026-05-30 Preinstall and Security Review

User request:

```text
brew로 설치해야 할 라이브러리,
AndroidFileTransfer.dmg 필요 여부,
안전모드/보안등급 하향 필요 여부,
Note 9/Fold 개발자모드 사용법을 공식문서 기준으로 꼼꼼히 검토
```

Review result:

- Required runtime dependencies:

  ```zsh
  brew install --cask android-platform-tools
  brew install sing-box
  ```

- Not required:

  ```text
  /Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg
  Android File Transfer
  RNDIS driver
  macOS Recovery Reduced Security
  SIP off
  Gatekeeper off
  ```

Reasoning:

- The package uses ADB, not Android File Transfer.
- The Android relay is uploaded through `adb push`.
- Native Android USB tethering/RNDIS is not the project baseline on Mac.
- The package does not install a kernel extension or system extension.
- Mac-side privileged work is limited to temporary route/DNS/TUN operations through existing macOS mechanisms.

Docs added/updated:

- Added:

  ```text
  pkg/PREINSTALL_SECURITY_REVIEW.md
  ```

- Updated:

  ```text
  pkg/MAC_SETUP.md
  pkg/GALAXY_SETUP.md
  pkg/USAGE.md
  pkg/README.md
  pkg/RELEASE_CHECKLIST.md
  README.md
  ```

- Updated `jam-usb-internet` user-facing install hints from:

  ```zsh
  brew install android-platform-tools
  ```

  to:

  ```zsh
  brew install --cask android-platform-tools
  ```

Version:

```text
0.4.4
```

### Session 18: 2026-06-01 GUI App Damaged Error Analysis

User report:

```text
M3/M4 MacBook에서 .app 파일이 손상된 파일로 읽혀 실행되지 않음.
.command shell fallback은 정상 작동.
```

Reproduction:

```zsh
ui/build-app.sh
codesign --verify --deep --strict --verbose=4 "ui/build/Jam USB Internet.app"
```

Original result:

```text
code has no resources but signature indicates they must be present
```

Root cause:

- `swiftc` generated an arm64 Mach-O executable with a linker ad-hoc signature.
- The build script assembled an `.app` bundle after compilation but did not sign the completed bundle.
- The bundle lacked:

  ```text
  Contents/_CodeSignature/CodeResources
  ```

- The packaged zip preserved this malformed bundle.
- Gatekeeper could therefore report that the app was damaged.

Not the cause:

- M3/M4 CPU architecture.
- Both M3 and M4 are compatible with the current:

  ```text
  Mach-O 64-bit executable arm64
  ```

Fix:

- Bumped version to:

  ```text
  0.4.5
  ```

- Updated:

  ```text
  ui/build-app.sh
  ```

  so it signs the completed bundle and runs:

  ```zsh
  codesign --verify --deep --strict --verbose=2 "Jam USB Internet.app"
  ```

- Updated:

  ```text
  pkg/build-dist.sh
  ```

  so it verifies:

  - source app after UI build
  - copied app in distribution folder
  - extracted app after zip creation

- Added:

  ```text
  pkg/CODE_SIGNING.md
  ```

Current signing tiers:

```text
Default build: ad-hoc signature for local structural testing.
External polished distribution: Developer ID Application certificate + Apple notarization.
```

Current local machine status:

```text
security find-identity -v -p codesigning
0 valid identities found
```

Implication:

- Local structural corruption is fixed.
- This Mac cannot yet produce a Gatekeeper-clean external release without configuring a Developer ID certificate and notarization credentials.
- `spctl --assess` rejection is still expected for the current ad-hoc build.

Additional self-repair:

- JSON status collection used:

  ```zsh
  local path=""
  ```

- In zsh, lowercase `path` is tied to `PATH`.
- This temporarily emptied command lookup and produced:

  ```text
  command not found: awk
  ```

- Renamed the variable to:

  ```zsh
  adb_path
  ```

- `doctor --json` and `system-status --json` now run without that warning.

## 10. Current Known State

Known working:

- ADB device detection.
- Relay binary upload.
- Android relay start.
- ADB forward creation.
- Android relay app-style check:
  - Chrome/web
  - Discord
  - Kakao HTTPS
  - git
- Normal Wi-Fi recovery state.
- `app-check` on normal Wi-Fi.
- Local Git author config is now `atozwizard`.
- Mac Wi-Fi off + Galaxy Wi-Fi connected: internet works, KakaoTalk works.
- Mac Wi-Fi off + Galaxy LTE connected: Chrome/web, Claude, Discord, KakaoTalk, and git work after the latest validation.
- `app-check` passes in the target tunnel state.
- Mac Wi-Fi connected + Galaxy disconnected: normal Mac internet works after `system-stop`.
- Manual `system-recover` restores normal Mac internet after forced terminal close.
- Portable distribution packaging exists under `pkg/`.
- Preinstall/security review is documented under `pkg/PREINSTALL_SECURITY_REVIEW.md`.
- GUI app bundle structural signing is fixed and verified after zip extraction.
- Current default GUI build is ad-hoc signed for local testing.

Known failing:

- Abnormal terminal/window close can still leave general Mac internet unavailable until `system-recover` is run.
- Switching Galaxy LTE/Wi-Fi while the tunnel is active can interrupt the phone network briefly and terminate the tunnel process.
- Discord voice/video is not guaranteed because the current milestone is TCP/DNS, not UDP.
- Gatekeeper-clean external GUI distribution is not available until Developer ID signing and Apple notarization are configured.

## 11. Current Blockers

### Blocker A: Abnormal Exit Recovery

Symptom:

```text
Closing or killing the system-mode terminal without system-stop can leave normal Mac internet unavailable.
```

Impact:

- DNS/routes may remain in temporary TUN state.
- User must run `system-recover` manually in affected cases.

Current patch:

- Launch cleanup guard for abnormal system-mode exits through `sudo launchctl submit`.
- Require an explicit disarm token before treating guard exit as normal.
- Remove stale guard launchd labels before starting a new guard.
- Repeat route/DNS/proxy repair after abnormal exit so delayed Wi-Fi reconnects are handled.
- Keep the guard armed on `HUP`/`TERM` terminal exits.
- Make guard refuse to start system mode if it cannot be launched.
- Disarm guard only after normal cleanup is complete.
- Make preclean restore route state before stopping old TUN engine.
- Repair stale local SOCKS proxy settings for this tool's local ports.

Required test:

- Start system mode with Mac Wi-Fi off and Galaxy internet connected.
- Confirm internet and KakaoTalk work.
- Force-close the system-mode terminal.
- Wait several seconds.
- Turn Mac Wi-Fi on and connect to normal Wi-Fi.
- Confirm normal Mac internet works without manual `system-recover`.

Fallback if this test fails:

```zsh
./jam-usb-internet system-recover
```

Current product decision:

- Keep `system-recover` as a required visible control.
- Treat automatic abnormal-exit cleanup as a reliability improvement, not a blocker for the core connectivity milestone.

### Blocker B: Mid-Session Galaxy Network Switching

Symptom:

```text
Galaxy LTE connected and system mode running.
Galaxy network is switched to Wi-Fi.
During the brief phone-side network drop, the terminal/tunnel process exits.
```

Impact:

- Active sessions are not resilient to phone-side network transitions.
- The user can restart system mode after the phone settles.

Required later work:

- Relay reconnect/backoff.
- ADB forward health monitor.
- Do not tear down immediately on one transient phone-side network failure.

### Blocker C: Packaging UI Incomplete

Minimal packaging has started with explicit command launchers:

- `Galaxy USB Internet ON.command`
- `Galaxy USB Internet OFF.command`
- `Galaxy USB Internet RECOVER.command`

Full `.app` packaging should wait until:

- Abnormal close recovery is field-validated.
- Stop/recover are proven.
- The on/off UX is clear enough for daily use.

### Closed Blockers

#### TUN Default Route Verification

```text
Temporary default route verification failed for utunX
```

Status:

- No longer blocks startup if split routes pass.
- User validated internet and KakaoTalk in target Wi-Fi-off Galaxy-Wi-Fi and Galaxy-LTE conditions.

#### KakaoTalk macOS Reachability

Status:

```text
KakaoTalk works in target Galaxy Wi-Fi and Galaxy LTE conditions.
```

The latest strict `app-check` passed while system mode was active.

## 12. Risk Register

### Risk 1: macOS Route API Behavior

Risk:

macOS may not accept `default -> utunX` in the form currently attempted.

Mitigation:

- Try gateway-based route via `172.19.0.1`.
- Keep split routes as backup.
- Print route diagnostics when verification fails.

### Risk 2: Cleanup Failure

Risk:

Failed runs may leave DNS/routes behind.

Mitigation:

- `system-stop`
- `system-recover`
- DNS stale repair
- default route backup/restore

### Risk 3: UDP Apps

Risk:

Discord voice/video may not work because the relay is TCP-only.

Mitigation:

- Current milestone explicitly targets TCP/DNS.
- UDP relay is a later milestone.

### Risk 4: ADB Debugging Trust

Risk:

USB debugging is a privileged local trust channel.

Mitigation:

- Use only trusted Mac/phone pair.
- Disable USB debugging when not needed.

## 13. Decisions

### Decision 1: Native USB Tethering Is Not the Primary Path

Native Android USB tethering is treated as unsupported for this device/host combination.

### Decision 2: ADB Relay Is the Primary Short-Term Path

ADB relay remains the primary engineering path.

### Decision 3: TCP/DNS First

Current milestone does not include UDP.

### Decision 4: Minimal Command Packaging Is Allowed

Full `.app` packaging waits until reliability is better, but explicit command launchers are allowed now because the core USB internet path works and recovery must be easy to access.

### Decision 5: Explicit Stop Is Preferred

Users should stop with:

```zsh
./jam-usb-internet system-stop
```

or:

```text
Galaxy USB Internet OFF.command
```

before closing the terminal.

If the terminal was force-closed or normal Wi-Fi does not recover, users should run:

```text
Galaxy USB Internet RECOVER.command
```

## 14. Session Record: 2026-06-02 Galaxy Flip and M3 Cleanup Guard Failure

### 14.1 Field Environment

- Mac account home: `/Users/knocklab`
- Mac model class: Apple Silicon M3
- Android device class: Galaxy Flip
- Entry point: packaged `.command` shell launcher

### 14.2 Field Log

The relay preparation completed before the failure:

```text
[ok] System mode is ready to start.
[info] TUN routing and local DNS setup need macOS administrator permission.
[info] Keep this terminal open. Press Ctrl-C to stop and clean up.

[warn] Could not start abnormal-exit cleanup guard. See: /Users/knocklab/.jam-usb-internet/system-guard.log
[fail] Could not start abnormal-exit cleanup guard; refusing to modify TUN routes/DNS.
[ok] Stopped Android relay if it was running.
[ok] Removed ADB forward tcp:18080 if it existed.
```

### 14.3 Failure Boundary

The failure occurred after Android relay checks and before TUN route or DNS mutation.

This means:

- Galaxy USB debugging authorization was sufficient to upload and run the relay.
- ADB forwarding was sufficient to validate relay connectivity.
- The failure was not evidence that Galaxy Flip USB data mode, Galaxy Wi-Fi/LTE, or Android relay connectivity had failed.
- The script correctly failed closed before changing Mac networking.

### 14.4 Cleanup Guard Defect

The previous startup implementation had a narrow readiness window:

```text
20 attempts * 0.1 seconds = 2 seconds
```

If privileged `launchctl submit` returned success but the guard process did not create `system-guard.pid` within that window, startup failed immediately. The fallback path was used only when `launchctl submit` returned a non-zero status. A slow successful launch could therefore fail without trying the fallback.

### 14.5 Implemented Repair

Version `0.4.6` changes cleanup guard startup:

1. Wait up to 10 seconds for the submitted `launchctl` guard.
2. Treat a PID file as ready only when it contains a numeric PID and that process is alive.
3. Try an absolute-path `/usr/bin/nohup /usr/bin/env ...` fallback when `launchctl` fails or does not become ready in time.
4. Redirect fallback stdin from `/dev/null`.
5. Write parent-side diagnostics to `~/.jam-usb-internet/system-guard.log`.
6. Print the last 20 guard-log lines when both startup methods fail.
7. Add `guard-check`, which tests guard start and disarm without modifying routes or DNS.

### 14.6 Local Validation

Validated on the development Mac with isolated temporary state directories:

```text
direct system-guard launch: passed
user launchctl submit launch: passed
nohup fallback launch: passed
zsh syntax validation: passed
```

An interactive administrator-path validation is still required on the Galaxy Flip / M3 field Mac because the development shell had no cached non-interactive sudo credential.

### 14.7 Authentication and Trust Separation

There are separate trust boundaries:

1. Android USB debugging authorization:
   - required for ADB relay upload and forwarding;
   - already passed far enough in the field log to reach system-mode readiness.
2. macOS administrator authorization:
   - required for cleanup guard, TUN route, DNS, and sing-box operations;
   - the field failure occurred in this runtime area.
3. macOS Gatekeeper trust for `Jam USB Internet.app`:
   - ad-hoc signed local packages can still require manual opening or quarantine removal;
   - polished external distribution requires Developer ID Application signing and Apple notarization;
   - this is separate from the `.command` cleanup-guard failure.

### 14.8 Next Field Procedure

Before starting USB internet on the Galaxy Flip / M3 Mac:

```zsh
./jam-usb-internet guard-check
```

If it fails:

```zsh
tail -80 ~/.jam-usb-internet/system-guard.log
```

Collect the full output before running `system`. If `guard-check` passes, continue:

```zsh
./jam-usb-internet system
./jam-usb-internet app-check
./jam-usb-internet system-stop
```

## 15. Session Record: 2026-06-02 Trusted ZIP Quarantine Guidance

### 15.1 Request

Document the free-distribution path for another Mac:

- use the ad-hoc signed `.app` bundle without purchasing a Developer ID membership;
- remove quarantine only for a trusted ZIP;
- do not weaken system-wide Mac security.

### 15.2 Self-Critique

The previous package already generated:

```text
jam-usb-internet-<version>.zip.sha256
```

but its checksum line contained the developer Mac's absolute ZIP path. That was inconvenient for a recipient because `shasum -c` should work from the recipient's download directory without editing the checksum file.

### 15.3 Implemented Repair

Version `0.4.7` changes packaging and documentation:

1. Generate the SHA256 file from inside `pkg/dist`, so it records the ZIP basename only.
2. Include trusted-ZIP setup steps in generated `START_HERE.txt`.
3. Add the same procedure to the project README and package guides.
4. Require checksum verification before quarantine removal.
5. Explicitly forbid applying `xattr` to an unknown or checksum-mismatched ZIP.
6. Keep Gatekeeper, SIP, and macOS Startup Security enabled.

### 15.4 Recipient Procedure

Place both files in the same trusted download directory:

```text
jam-usb-internet-<version>.zip
jam-usb-internet-<version>.zip.sha256
```

Then run:

```zsh
cd /path/to/download-directory
shasum -a 256 -c jam-usb-internet-<version>.zip.sha256
unzip jam-usb-internet-<version>.zip
xattr -dr com.apple.quarantine jam-usb-internet-<version>
```

Continue only if the checksum command prints:

```text
jam-usb-internet-<version>.zip: OK
```

### 15.5 Validation

Validated with the generated `0.4.7` artifact:

```text
portable shasum -c verification: passed
ZIP integrity: passed
strict app-bundle codesign verification: passed
generated START_HERE instructions: verified
```

## 16. Session Record: 2026-06-02 Downloads Cleanup Guard Fallback

### 16.1 Field Evidence

Galaxy Flip / M3 field log:

```text
parent: script=/Users/knocklab/Downloads/jam-usb-internet-0.4.6/jam-usb-internet
parent: launchctl submit rc=0 output=<empty>
/bin/zsh: can't open input file: /Users/knocklab/Downloads/jam-usb-internet-0.4.6/jam-usb-internet
parent: launchctl guard did not become ready within 10 seconds; trying nohup fallback
parent: nohup fallback launcher pid=43138
cleanup guard started for parent 42669
parent: cleanup guard startup failed after launchctl and nohup attempts
```

### 16.2 Root Cause

Two issues combined:

1. The privileged `launchctl submit` context could not reopen the package script under the user's `Downloads` folder. The submitted job kept retrying because `launchctl submit` keeps a failed job alive.
2. The `nohup` fallback actually started successfully as a root-owned process, but the unprivileged parent used:

   ```zsh
   kill -0 "$guard_pid"
   ```

   An unprivileged process receives `operation not permitted` when probing a live root-owned process. The parent misclassified that permission error as a missing process and rejected the working fallback guard.

This was a Mac guard-lifecycle defect, not a Galaxy USB, ADB RSA authorization, or phone internet failure.

### 16.3 Self-Critique

The `0.4.6` repair added a fallback but validated the fallback with a permission-sensitive signal probe. Local tests used same-user processes and therefore did not reproduce the field ownership boundary. Cross-owner process validation was missing.

### 16.4 Implemented Repair

Version `0.4.8`:

1. Adds `process_pid_is_alive`.
2. Uses `kill -0` when permitted and falls back to `ps -p` existence checking.
3. Applies the same existence helper to guard PID and fallback launcher PID checks.
4. Detects package execution under `Downloads`, `Desktop`, or `Documents`.
5. Skips privileged `launchctl submit` for those privacy-managed user folders.
6. Starts the `nohup` cleanup guard fallback immediately.

### 16.5 Local Validation

Validated:

```text
PID 1 root process:
  unprivileged kill -0: operation not permitted
  ps -p existence check: passed
  new process helper result: alive

Downloads path detection: passed
zsh syntax validation: passed
git diff whitespace validation: passed
```

### 16.6 Next Field Procedure

Use the `0.4.8` package. From the unpacked folder:

```zsh
./jam-usb-internet guard-check
```

Expected for a package under `Downloads`:

```text
[info] Using cleanup guard fallback because the package is under Downloads, Desktop, or Documents.
[ok] Started abnormal-exit cleanup guard fallback ...
[ok] Cleanup guard check passed.
```

Then continue:

```zsh
./jam-usb-internet system
./jam-usb-internet app-check
./jam-usb-internet system-stop
```
