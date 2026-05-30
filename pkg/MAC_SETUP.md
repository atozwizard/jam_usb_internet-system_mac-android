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
- Python 3
- USB-C 데이터 연결
- 새 USB accessory 승인

## 2. 의존성 설치

```zsh
brew install android-platform-tools
brew install sing-box
```

확인:

```zsh
adb version
sing-box version
python3 --version
```

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
- 불분명한 커널 확장이나 RNDIS 드라이버를 설치하지 않는다.

## 4. 앱 보안 경고 / quarantine

이 패키지는 현재 코드서명/notarization된 앱이 아니다.

배포 zip을 직접 만든 신뢰 가능한 파일로 쓰는 경우에만 다음 중 하나를 사용한다.

권장:

1. Finder에서 `.command` 파일을 Control-click 또는 right-click.
2. `Open`을 선택한다.
3. macOS 경고창에서 다시 `Open`을 선택한다.

로컬에서 직접 빌드한 zip을 풀었고 quarantine 때문에 실행이 막힐 때:

```zsh
xattr -dr com.apple.quarantine /path/to/jam-usb-internet-<version>
```

주의:

- 출처를 모르는 zip에는 이 명령을 쓰지 않는다.
- 이 프로젝트는 USB debugging과 관리자 권한을 사용하므로 신뢰 경계를 명확히 해야 한다.

## 5. 관리자 권한

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

## 6. MacBook Pro M3 Pro 판단

MacBook Pro M3 Pro는 Thunderbolt 4 / USB 4 포트를 가진다. ADB relay 방식에는 충분하다.

다만 native Android USB tethering을 Mac USB LAN으로 인식하는 방식은 공식 Android 문서 기준으로 신뢰하지 않는다. 이 프로젝트는 그 경로를 기본으로 쓰지 않는다.

## 7. 공식 문서 기준

- MacBook Pro M3 Pro technical specs: https://support.apple.com/en-ie/117736
- Apple USB/Thunderbolt accessory security: https://support.apple.com/en-us/102282
- Android ADB: https://developer.android.com/tools/adb
- Android tethering help: https://support.google.com/android/answer/9059108

