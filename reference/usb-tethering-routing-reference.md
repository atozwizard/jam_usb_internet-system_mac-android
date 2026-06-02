# Android USB Tethering and macOS Routing References

Created: 2026-05-30
Updated: 2026-06-02
Target device: Samsung Galaxy Note 9, Android 10
Target host: macOS 26.5, arm64

## Working Diagnosis

The largest blocker is native recognition: macOS is not exposing the Galaxy Note 9 USB tethering function as a usable network interface. In the native USB tethering path, the Mac must see the phone as a USB Ethernet-like device, then DHCP/routing/DNS can work through that interface. On this machine, that interface does not appear, so native Android USB tethering cannot become the Mac's default network route.

This is distinct from the ADB relay path. ADB can recognize the phone over USB in File Transfer / Android Auto mode and can forward TCP ports to a relay process on Android. That proves USB data and ADB are working, but it does not mean macOS recognized Android USB tethering as a LAN device.

Therefore there are two separate implementation tracks:

1. Native USB tethering:
   - Requires macOS to recognize the phone's USB network function.
   - If the phone exposes an unsupported USB networking protocol, no shell script can turn it into a normal Mac network service.
   - In this project, current evidence says this path is not viable for Galaxy Note 9 + macOS 26.5.

2. ADB relay + Mac TUN / NetworkExtension:
   - Does not require macOS to recognize Android USB tethering.
   - Requires USB debugging, ADB authorization, a relay process on Android, and a Mac-side tunnel/proxy.
   - Can support TCP-heavy apps such as Chrome, git, many chat app API calls.
   - UDP-heavy behavior, such as some Discord voice/video paths, requires additional UDP support or a different tunnel design.

## Source Index

### Google / Android

1. Android Help: "Share a mobile connection by hotspot or tethering on Android"
   - URL: https://support.google.com/android/answer/9059108
   - Key point: Android supports hotspot/tethering by Wi-Fi, Bluetooth, and USB, but the same official page states: "Mac computers can't tether with Android by USB."
   - Impact on this project: This directly supports the diagnosis that native Android USB tethering is not expected to work on Mac in the generic Android support path.

2. Android Open Source Project: "Tethering"
   - URL: https://source.android.com/docs/core/ota/modular-system/tethering
   - Key point: Android's Tethering module shares the Android device's internet connection with client devices over Wi-Fi, USB, Bluetooth, or Ethernet. It includes tethering components and dependencies such as entitlement checks, IpServer, and offload handling.
   - Impact on this project: Android-side tethering exists as a real OS subsystem. The failure is not "Android has no tethering"; it is host/protocol interoperability with macOS for this phone.

3. Android Developers: "Android Debug Bridge (adb)"
   - URL: https://developer.android.com/tools/adb
   - Key point: ADB is the official command-line tool for communicating with an Android device. It supports USB debugging, shell access, file push/pull, and port forwarding with `adb forward`.
   - Impact on this project: The current ADB relay architecture is within the documented ADB capability surface. It is an official development/debugging transport, not native tethering.

### Samsung

4. Samsung Support: "Connection options for your Galaxy phone or tablet"
   - URL: https://www.samsung.com/us/support/answer/ANS10002546/
   - Key point: Samsung describes Galaxy USB connections as supporting functions including file transfer, charging, and tethering internet, while also noting that both devices must support the selected USB function.
   - Impact on this project: The Galaxy may expose a tethering function, but the host Mac still needs compatible support. "Phone can offer tethering" is not sufficient by itself.

5. Samsung Support: "Unable to tether a Galaxy phone to a computer using USB cable"
   - URL: https://www.samsung.com/us/support/troubleshooting/TSG01001516/
   - Key point: Samsung treats USB tethering as a supported Galaxy troubleshooting topic, with cable/device/support conditions.
   - Impact on this project: Useful for phone-side checklist, but it does not override Google's Mac-specific Android USB limitation.

### Apple / macOS

6. Apple Support: "Use an iPhone or iPad to connect your Mac to the internet"
   - URL: https://support.apple.com/guide/mac-help/mchl7594e36f/mac
   - Key point: Apple documents USB internet sharing for iPhone/iPad Personal Hotspot, including a Mac Network settings entry for the iPhone/iPad USB device.
   - Impact on this project: Apple documents USB hotspot integration for Apple mobile devices. This does not imply Android USB tethering support.

7. Apple Support: "Ethernet settings on Mac"
   - URL: https://support.apple.com/guide/mac-help/mh11939/mac
   - Key point: macOS manages wired network services as Ethernet-like services in Network settings.
   - Impact on this project: If native Android USB tethering worked, we would expect an Ethernet-like service/interface to appear here. Current tests show no usable Android USB network interface.

8. Apple Developer Documentation: "Packet tunnel provider"
   - URL: https://developer.apple.com/documentation/networkextension/packet-tunnel-provider
   - Key point: Apple's NetworkExtension packet tunnel provider is the supported framework for a packet-oriented custom VPN/tunnel that forwards system packets through a provider.
   - Impact on this project: A production-quality Mac-wide ADB relay solution should eventually move toward NetworkExtension instead of fragile shell-managed TUN/DNS state.

### Runtime and Distribution Trust

9. Apple Support: "Allow USB and other accessories to connect to your Mac"
   - URL: https://support.apple.com/en-us/102282
   - Key point: Apple Silicon Mac laptops can require explicit approval before a new or unknown USB accessory receives data access. A denied accessory can still charge.
   - Impact on this project: Charging alone does not prove USB data access. On a new M3/M4 Mac, unlock the Mac and approve the Galaxy accessory before diagnosing ADB.

10. Android Developers: "Android Debug Bridge (adb)"
    - URL: https://developer.android.com/tools/adb
    - Key point: USB ADB requires Developer options > USB debugging. Android 4.2.2 and later show an RSA-key dialog that must be acknowledged on the unlocked device before USB debugging and other ADB commands can execute.
    - Impact on this project: If the tool has uploaded the relay, created an ADB forward, and completed relay endpoint checks, the Android RSA authorization boundary has already been crossed successfully.

11. Apple Developer: "Developer ID"
    - URL: https://developer.apple.com/support/developer-id/
    - Key point: Software distributed outside the Mac App Store can use a Developer ID certificate and Apple notarization so Gatekeeper can verify that it is from an identified developer and has not been tampered with.
    - Impact on this project: An ad-hoc signature is useful for local bundle-integrity testing but is not the final external-distribution trust solution.

12. Apple Support: "Safely open apps on your Mac"
    - URL: https://support.apple.com/en-us/HT202491
    - Key point: Gatekeeper checks Developer ID signatures and notarization for software distributed outside the App Store. macOS can report that an app cannot be opened if it detects modification or damage.
    - Impact on this project: A damaged-app warning is a separate distribution-signing problem from a `.command` runtime cleanup-guard failure.

### USB Networking Protocols

13. USB-IF: "CDC Subclass Specification for Ethernet Emulation Model Devices 1.0"
   - URL: https://www.usb.org/sites/default/files/CDC_EEM10.pdf
   - Key point: USB CDC Ethernet-style subclasses define standardized ways to carry Ethernet-like network traffic over USB.
   - Impact on this project: macOS compatibility depends on the phone exposing a USB networking function/protocol the Mac can bind as a network service.

14. USB-IF document library: "Network Control Model Devices Specification v1.0"
    - URL: https://www.usb.org/document-library/network-control-model-devices-specification-v10
    - Key point: CDC-NCM is a USB-IF network control model for USB networking.
    - Impact on this project: Modern Android devices that expose CDC-NCM are more likely to work as native USB network devices on macOS than older RNDIS-only devices.

15. Microsoft Learn: "Overview of Remote NDIS (RNDIS)"
    - URL: https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-remote-ndis--rndis-
    - Key point: RNDIS is a Microsoft-defined network device model over buses such as USB, and Microsoft provides the Windows driver stack for it.
    - Impact on this project: Older Android USB tethering often aligns with Windows/RNDIS expectations. If the Galaxy Note 9 exposes RNDIS-like tethering, macOS may not bind it natively.

16. Microsoft Learn: "USB device class drivers included in Windows"
    - URL: https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/supported-usb-classes
    - Key point: Windows has its own USB class driver support matrix, including NCM support in modern versions.
    - Impact on this project: USB tethering interoperability is OS/driver/protocol-specific, not guaranteed by USB cable detection alone.

### Papers / Books / Research-Grade Sources

17. "(In)Secure Android Debugging: Security analysis and lessons learned"
    - URL: https://www.sciencedirect.com/science/article/pii/S016740481831023X
    - DOI: https://doi.org/10.1016/j.cose.2018.12.010
    - Key point: Academic security analysis of Android debugging and USB-related attack surfaces, including ADB-related risks.
    - Impact on this project: ADB relay mode is practical, but USB debugging should be treated as a trusted-local-device mode and disabled when not needed.

18. "The Android Platform Security Model (2023)"
    - URL: https://research.google/pubs/the-android-platform-security-model-2023/
    - arXiv: https://arxiv.org/abs/1904.05572
    - Key point: Research-grade description of Android's security model and tradeoffs.
    - Impact on this project: Helps frame why privileged network/tethering behavior is guarded by user settings, carrier policy, and system components.

19. "Unboxing Android USB: A hands on approach with real world examples", Chapter 4: USB Tethering
    - URL: https://www.oreilly.com/library/view/unboxing-android-usb/9781430262084/9781430262084_Ch04.xhtml
    - Key point: Technical book coverage of Android USB framework, RNDIS overview, Android USB tethering framework, and reverse tethering.
    - Impact on this project: Useful background for implementation decisions, but less authoritative than Android/AOSP/Apple/Microsoft/USB-IF documentation.

## Practical Conclusions for `jam-usb-internet`

1. Treat native Android USB tethering as unsupported for this Mac + Galaxy Note 9 combination unless macOS exposes a real Android USB network interface.

2. The correct phone mode for the current workaround is:
   - USB mode: File Transfer / Android Auto
   - USB debugging: enabled and authorized
   - Android internet source: LTE or Wi-Fi
   - Android USB tethering: off for the ADB relay path

3. The current tool must not assume "USB tethering on phone" means "Mac network interface exists." These are different layers.

4. The roadmap should focus on one of these:
   - Short term: ADB relay + sing-box TUN failover watcher for TCP-oriented Mac-wide internet.
   - Medium term: Add UDP support if Discord voice/video is required.
   - Long term: Native macOS NetworkExtension packet tunnel app.
   - Alternative hardware path: use a travel router or phone/device that exposes CDC-NCM and appears as a Mac Ethernet service.

## Verification Commands

Use these to distinguish native USB tethering from ADB relay:

```zsh
system_profiler SPUSBDataType
networksetup -listallhardwareports
ifconfig
route -n get 1.1.1.1
adb devices
adb forward --list
```

Expected native USB tethering success signal:

- A new Ethernet-like service or hardware port appears when Android USB tethering is enabled.
- A new `enX`/USB network interface receives an IP address.
- The default route can point through that USB network interface.

Expected ADB relay success signal:

- `adb devices` shows the Galaxy as `device`.
- `adb forward tcp:18080 tcp:18080` exists.
- SOCKS or TUN traffic can be carried through the Android relay even though no new macOS USB Ethernet service appears.
