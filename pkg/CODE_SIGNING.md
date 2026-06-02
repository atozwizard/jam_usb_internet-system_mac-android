# macOS App Signing and Notarization

Date: 2026-06-01

## 1. Problem

`Jam USB Internet.app` is a SwiftUI wrapper around the working CLI.

The original UI build script compiled the Mach-O executable and copied `Info.plist`, but did not sign the completed `.app` bundle.

Observed verification failure:

```text
code has no resources but signature indicates they must be present
```

Cause:

- `swiftc` produced an arm64 executable with a linker ad-hoc signature.
- The completed `.app` bundle was not signed afterward.
- The bundle therefore lacked:

  ```text
  Contents/_CodeSignature/CodeResources
  ```

- Gatekeeper can present this malformed bundle as damaged.

## 2. Fixed Local Build

`ui/build-app.sh` now signs the completed app bundle and verifies it.

Default:

```zsh
ui/build-app.sh
```

This uses:

```text
ad-hoc signing
```

Purpose:

- local development
- structural validation
- package integrity testing

The build must pass:

```zsh
codesign --verify --deep --strict --verbose=2 "ui/build/Jam USB Internet.app"
```

## 3. External Distribution Requirement

Ad-hoc signing is not enough for a polished external download.

For an app distributed outside the Mac App Store without manual bypass steps, use:

```text
Developer ID Application certificate
Apple notarization
```

Apple documentation:

- Signing Mac software with Developer ID:
  https://developer.apple.com/developer-id/
- Notarizing macOS software before distribution:
  https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Gatekeeper and runtime protection:
  https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web
- Safely open apps on your Mac:
  https://support.apple.com/en-us/HT202491

## 4. Developer ID Build

Check available identities:

```zsh
security find-identity -v -p codesigning
```

Build with a Developer ID identity:

```zsh
JAM_USB_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  pkg/build-dist.sh
```

The build script adds:

```text
--options runtime
--timestamp
```

when a non-ad-hoc identity is supplied.

## 5. Notarization

After Developer ID signing, notarize the distribution artifact using Apple `notarytool`, then staple the ticket to the app before final release packaging.

Example preparation:

```zsh
xcrun notarytool store-credentials jam-usb-internet
```

Use the Apple documentation above for the credential and submission flow. Do not invent or hard-code Apple credentials in this repository.

## 6. Gatekeeper Checks

Structural signature check:

```zsh
codesign --verify --deep --strict --verbose=2 "Jam USB Internet.app"
```

Gatekeeper assessment:

```zsh
spctl --assess --type execute --verbose=4 "Jam USB Internet.app"
```

Expected:

- ad-hoc local build:
  - `codesign --verify` passes
  - `spctl --assess` may reject
- Developer ID + notarized release:
  - both checks pass on a clean release artifact

## 7. Apple Silicon Compatibility

Current app executable:

```text
Mach-O 64-bit executable arm64
```

This is the correct architecture for M3 and M4 MacBook models.

The observed damaged-app error is a signing/package-integrity problem, not an M3/M4 CPU incompatibility.

## 8. Local Test Bypass

For a trusted local development build only, the user may right-click the app and choose `Open`, or remove quarantine after verifying the supplied SHA256 checksum file.

```zsh
cd /path/to/download-directory
shasum -a 256 -c jam-usb-internet-<version>.zip.sha256
unzip jam-usb-internet-<version>.zip
xattr -dr com.apple.quarantine jam-usb-internet-<version>
```

Continue only if checksum verification prints `OK`. Do not remove quarantine from an unknown or checksum-mismatched ZIP. This is not the final distribution strategy.

Do not:

- disable SIP
- disable Gatekeeper globally
- lower macOS Startup Security
