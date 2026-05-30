# jam-usb-internet Packaging

Date: 2026-05-30

이 디렉토리는 배포용 묶음을 만드는 작업 공간이다.

현재 패키징 방식은 설치형 macOS `.pkg`가 아니라 portable folder + zip 이다. 이 선택은 의도적이다.

- 사용자는 폴더를 열고 `ON`, `OFF`, `RECOVER` 실행 파일을 직접 볼 수 있다.
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

## Package Contents

배포 폴더에는 다음이 들어간다.

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
./jam-usb-internet app-check
pkg/build-dist.sh
```

## Next Packaging Stage

나중에 안정화되면 다음 단계로 간다.

- signed `.app` wrapper
- menu bar on/off/recover
- status indicator
- optional signed/notarized `.pkg` installer

