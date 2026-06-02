# Usage Guide

## 1. 신뢰 가능한 ZIP을 다른 Mac에서 열기

무료 배포 ZIP은 신뢰 가능한 담당자에게 받은 파일에 한해 quarantine을 해제한다. ZIP과 `.sha256` 파일을 같은 폴더에 둔다.

```zsh
cd /path/to/download-directory
shasum -a 256 -c jam-usb-internet-<version>.zip.sha256
unzip jam-usb-internet-<version>.zip
xattr -dr com.apple.quarantine jam-usb-internet-<version>
cd jam-usb-internet-<version>
```

체크섬 검증 결과가 `OK`일 때만 진행한다. 출처를 모르는 ZIP이나 체크섬이 일치하지 않는 ZIP에는 `xattr`를 실행하지 않는다. Gatekeeper 전체 비활성화, SIP 비활성화, macOS Startup Security 하향은 하지 않는다.

## 2. 가장 안전한 사용 흐름

0. 처음 한 번 Mac에 의존성을 설치한다.

```zsh
brew install --cask android-platform-tools
brew install sing-box
```

1. Galaxy에서 Wi-Fi 또는 LTE를 켠다.
2. Galaxy 개발자 옵션과 USB debugging을 켠다.
3. Galaxy를 Mac에 USB 데이터 케이블로 연결한다.
4. Mac에서 새 USB accessory 허용 창이 뜨면 허용한다.
5. Galaxy USB 모드를 `File Transfer / Android Auto`로 둔다.
6. Galaxy 화면에서 USB debugging 허용을 확인한다.
7. Mac에서 `Jam USB Internet.app`을 실행한다.
8. 앱 상단의 시작 전 확인(ADB, sing-box, USB debugging)이 통과했는지 본다.
9. **[USB 인터넷 켜기]**를 누른다. 관리자 비밀번호를 묻면 입력한다.
10. 사용 중에는 앱을 닫지 않는다. 로그 패널에서 `[ok] System mode is running.`을 확인한다.
11. 끝낼 때는 앱의 **[끄기]**를 사용한다.
12. 인터넷이 꼬였거나 앱/터미널을 강제로 닫았다면 앱의 **[복구]**를 사용한다.

### Fallback: `.command` 파일

Gatekeeper 경고나 GUI sudo 문제가 있으면 터미널 fallback을 쓴다.

```text
Galaxy USB Internet ON.command
Galaxy USB Internet OFF.command
Galaxy USB Internet RECOVER.command
```

## 3. 완료 지표

다음이 되면 현재 TCP/DNS 목표는 통과다.

- Chrome/web 접속 가능
- Claude 같은 웹 앱 접속 가능
- Discord text/API 접속 가능
- KakaoTalk 접속 가능
- git over HTTPS 가능

명령 확인:

```zsh
./jam-usb-internet app-check
```

성공 예:

```text
[ok] DNS works through current macOS resolver.
[ok] Chrome/web HTTPS reachable
[ok] Discord gateway API HTTPS reachable
[ok] Discord gateway TCP reachable
[ok] Kakao HTTPS reachable
[ok] Kakao TCP reachable
[ok] KakaoTalk macOS reachability
[ok] git over HTTPS reachable
[ok] App connectivity check passed.
```

## 4. 상태 확인

앱 상단 상태 줄이 3초마다 갱신된다. 터미널에서는:

```zsh
./jam-usb-internet system-status
./jam-usb-internet system-status --json
```

확인할 것:

- `sing-box` process가 실행 중인지
- ADB forward가 있는지
- Android relay가 실행 중인지
- temporary DNS resolver가 active인지
- route to `1.1.1.1`이 `utunX` 또는 정상 Wi-Fi로 가는지

## 5. 강제종료 주의

현재 알려진 제한:

```text
Terminal 창을 강제로 닫으면 일반 Mac 인터넷이 복구되지 않을 수 있다.
```

이때는:

```text
Galaxy USB Internet RECOVER.command
```

을 실행한다.

## 6. Galaxy 네트워크 전환 주의

실행 중 Galaxy의 인터넷을 LTE에서 Wi-Fi로 바꾸면, 전환 순간의 끊김 때문에 터널이 종료될 수 있다.

대응:

1. `OFF` 또는 `RECOVER`를 실행한다.
2. Galaxy 네트워크가 안정된 뒤 `ON`을 다시 실행한다.

## 7. CLI 사용

배포 폴더에서:

```zsh
./jam-usb-internet doctor
./jam-usb-internet guard-check
./jam-usb-internet system --check-only
./jam-usb-internet system
./jam-usb-internet app-check
./jam-usb-internet system-stop
./jam-usb-internet system-recover
```

Galaxy LTE만 강제로 쓰고 싶을 때:

```zsh
./jam-usb-internet system --mobile-only
```

주의:

`--mobile-only`는 phone Wi-Fi를 끄고 mobile data를 켜도록 Android에 요청한다. Galaxy 네트워크를 직접 바꾸는 일이므로 필요할 때만 쓴다.

## 8. 새 Mac에서 cleanup guard 확인

새 Mac에서 다음 오류가 나오면:

```text
[fail] Could not start abnormal-exit cleanup guard; refusing to modify TUN routes/DNS.
```

먼저 라우팅과 DNS를 바꾸지 않는 진단을 실행한다.

```zsh
./jam-usb-internet guard-check
```

`guard-check`는 관리자 권한 확인, `launchctl` 가드 시작, 정상 해제만 검증한다. `launchctl` 경로가 실패하거나 늦으면 대체 `nohup` 경로도 시도한다. USB 인터넷 라우팅은 설치하지 않는다.

패키지를 `Downloads`, `Desktop`, `Documents` 아래에서 실행하면 privileged `launchctl`이 해당 스크립트를 다시 열지 못할 수 있다. 이 경우 도구는 기다리지 않고 `nohup` 가드 fallback을 바로 사용한다. fallback 가드는 root 소유 프로세스일 수 있으므로 `ps` 기반 생존 확인을 사용한다.

실패하면 다음 로그를 전달한다.

```zsh
tail -80 ~/.jam-usb-internet/system-guard.log
```

## 9. 설치하지 않아도 되는 것

다음은 기본 사용에 필요 없다.

- `/Users/twentyflags/twentyflags/tools/AndroidFileTransfer.dmg`
- RNDIS 드라이버
- Recovery mode의 Reduced Security
- SIP 비활성화
- Gatekeeper 비활성화

필요한 것은 ADB와 sing-box다. Android File Transfer는 GUI 파일 전송용이고, 이 패키지는 `adb push`로 Android relay를 올린다.
