# Mac Setup Guide

대상:

- Apple Silicon MacBook
- MacBook Pro M3 Pro
- macOS 26.x 계열에서 검증 중

## 1. 필수 조건

Mac에 필요한 것:

- 관리자 계정 비밀번호
- Homebrew
- Android platform tools / ADB
- sing-box
- USB-C 데이터 연결
- 새 USB accessory 승인

선택 또는 특정 기능에서만 필요한 것:

- Python 3: `browser` / `proxy` fallback 모드에서 사용한다. 기본 `ON` / `system` 경로에는 필수 선행요건이 아니다.
- git: `app-check`의 git 검증에 사용한다. Mac 개발 도구가 설치되어 있으면 보통 이미 있다.
- zip/unzip/shasum: 배포 zip을 만드는 개발자용 도구다.

필수가 아닌 것:

- `/Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg`
- RNDIS USB tethering driver
- macOS Recovery의 Reduced Security
- SIP 비활성화
- Gatekeeper 비활성화

## 2. 의존성 설치

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

확인:

```zsh
adb version
sing-box version
```

`python3 --version`은 Chrome-only/browser fallback 또는 proxy fallback을 쓸 때만 확인한다.

## 3. macOS USB accessory 승인

Apple Silicon Mac에서는 새 USB/Thunderbolt accessory가 Mac과 통신하기 전에 승인이 필요할 수 있다.

확인할 것:

1. Mac을 잠금 해제한다.
2. Galaxy를 USB로 연결한다.
3. macOS에서 accessory 승인 팝업이 뜨면 허용한다.
4. 필요하면 `System Settings -> Privacy & Security -> Allow accessories to connect` 설정을 확인한다.

보안 원칙:

- SIP를 끄지 않는다.
- Gatekeeper를 끄지 않는다.
- Recovery mode에서 Reduced Security로 낮추지 않는다.
- 불분명한 커널 확장이나 RNDIS 드라이버를 설치하지 않는다.

이 프로젝트는 커널 확장이나 system extension을 설치하지 않는다. `sing-box`를 관리자 권한으로 실행해 macOS의 기존 `utun` 인터페이스와 라우팅/DNS 설정을 임시로 사용한다.

## 4. Android File Transfer 판단

로컬에 다음 파일이 있을 수 있다.

```text
/Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg
```

이 패키지를 쓰기 위해 설치할 필요는 없다.

이유:

- Android File Transfer는 Mac Finder/GUI에서 phone 파일을 옮기는 MTP 계열 도구다.
- 이 프로젝트는 phone 파일 브라우징을 하지 않는다.
- Android relay 바이너리는 `adb push`로 업로드한다.
- phone 인식의 핵심은 Android File Transfer가 아니라 ADB authorization이다.

설치해도 되는 경우:

- 사용자가 별도로 Galaxy 파일을 GUI로 옮기고 싶을 때.

설치해도 해결하지 못하는 문제:

- `adb devices`가 비어 있음
- `adb devices`가 `unauthorized`로 보임
- macOS USB accessory approval이 막힘
- Galaxy에서 USB debugging prompt를 허용하지 않음

## 5. 앱 보안 경고 / quarantine

이 패키지는 현재 코드서명/notarization된 앱이 아니다.

로컬 테스트용 app bundle은 ad-hoc signing으로 구조 검증을 통과한다. 다른 Mac에 경고 없이 배포하려면 Developer ID Application certificate와 Apple notarization이 필요하다. 자세한 내용:

```text
docs/CODE_SIGNING.md
```

배포 zip을 직접 만들었거나 신뢰 가능한 담당자에게 받은 경우에만 다음 중 하나를 사용한다.

권장:

1. Finder에서 `.command` 파일을 Control-click 또는 right-click.
2. `Open`을 선택한다.
3. macOS 경고창에서 다시 `Open`을 선택한다.

ZIP과 함께 받은 `.sha256` 파일을 같은 폴더에 둔다.

```text
jam-usb-internet-<version>.zip
jam-usb-internet-<version>.zip.sha256
```

quarantine 때문에 앱 실행이 막힐 때는 먼저 체크섬을 검증하고, 압축을 푼 배포 폴더에만 quarantine 해제를 적용한다.

```zsh
cd /path/to/download-directory
shasum -a 256 -c jam-usb-internet-<version>.zip.sha256
unzip jam-usb-internet-<version>.zip
xattr -dr com.apple.quarantine jam-usb-internet-<version>
```

주의:

- 체크섬 검증 결과가 `OK`일 때만 다음 단계로 진행한다.
- 출처를 모르는 zip에는 이 명령을 쓰지 않는다.
- 체크섬이 맞지 않으면 압축을 풀거나 실행하지 말고 새 파일을 받는다.
- `xattr`는 압축을 푼 `jam-usb-internet-<version>` 폴더에만 적용한다.
- 이 프로젝트는 USB debugging과 관리자 권한을 사용하므로 신뢰 경계를 명확히 해야 한다.

## 6. 관리자 권한

`ON` / `system` 모드는 다음을 임시로 바꾼다.

- TUN route
- temporary DNS resolver
- ADB forward
- Android relay process

그래서 실행 중 Mac 관리자 비밀번호를 물어볼 수 있다.

정상 종료는 반드시:

```text
Galaxy USB Internet OFF.command
```

또는:

```zsh
./jam-usb-internet system-stop
```

강제 종료 후 인터넷이 꼬이면:

```text
Galaxy USB Internet RECOVER.command
```

또는:

```zsh
./jam-usb-internet system-recover
```

## 7. MacBook Pro M3 Pro 판단

MacBook Pro M3 Pro는 Thunderbolt 4 / USB 4 포트를 가진다. ADB relay 방식에는 충분하다.

다만 native Android USB tethering을 Mac USB LAN으로 인식하는 방식은 공식 Android 문서 기준으로 신뢰하지 않는다. 이 프로젝트는 그 경로를 기본으로 쓰지 않는다.

## 8. cleanup guard 진단

새 Mac에서 다음 오류가 나오면 TUN 라우팅이나 DNS는 변경되지 않은 상태다.

```text
[fail] Could not start abnormal-exit cleanup guard; refusing to modify TUN routes/DNS.
```

다음을 실행한다.

```zsh
./jam-usb-internet guard-check
tail -80 ~/.jam-usb-internet/system-guard.log
```

`guard-check`는 관리자 권한을 확인하고 비정상 종료 복구 가드만 시작했다가 해제한다. USB 인터넷 경로를 활성화하지 않는다.

## 9. 공식 문서 기준

- Homebrew android-platform-tools cask: https://formulae.brew.sh/cask/android-platform-tools
- Homebrew sing-box formula: https://formulae.brew.sh/formula/sing-box
- MacBook Pro M3 Pro technical specs: https://support.apple.com/en-ie/117736
- Apple USB/Thunderbolt accessory security: https://support.apple.com/en-us/102282
- Apple startup security policy: https://support.apple.com/guide/mac-help/change-security-settings-startup-disk-a-mac-mchl768f7291/mac
- Apple safely open apps on Mac: https://support.apple.com/en-us/HT202491
- Android ADB: https://developer.android.com/tools/adb
- Android tethering help: https://support.google.com/android/answer/9059108
