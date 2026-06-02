# jam-usb-internet Packaging

Date: 2026-05-30

이 디렉토리는 배포용 묶음을 만드는 작업 공간이다.

현재 패키징 방식은 설치형 macOS `.pkg`가 아니라 portable folder + zip 이다. 이 선택은 의도적이다.

- 사용자는 `Jam USB Internet.app`으로 ON/OFF/RECOVER와 상태를 한 화면에서 다룬다.
- `.command` fallback도 같은 폴더에 남긴다.
- 아직 강제 터미널 종료 자동복구가 완전히 신뢰할 수준은 아니므로 `RECOVER`가 눈에 보여야 한다.
- macOS 관리자 권한, ADB 승인, Galaxy USB 모드 같은 수동 확인 단계가 필요하다.
- 코드 서명과 notarization 없이 설치형 `.pkg`를 만들면 오히려 보안 경고와 제거 경로가 불명확해질 수 있다.

## Build

배포 zip 생성:

```zsh
cd /Users/twentyflags/twentyflags/knocklab/tools/jam-usb-internet
pkg/build-dist.sh
```

결과물:

```text
pkg/dist/jam-usb-internet-<version>/
pkg/dist/jam-usb-internet-<version>.zip
pkg/dist/jam-usb-internet-<version>.zip.sha256
```

`pkg/dist/`는 생성물이라 git에 커밋하지 않는다. GitHub 배포가 필요하면 이 zip을 Release asset으로 올린다.

다른 Mac에 무료 배포할 때는 ZIP과 `.sha256` 파일을 함께 전달한다. 사용자는 체크섬을 먼저 검증하고, 신뢰 가능한 ZIP에서 압축을 푼 폴더에만 quarantine 해제를 적용한다.

```zsh
cd /path/to/download-directory
shasum -a 256 -c jam-usb-internet-<version>.zip.sha256
unzip jam-usb-internet-<version>.zip
xattr -dr com.apple.quarantine jam-usb-internet-<version>
```

## Package Contents

배포 폴더에는 다음이 들어간다.

- `Jam USB Internet.app`
- `jam-usb-internet`
- `Galaxy USB Internet ON.command`
- `Galaxy USB Internet OFF.command`
- `Galaxy USB Internet RECOVER.command`
- `Galaxy USB Internet.command`
- `Galaxy System Stop.command`
- `Galaxy Browser Fallback.command`
- `adb-socks-proxy.py`
- `configs/sing-box.template.json`
- `android-relay/bin/arm64-v8a/knock-relay`
- 사용 문서:
  - `docs/GALAXY_SETUP.md`
  - `docs/MAC_SETUP.md`
  - `docs/USAGE.md`
  - `docs/PREINSTALL_SECURITY_REVIEW.md`
  - `docs/CODE_SIGNING.md`
  - `docs/RELEASE_CHECKLIST.md`
  - `docs/reference/`

## Distribution Rule

배포 전 필수 확인:

```zsh
zsh -n jam-usb-internet
for f in *.command; do zsh -n "$f"; done
python3 -m json.tool configs/sing-box.template.json >/dev/null
sing-box check -c configs/sing-box.template.json
(cd android-relay && GOCACHE="$PWD/.gocache" go test ./...)
./jam-usb-internet doctor --json >/dev/null
./jam-usb-internet system-status --json >/dev/null
./jam-usb-internet guard-check
./jam-usb-internet app-check
ui/build-app.sh
pkg/build-dist.sh
```

GUI 앱 소스는 `ui/JamUSBInternet/`에 있고, `ui/build-app.sh`가 `Jam USB Internet.app`을 만든다.

`ui/build-app.sh`는 완성된 app bundle을 서명하고 `codesign --verify --deep --strict`로 검증한다. 기본값은 로컬 테스트용 ad-hoc 서명이다. 외부 배포용 Gatekeeper 통과 빌드는 Developer ID Application certificate와 Apple notarization이 필요하다. 자세한 내용은 `pkg/CODE_SIGNING.md`를 본다.

## Next Packaging Stage

- Developer ID code signing / notarization for the GUI app
- menu bar on/off/recover companion
- optional signed/notarized `.pkg` installer
