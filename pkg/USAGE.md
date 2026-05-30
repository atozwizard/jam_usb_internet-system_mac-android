# Usage Guide

## 1. 가장 안전한 사용 흐름

1. Galaxy에서 Wi-Fi 또는 LTE를 켠다.
2. Galaxy를 Mac에 USB 데이터 케이블로 연결한다.
3. Galaxy USB 모드를 `File Transfer / Android Auto`로 둔다.
4. Galaxy 화면에서 USB debugging 허용을 확인한다.
5. Mac에서 다음 파일을 실행한다.

```text
Galaxy USB Internet ON.command
```

6. 사용 중에는 열린 Terminal 창을 닫지 않는다.
7. 끝낼 때는 다음 파일을 실행한다.

```text
Galaxy USB Internet OFF.command
```

8. 인터넷이 꼬였거나 창을 강제로 닫았다면 다음 파일을 실행한다.

```text
Galaxy USB Internet RECOVER.command
```

## 2. 완료 지표

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

## 3. 상태 확인

```zsh
./jam-usb-internet system-status
```

확인할 것:

- `sing-box` process가 실행 중인지
- ADB forward가 있는지
- Android relay가 실행 중인지
- temporary DNS resolver가 active인지
- route to `1.1.1.1`이 `utunX` 또는 정상 Wi-Fi로 가는지

## 4. 강제종료 주의

현재 알려진 제한:

```text
Terminal 창을 강제로 닫으면 일반 Mac 인터넷이 복구되지 않을 수 있다.
```

이때는:

```text
Galaxy USB Internet RECOVER.command
```

을 실행한다.

## 5. Galaxy 네트워크 전환 주의

실행 중 Galaxy의 인터넷을 LTE에서 Wi-Fi로 바꾸면, 전환 순간의 끊김 때문에 터널이 종료될 수 있다.

대응:

1. `OFF` 또는 `RECOVER`를 실행한다.
2. Galaxy 네트워크가 안정된 뒤 `ON`을 다시 실행한다.

## 6. CLI 사용

배포 폴더에서:

```zsh
./jam-usb-internet doctor
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

