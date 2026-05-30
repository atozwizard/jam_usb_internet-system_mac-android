# Galaxy Setup Guide

대상:

- Samsung Galaxy Note 9
- Samsung Galaxy Fold / Galaxy Z Fold 계열

목표:

```text
Mac <-> USB/ADB <-> Galaxy relay <-> Galaxy Wi-Fi 또는 LTE <-> Internet
```

이 프로젝트의 기본 경로는 Android `USB tethering`이 아니다. Galaxy는 `File Transfer / Android Auto` 모드로 두고, ADB로 Android relay를 실행한다.

## 1. 필수 조건

- 데이터 전송 가능한 USB 케이블
- Galaxy 잠금 해제 가능
- Galaxy Wi-Fi 또는 LTE/mobile data 연결 가능
- 개발자 옵션 활성화
- USB debugging 활성화
- Mac의 ADB RSA key 승인
- USB 연결 모드: `File Transfer / Android Auto`
- Android `USB tethering`: 꺼둠

## 2. Note 9 개발자 옵션 켜기

일반적인 Samsung Android 10 / One UI 흐름:

1. `Settings`를 연다.
2. `About phone`으로 들어간다.
3. `Software information`으로 들어간다.
4. `Build number`를 7번 누른다.
5. 잠금 PIN/패턴을 요구하면 입력한다.
6. `Developer options`가 활성화됐는지 확인한다.

그 다음:

1. `Settings`로 돌아간다.
2. `Developer options`로 들어간다.
3. `USB debugging`을 켠다.
4. Mac과 USB로 연결한다.
5. phone 화면에 `Allow USB debugging?`가 뜨면 허용한다.

문제가 생기면:

- `adb devices`가 `unauthorized`이면 Galaxy 화면을 켜고 USB debugging 허용 창을 확인한다.
- 허용 창이 안 뜨면 USB를 뽑았다가 다시 연결한다.
- `Developer options -> Revoke USB debugging authorizations`를 실행한 뒤 다시 연결하면 authorization prompt가 다시 뜰 수 있다.

## 3. Galaxy Fold / Z Fold 개발자 옵션 켜기

Fold 계열도 원리는 같다.

1. `Settings`를 연다.
2. `About phone`으로 들어간다.
3. `Software information`으로 들어간다.
4. `Build number`를 7번 누른다.
5. `Developer options`에서 `USB debugging`을 켠다.
6. Mac 연결 후 ADB authorization prompt를 허용한다.

모델과 One UI 버전에 따라 메뉴 이름은 약간 다를 수 있지만 핵심은 `Software information -> Build number -> Developer options -> USB debugging`이다.

Fold 계열에서 추가로 확인할 것:

- 접힌 상태/펼친 상태와 무관하게 USB debugging prompt는 현재 켜진 화면에 뜬다.
- 화면 잠금 상태에서는 ADB authorization prompt를 놓칠 수 있으므로 반드시 잠금을 해제한다.
- 처음 연결한 Mac이면 RSA fingerprint 확인 창에서 `Always allow from this computer`를 선택할 수 있다.

## 4. USB 연결 모드

USB를 연결한 뒤 Galaxy 알림창에서 USB 알림을 누른다.

선택:

```text
File Transfer / Android Auto
```

선택하지 말 것:

```text
USB tethering
Charge only
```

왜냐하면 현재 프로젝트는 macOS가 Android USB LAN을 인식하는 방식이 아니라, 파일전송/MTP 모드에서 살아있는 ADB 연결을 사용하기 때문이다.

`USB tethering`은 이 프로젝트의 기본 경로가 아니다. Google Android Help 기준으로 Mac은 Android와 USB tethering을 할 수 없다고 안내되어 있으므로, Mac에서 Galaxy를 USB LAN처럼 인식시키는 방식은 기본 성공 조건으로 두지 않는다.

## 5. Galaxy 인터넷 상태

둘 중 하나가 켜져 있으면 된다.

- Galaxy Wi-Fi 연결
- Galaxy LTE/mobile data 연결

주의:

- 터널 실행 중 Galaxy의 인터넷 경로를 LTE에서 Wi-Fi로 바꾸면 잠시 끊기는 순간 터널 프로세스가 종료될 수 있다.
- 이 문제는 후속 안정화 과제다.

## 6. 확인 명령

Mac에서:

```zsh
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.product.cpu.abilist
```

정상 조건:

- `adb devices`에 `device`로 표시된다.
- `unauthorized`가 보이면 Galaxy 화면에서 USB debugging 허용을 눌러야 한다.
- ABI 목록에 `arm64-v8a`가 포함되어야 한다.

## 7. 공식 문서 기준

- Android ADB: https://developer.android.com/tools/adb
- Android developer options: https://developer.android.com/studio/debug/dev-options
- Android tethering help: https://support.google.com/android/answer/9059108
- Samsung USB options: https://www.samsung.com/us/support/answer/ANS10002546/
- Android ABI: https://developer.android.com/ndk/guides/abis
