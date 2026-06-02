# jam-usb-internet

MacBook + Galaxy Note 9 USB internet helper.

This is a small macOS utility for the exact field workflow: connect the phone by USB, run one file, and try to get internet through the phone's cellular data.

## Quick Start

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
chmod +x jam-usb-internet *.command
./jam-usb-internet doctor
./jam-usb-internet browser --mobile-only
./jam-usb-internet system --mobile-only --check-only
./jam-usb-internet system
```

For packaged distribution, double-click:

```text
Jam USB Internet.app
```

The app shows ON/OFF/RECOVER controls, live status, preflight checks, and logs. Keep the app open while USB internet is running; use **끄기** before closing.

Terminal fallback (same folder):

```text
Galaxy USB Internet ON.command
Galaxy USB Internet OFF.command
Galaxy USB Internet RECOVER.command
```

Legacy launchers remain available:

```text
Galaxy USB Internet.command
Galaxy Browser Fallback.command
Galaxy System Stop.command
```

Use **OFF** / **끄기** for normal shutdown. Use **RECOVER** / **복구** if a session was force-closed or normal Mac Wi-Fi internet does not come back.

## Phone Setup

On the Galaxy Note 9:

1. Use a data-capable USB cable.
2. Unlock the phone.
3. Turn on either phone Wi-Fi or mobile data.
4. Set the USB mode to `File Transfer / Android Auto`.
5. Enable Developer options and USB debugging, then authorize this Mac.
6. Keep Android `USB tethering` off for `system --mobile-only`.

Use Android `USB tethering` only for the legacy/native `connect --mobile-only` experiment. The main Mac-wide path uses ADB plus an Android relay, so it needs MTP/file-transfer mode to keep ADB stable.

Use `--mobile-only` with `system` only when you intentionally want the Galaxy to turn off phone Wi-Fi and use LTE/mobile data.

If ADB is missing on the Mac:

```zsh
brew install --cask android-platform-tools
```

After installing ADB, connect the phone, unlock it, and accept the USB debugging authorization prompt.

## Preinstall and Security Requirements

Required Homebrew installs:

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

Not required:

- `AndroidFileTransfer.dmg`
- RNDIS drivers
- Reduced Security in macOS Recovery
- disabling SIP
- disabling Gatekeeper

`AndroidFileTransfer.dmg` can be useful only for manually browsing phone files through MTP. This package uploads its relay with `adb push`, so Android File Transfer is not part of the runtime path.

Apple Silicon Macs may ask you to allow a new USB/Thunderbolt accessory. Approve that prompt or check `System Settings -> Privacy & Security -> Allow accessories to connect`.

See:

```text
pkg/MAC_SETUP.md
pkg/GALAXY_SETUP.md
pkg/PREINSTALL_SECURITY_REVIEW.md
```

## Commands

```zsh
./jam-usb-internet connect --mobile-only
./jam-usb-internet browser --mobile-only
./jam-usb-internet proxy --mobile-only
./jam-usb-internet proxy-stop
./jam-usb-internet system-status
./jam-usb-internet system-stop
./jam-usb-internet guard-check
./jam-usb-internet status
./jam-usb-internet doctor
./jam-usb-internet restore
```

For Mac-wide internet fallback, use:

```zsh
./jam-usb-internet system
```

This first checks normal Mac internet. If Wi-Fi internet already works, it does not start the USB TUN. If normal Mac internet is unavailable, it uses the Android relay plus `sing-box` TUN mode and may ask for the Mac admin password.
While running, it installs a temporary macOS DNS resolver that points to `127.0.0.1`, where `sing-box` answers DNS and sends resolution through the phone relay. The temporary resolver is removed on stop. It also backs up the current IPv4 default route and temporarily points the default route through the active `utunX` interface so apps that rely on macOS reachability checks can see the network as online. It verifies that the route to `1.1.1.1` actually goes through `utunX` before it declares system mode usable.

To inspect or stop:

```zsh
./jam-usb-internet system-status
./jam-usb-internet system-stop
./jam-usb-internet system-recover
./jam-usb-internet guard-check
./jam-usb-internet app-check
```

`system-stop` also repairs stale local DNS if a failed run left a network service pointing at `127.0.0.1`.
`system-recover` is the stronger panic button: it stops TUN/proxy/relay state, repairs stale DNS, and then checks Chrome-style HTTPS, Discord, Kakao, and git connectivity.
`guard-check` starts and disarms only the abnormal-exit cleanup guard. It does not install TUN routes or change DNS. Run it before `system` when a new Mac reports `Could not start abnormal-exit cleanup guard`.
`system --check-only` does not start the privileged TUN. It uploads the Android relay, starts the ADB forward, and checks Chrome/web, Discord, Kakao, and git-style HTTPS through the relay. If this fails, the blocker is Android relay/phone internet/DNS, not Mac TUN routing.

Abnormal close behavior:

- `system` starts a `launchctl` cleanup guard before modifying TUN routes or DNS.
- Guard startup waits up to 10 seconds for `launchctl`, then tries a `nohup` fallback before refusing to modify networking.
- Normal shutdown writes an explicit disarm token for that guard.
- If the system-mode terminal is force-closed, the guard should notice that the main session disappeared and run recovery automatically.
- Terminal `HUP`/`TERM` exits are treated as abnormal: the script cleans local state but keeps the guard armed.
- After a forced close, the guard repeats route/DNS/proxy repair for up to about two minutes so it can catch the moment when Mac Wi-Fi reconnects.
- Current field result: forced terminal close still may not restore general Mac internet automatically. If normal Wi-Fi does not work after a forced close, run `Galaxy USB Internet RECOVER.command` or `./jam-usb-internet system-recover`.

Safe stop rule:

```zsh
./jam-usb-internet system-stop
```

If normal Wi-Fi still does not work after stopping:

```zsh
./jam-usb-internet system-recover
```

`restore` puts the macOS network service order back to the saved order from before the first successful change.

`browser` starts a local SOCKS5 proxy on `127.0.0.1:10808`, opens a dedicated Google Chrome window through it, and forwards traffic through the phone over ADB. This is the Chrome-only fallback.

`proxy` starts the same SOCKS5 proxy and points macOS network services at it. This can help apps that honor macOS proxy settings, but macOS may ignore service-level proxy settings when no Wi-Fi/Ethernet service is connected. Keep the terminal window open. Run `proxy-stop` if the system proxy setting remains enabled after closing it.

## Important Limitation

Many Samsung/older Android phones expose USB tethering as RNDIS. Modern macOS, especially on Apple Silicon, often does not expose that as a native network interface. This utility detects and reports that case, but it cannot force macOS to support a USB network protocol the OS does not load.

Useful references:

- Android ADB docs: https://developer.android.com/studio/command-line/adb
- Current macOS Android USB tethering limitation summary: https://support.speedify.com/article/415-tether-android-mac-usb

If native USB tethering is blocked on your Mac, use `system --mobile-only` for Mac-wide TUN mode. The tool uploads a temporary relay binary to `/data/local/tmp/knock-relay` automatically, starts it through ADB, and removes the ADB forward on stop. Use `browser --mobile-only` only as a Chrome fallback.

If `sing-box` prints `network: missing default interface`, the tool now keeps going: it waits for the TUN address, adds split IPv4 routes manually, and uses local DNS hijacking so disconnected Wi-Fi does not have to provide DNS.

Safety note: full system mode fails closed for relay, DNS, split-route, and cleanup-guard startup failures. It starts `sing-box`, verifies that `127.0.0.1` can answer DNS, verifies that macOS is using the temporary resolver, and verifies the TUN split route before startup checks. A temporary default-route verification failure is allowed as a warning because split routes can still carry Chrome, Discord, git, KakaoTalk, and general TCP/DNS traffic. KakaoTalk reachability remains a strict completion check in `app-check`.

Priority rule: Mac Wi-Fi wins. USB TUN is a fallback for when the Mac itself has no working internet. Use `--force-tun` only for deliberate USB-path testing.

Completion indicators:

- Chrome/web HTTPS reaches `https://www.google.com/generate_204`.
- Discord reaches `https://discord.com/api/v10/gateway` and `gateway.discord.gg:443`.
- Kakao reaches `https://talk.kakao.com` and `talk.kakao.com:443`.
- KakaoTalk/macOS reachability reports `talk.kakao.com` as reachable.
- git can run `git ls-remote https://github.com/git/git.git HEAD`.
- UDP-heavy features such as Discord voice/video are outside the current TCP/DNS milestone.

Current field status:

- Galaxy Wi-Fi path: internet and KakaoTalk work with Mac Wi-Fi off.
- Galaxy LTE path: internet and KakaoTalk work with Mac Wi-Fi off.
- `app-check` has passed in the target tunnel state: DNS, Chrome/web, Discord API/TCP, Kakao HTTPS/TCP, KakaoTalk reachability, and git.
- Normal stop with `system-stop` restores Mac Wi-Fi.
- Forced terminal close is not yet reliable enough to trust; `system-recover` remains the manual fallback and should become a visible Recover button in packaging.
- Switching the Galaxy's own internet path between LTE and Wi-Fi during an active session can briefly interrupt the phone network and terminate the tunnel process. This is deferred to a later reliability stage.

## Distribution Packaging

Packaging work lives in:

```text
/Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet/pkg
```

Build a portable distribution folder and zip:

```zsh
pkg/build-dist.sh
```

The generated zip includes:

- ON / OFF / RECOVER `.command` launchers
- Galaxy setup guide for Note 9 and Fold
- Mac setup guide for Apple Silicon / M3 Pro security prompts
- preinstall/security review for Homebrew dependencies, Android File Transfer, and macOS security policy
- code-signing review for local ad-hoc builds and Developer ID/notarized releases
- usage guide and release checklist
- Android relay binary and sing-box config template

Generated files are written under `pkg/dist/` and are not committed to git.

GUI signing note:

- `ui/build-app.sh` now signs and verifies the completed app bundle.
- The default ad-hoc signature is for local testing.
- External distribution without manual bypass requires Developer ID Application signing and Apple notarization.
- See `pkg/CODE_SIGNING.md`.
