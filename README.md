# G560Studio

Logitech G560을 G HUB 없이 macOS 메뉴바에서 제어합니다.
사운드 반응 LightSync(4존), 서브우퍼 레벨, 10밴드 하드웨어 EQ, 볼륨, 프로필.
메뉴바 아이콘은 재생 중인 소리와 현재 조명 색으로 실시간 렌더링됩니다.

시작한 이유: macOS G HUB에는 사운드 반응 조명이 없고, 서브우퍼를 줄이려면 G HUB가 필요합니다. 둘 다 되게 만들었습니다.

## 요구 사항
- macOS 14.2+ (Core Audio Process Tap), Xcode 26
- Logitech G560 (USB)

## 빌드 · 설치
```bash
scripts/bundle.sh release && cp -R build/G560Studio.app /Applications/
```
첫 실행 시 "시스템 오디오 녹음" 권한을 허용하세요. 녹음·저장은 하지 않고 레벨 계산에만 씁니다.

## 테스트
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

## CLI / 복구
```bash
swift run g560ctl status
swift run g560ctl led all 00A0FF
swift run g560ctl woofer 40
swift run g560ctl eq 0 0 0 0 0 0 0 0 0 0
swift run g560ctl restore          # 우퍼 40, EQ Flat (공장값)
tools/.venv/bin/python tools/g560probe.py restore   # Python 쪽 복구 (factory-defaults.json 기준)
```

## 프로토콜
[docs/protocol.md](docs/protocol.md) — 실측한 HID++ 명령. 장치에 쓰는 명령은 재전송 검증된 3개(LED, 서브우퍼, EQ)뿐입니다.
펌웨어/리셋 계열 기능은 호출하지 않습니다. EQ는 장치 EEPROM에 저장되므로 슬라이더를 놓을 때만 씁니다.

## 구조
- `Sources/G560Core` — HID++ 패킷, 장치, 조명 엔진, 오디오 탭, 프로필 (UI 없음)
- `Sources/G560Studio` — SwiftUI 메뉴바 앱
- `Sources/g560ctl` — CLI
- `tools/` — Phase 0 프로토콜 캡처 스크립트

## 라이선스
코드는 [MIT](LICENSE). `Assets/`의 로고·제품 사진은 Logitech 소유이며 이 라이선스에 포함되지 않습니다 (개인 사용 목적으로만 포함).
이 프로젝트는 Logitech과 무관한 개인 프로젝트입니다.
