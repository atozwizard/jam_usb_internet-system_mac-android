# Preinstall and Security Review

Date: 2026-05-30

목표:

```text
이 패키지를 쓰기 위해 무엇을 설치해야 하는지,
그리고 무엇을 설치하거나 보안을 낮추지 않아도 되는지 명확히 구분한다.
```

## 1. 결론

필수:

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

필수 아님:

- `/Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg`
- Android File Transfer
- RNDIS 드라이버
- macOS Recovery의 Reduced Security
- SIP 비활성화
- Gatekeeper 비활성화
- 커널 확장 허용

선택:

- Python 3: `browser` / `proxy` fallback 모드에서만 필요.
- git: `app-check`의 git 검증에 필요.
- Go: Android relay를 다시 빌드할 때만 필요. 배포 패키지에는 relay 바이너리가 포함된다.

## 2. 왜 android-platform-tools가 필요한가

이 패키지는 Android Debug Bridge를 사용한다.

ADB 역할:

- Galaxy USB debugging 연결 확인
- Android relay 바이너리 업로드
- Android relay 실행
- Mac `tcp:18080`을 Android `tcp:18080`으로 forward

설치:

```zsh
brew install --cask android-platform-tools
```

확인:

```zsh
adb version
adb devices
```

공식 문서:

- Android ADB: https://developer.android.com/tools/adb
- Android SDK Platform-Tools: https://developer.android.com/tools/releases/platform-tools
- Homebrew android-platform-tools cask: https://formulae.brew.sh/cask/android-platform-tools

## 3. 왜 sing-box가 필요한가

`system` / `ON` 모드는 Mac 전체 TCP/DNS 트래픽을 TUN으로 받아 Android relay로 보낸다.

`sing-box` 역할:

- macOS `utunX` TUN 생성
- 로컬 DNS 처리
- Mac 앱 TCP 트래픽을 local SOCKS outbound로 전달

설치:

```zsh
brew install sing-box
```

확인:

```zsh
sing-box version
```

공식 문서:

- sing-box: https://sing-box.sagernet.org
- Homebrew sing-box formula: https://formulae.brew.sh/formula/sing-box

## 4. Android File Transfer 판단

로컬 파일:

```text
/Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg
```

판정:

```text
이 프로젝트의 필수 선행 설치물이 아니다.
```

이유:

- Android File Transfer는 Mac에서 Android 파일을 GUI로 복사하기 위한 MTP 도구다.
- 이 프로젝트는 Galaxy 파일 시스템을 GUI로 탐색하지 않는다.
- relay 바이너리는 `adb push`로 업로드한다.
- 연결 성공 조건은 `adb devices`가 `device`로 보이는 것이다.

사용해도 되는 경우:

- 사용자가 별도로 사진/파일을 수동 복사하고 싶을 때.

사용해도 해결되지 않는 경우:

- ADB가 설치되어 있지 않음
- USB debugging이 꺼져 있음
- Galaxy 화면에서 ADB RSA key를 승인하지 않음
- Mac에서 USB accessory approval을 허용하지 않음

## 5. macOS 보안 등급 판단

판정:

```text
Recovery mode에 들어가 보안 등급을 낮출 필요가 없다.
```

하지 말 것:

- Reduced Security로 변경
- SIP 비활성화
- Gatekeeper 비활성화
- 불명확한 RNDIS kernel extension 설치

이유:

- 이 프로젝트는 macOS kernel extension을 설치하지 않는다.
- 이 프로젝트는 NetworkExtension system extension을 설치하지 않는다.
- `sing-box`는 관리자 권한으로 실행되어 macOS의 기존 TUN/route/DNS 기능을 사용한다.
- Native Android USB tethering/RNDIS를 성공시키기 위해 보안을 낮추는 방향은 이 프로젝트의 기본 경로가 아니다.

필요할 수 있는 보안 동작:

- Apple Silicon Mac에서 새 USB/Thunderbolt accessory 연결을 허용한다.
- 서명되지 않은 `.command` 파일은 Finder에서 Control-click 또는 right-click 후 `Open`으로 실행한다.
- 직접 빌드한 신뢰 가능한 배포물에 한해 quarantine 제거를 사용할 수 있다.

```zsh
xattr -dr com.apple.quarantine /path/to/jam-usb-internet-<version>
```

공식 문서:

- Apple accessory security: https://support.apple.com/en-us/102282
- Apple startup security policy: https://support.apple.com/guide/mac-help/change-security-settings-startup-disk-a-mac-mchl768f7291/mac

## 6. Galaxy 선행 설정

필수:

- Developer options 활성화
- USB debugging 활성화
- Galaxy USB mode: `File Transfer / Android Auto`
- USB debugging RSA prompt 허용
- Galaxy Wi-Fi 또는 LTE/mobile data 연결
- Android `USB tethering` OFF

개발자 옵션 활성화:

```text
Settings
-> About phone
-> Software information
-> Build number 7번 탭
-> Developer options
-> USB debugging ON
```

공식 문서:

- Android developer options: https://developer.android.com/studio/debug/dev-options
- Samsung USB options: https://www.samsung.com/us/support/answer/ANS10002546/

## 7. Self-Critique

검토 중 바로잡은 점:

- `brew install android-platform-tools`라고만 쓰는 것보다 `brew install --cask android-platform-tools`가 더 정확하다.
- `AndroidFileTransfer.dmg`가 있더라도 이 프로젝트의 ADB relay 경로에는 필요하지 않다.
- Mac에서 Android USB tethering/RNDIS를 억지로 살리기 위해 보안등급을 낮추는 방향은 목표와 다르다.
- 사용자용 문서에는 Note 9/Fold 개발자모드 진입 절차와 Mac accessory approval을 앞쪽에 배치해야 한다.

## 8. Final Recommendation

배포 사용자에게 요구할 것은 다음만으로 제한한다.

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

그리고 다음은 명시적으로 요구하지 않는다.

```text
AndroidFileTransfer.dmg 설치
Recovery mode Reduced Security
SIP off
Gatekeeper off
RNDIS driver
```

