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
Partially working, currently blocked by default route / reachability behavior.
```

Evidence:

- `sing-box` starts TUN at `utun4`.
- Split route to `1.1.1.1` passes.
- DNS resolver at `127.0.0.1` starts.
- Failure occurs when temporary default route verification fails for `utun4`.

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
  c8a408a Initial jam USB internet system prototype
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

Known failing:

- Mac-wide TUN mode when Mac Wi-Fi is off currently fails at temporary default route verification.

## 11. Current Blockers

### Blocker A: TUN Default Route Verification

Symptom:

```text
Temporary default route verification failed for utun4.
```

Impact:

- System mode exits before final app checks.
- Mac-wide USB internet remains unavailable in target Wi-Fi-off condition.

Current patch:

- Switch default route installation to gateway `172.19.0.1`.
- Improve diagnostic output.

Required test:

- Mac Wi-Fi off.
- Galaxy Wi-Fi connected.
- Run:

  ```zsh
  ./jam-usb-internet system
  ```

### Blocker B: Packaging Not Yet Started

Packaging should wait until:

- System mode works in target conditions.
- Stop/recover are proven.
- KakaoTalk reachability passes.

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

### Decision 4: No Packaging Until Functional Completion

On/off UI packaging waits until target system mode works reliably.

### Decision 5: Explicit Stop Is Preferred

Users should stop with:

```zsh
./jam-usb-internet system-stop
```

or:

```text
Galaxy System Stop.command
```

before closing the terminal.
