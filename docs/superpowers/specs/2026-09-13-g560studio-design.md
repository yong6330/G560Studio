# G560Studio — 설계 문서

날짜: 2026-09-13
상태: 승인됨

## 목적

Logitech G560 스피커를 G HUB 없이 macOS 메뉴바 앱에서 제어한다.
- LightSync 조명 (고정색 / 사운드 반응 / 컬러 사이클·브리딩)
- 출력: 볼륨, 우퍼 레벨, 하드웨어 EQ
- 프로필 저장 / 수동 전환
- 메뉴바 아이콘이 재생 중 소리와 존 색상에 실시간 반응

시작 이유: G HUB macOS 버전은 사운드 반응 LightSync를 제공하지 않고, 우퍼 조절을 하려면 G HUB가 필요하다. 둘을 동시에 쓸 수 없다.

## 범위

**1차 (이 스펙)**
- 조명 모드: Static, SoundReactive, ColorCycle, Breathing
- 출력: 볼륨, 우퍼, EQ
- 프로필: 생성/수정/삭제/수동 적용, 마지막 프로필 자동 복원
- 공장 초기값 스냅샷 + 복원
- 메뉴바 빠른 패널 + 일반 설정 창
- 배포: 개인용 (ad-hoc 서명, 공증 없음)

**나중**
- 스케줄 엔진 (시간대별 프로필 자동 전환)
- 앱별 자동 전환
- 화면 샘플러 모드
- 공개 배포 (Developer ID, Sparkle)

## 안전 원칙

1. 펌웨어 쓰기/업데이트 계열 명령은 절대 보내지 않는다. 휘발성 상태(LED 색, 우퍼, 볼륨, EQ)만 다룬다.
2. HID++ 기능 ID를 무작위로 시도하지 않는다. 커뮤니티(Solaar, logiops, g560-led)에서 확인된 ID 또는 G HUB 패킷 캡처로 확인된 것만 사용한다.
3. 앱이 어떤 쓰기 명령도 보내기 전에 장치의 현재 상태를 GET으로 읽어 `factory-defaults.json`으로 저장한다. 이 파일은 한 번 생성되면 앱이 덮어쓰지 않는다.
4. 모든 `set*` 명령에는 짝이 되는 `get*` 명령이 있다.
5. 언제든 `g560ctl restore` 또는 설정 창의 "기본값으로 초기화"로 복구할 수 있다.

## 구조

```
G560Studio/
├─ Package.swift                SwiftPM. 라이브러리 + 앱 + CLI 타깃. Xcode 프로젝트 없음.
├─ Sources/
│   ├─ G560Core/                순수 로직. UI 모름.
│   │   ├─ Device/
│   │   │   ├─ G560Device       IOHIDManager 열기/닫기, 핫플러그 감지
│   │   │   ├─ HIDPP            20바이트 long report 조립·전송·응답 파싱
│   │   │   ├─ G560Commands     setLEDZones/getLEDZones, setWoofer/getWoofer,
│   │   │   │                   setVolume/getVolume, setEQ/getEQ — 검증된 명령만
│   │   │   └─ FactorySnapshot  첫 연결 시 전체 상태 GET → JSON 저장, restore()
│   │   ├─ Lighting/
│   │   │   ├─ LightingEngine   30Hz 타이머, 모드에 프레임 요청, 변경 시에만 전송
│   │   │   └─ Modes            Static / SoundReactive / ColorCycle / Breathing
│   │   ├─ Audio/
│   │   │   └─ AudioTap         Core Audio Process Tap → AudioLevels 스트림
│   │   └─ Profiles/
│   │       ├─ Profile          Codable
│   │       └─ ProfileStore     profiles.json 읽기/쓰기, 활성 프로필 ID
│   ├─ G560Studio/              앱
│   │   ├─ MenuBar/
│   │   │   ├─ MenuBarIcon      매 프레임 NSImage 렌더 (컬러 파형)
│   │   │   └─ QuickPanel       프로필 목록, 우퍼·볼륨 슬라이더, 조명 on/off, 설정 열기
│   │   └─ Settings/
│   │       ├─ LightingTab      모드 + 존별 색 + 사운드 반응 감도
│   │       ├─ OutputTab        볼륨, 우퍼, EQ 밴드 슬라이더 + 프리셋
│   │       └─ ProfilesTab      생성/이름변경/삭제/현재 상태 저장, 기본값 초기화
│   └─ g560ctl/                 CLI (개발·복구용)
├─ Tests/G560CoreTests/
├─ tools/g560probe.py           0단계: GET 전용 스냅샷 + 캡처 패킷 재전송 검증
├─ docs/protocol.md             캡처 결과표
└─ docs/superpowers/specs/
```

데이터 흐름: `AudioTap → LightingEngine(모드) → G560Commands → HIDPP → USB`
프로필 적용: `ProfileStore → LightingEngine 모드 교체 + 우퍼/볼륨/EQ 명령 각 1회`

각 폴더는 옆 폴더의 내부를 모른다. `Device`는 G560만 알고, `Lighting`은 4존 색을 만드는 것만 한다.

## 장치 통신 (HID++)

- G560: VID `0x046D`, PID `0x0A78`. HID++ 벤더 인터페이스(usage page `0xFF43`)만 연다. 오디오 인터페이스는 건드리지 않는다 → macOS 사운드 출력에 영향 없음.
- 패킷: long report 20바이트 `[0x11][0xFF][feature index][fn<<4 | sw id][params…]`. 에러 응답은 `0x8F`.
- 시작 시 `IRoot(0x0000).getFeature(id)`로 기능 ID → 인덱스를 장치에서 읽는다. 인덱스 하드코딩 금지 (펌웨어별로 다름).
- 알려진 기능: LED `0x8070 COLOR_LED_EFFECTS` (g560-led 사용), EQ `0x8310 EQUALIZER` (Solaar 목록). 볼륨/우퍼는 캡처로 확인.
- 쓰기 `IOHIDDeviceSetReport`, 읽기는 input report 콜백. 타임아웃 200ms, 자동 재시도 없음.
- 핫플러그: IOHIDManager 매칭/제거 콜백. 제거 시 조명 엔진 정지, 재연결 시 현재 프로필 재적용.
- 단일 인스턴스 앱.

## 0단계 — 프로토콜 캡처 (앱 코드 이전)

1. `tools/g560probe.py` (hidapi): 장치 열기 → IRoot로 기능 목록 나열 → 각 기능 GET 호출 → `factory-defaults.json` 저장 + 저장소 커밋. **쓰기 0회.**
2. G HUB 설치. Wireshark USB 캡처 (`ifconfig XHC20 up`, 필터 `usb.idVendor == 0x046d`).
3. G HUB에서 하나씩 조작하며 패킷 기록: 볼륨, 우퍼, EQ 밴드 각각, LED 존 색, "기본값 복원". → `docs/protocol.md`.
4. G HUB 삭제 (장치 점유 충돌).
5. 캡처 패킷을 probe로 재전송해 동작 확인 → 확인된 것만 `G560Commands`로.
6. 장치 자체 공장 초기화 명령이 캡처되면 그것을 `restore()`에 사용, 없으면 스냅샷 방식.

## 오디오

- `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`로 시스템 출력 전체 탭. 첫 실행 시 시스템 오디오 녹음 권한 팝업 1회.
- 버퍼마다 계산: RMS, 피크, 저(<200Hz)/중/고역 에너지. `Accelerate.vDSP` 256포인트 FFT.
- 출력 `AudioLevels { rms, peak, low, mid, high }`. 소비자: LightingEngine, MenuBarIcon.
- 무음 3초 → idle 플래그. 조명은 모드 기본색, 아이콘은 정지.

## 조명 엔진

- 타이머 30Hz. 매 틱 `mode.frame(t, audio) -> ZoneColors(4)`. 이전 프레임과 같으면 전송 스킵.
- 모드 프로토콜: `func frame(t: TimeInterval, audio: AudioLevels) -> ZoneColors`
  - Static: 고정 4색
  - ColorCycle / Breathing: t 기반
  - SoundReactive: 기본색 × 밝기(rms). 옵션: low→전면존, high→후면존. 파라미터는 감도, 어택/릴리즈.
- 4존을 한 패킷으로 보낼 수 있는지 캡처에서 확인.

## 메뉴바 아이콘

- 매 프레임(30Hz) `NSImage`를 직접 그린다. 미리 그린 프레임 없음.
- 형태: 오디오 파형(rms·밴드). 색: 좌→우 4존 색 그라데이션 선. 컬러 아이콘(템플릿 아님).
- 무음: 평평한 선을 현재 존 색으로 은은하게. 미연결: 회색.

## 프로필

```swift
struct Profile: Codable, Identifiable {
    var id: UUID
    var name: String
    var lighting: LightingConfig   // enum with associated values (mode + 파라미터)
    var volume: Int
    var woofer: Int
    var eq: [Int]                  // 밴드 수·범위는 캡처 후 확정
}
```
`ProfileStore`: `~/Library/Application Support/G560Studio/profiles.json` 하나. 활성 프로필 ID 포함. 앱 시작 시 마지막 프로필 적용.

## UI

**QuickPanel (메뉴바 클릭)**: 연결 상태 한 줄, 프로필 목록(클릭=적용), 우퍼·볼륨 슬라이더, 조명 on/off, "설정 열기…".
**설정 창 (⌘,)**: 일반 창, Dock에 안 뜸. 탭 3개 — 조명 / 출력 / 프로필.

## 에러 처리

- 장치 없음/무응답 → 엔진 정지, 아이콘 회색, 패널에 "G560 연결 안 됨". 재시도 폭주 없음.
- 오디오 권한 거부 → SoundReactive만 비활성, 나머지 정상. "시스템 설정에서 허용" 링크.
- HID++ 에러(0x8F) → 로그, 해당 명령만 실패.
- `factory-defaults.json` 없음/손상 → 초기화 버튼 비활성 + 이유 표시. 빈 값 절대 안 씀.

## 테스트

XCTest 기본, 프레임워크 추가 없음.
- `HIDPP`: 캡처한 실제 바이트열로 조립/파싱 왕복
- `LightingModes`: 고정 t/levels → 4색 검증
- `ProfileStore`: JSON 왕복
- 하드웨어: `g560ctl` 수동 (`led 0 ff0000`, `woofer 30`, `restore`)

## 빌드

Xcode.app 사용 (`sudo xcode-select -s /Applications/Xcode.app`). SwiftPM, macOS 14.2+ (Process Tap). ad-hoc 서명.
