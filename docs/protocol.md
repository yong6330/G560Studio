# G560 HID++ 프로토콜 (실측)

- 장치: Logitech G560, VID `0x046D` PID `0x0A78`, HID++ 인터페이스 usage page `0xFF43` (interface 2)
- 펌웨어: `0x0003 fn1` → `00 55 31 20 22 03 00 23 01 0a 78` (U1 v22.03, build 0x0023)
- HID++ 프로토콜 버전: 4.2 (`ROOT fn1` → `04 02`)
- 측정일: 2026-09-13
- 방법: (1) 문서화된 GET 호출로 상태 덤프 → G HUB 조작 전후 diff, (2) HID 인터페이스 공유 오픈으로 G HUB에 대한 장치 응답 리스닝
- 이 문서의 "확정" 표시는 Task 6 재전송 검증 후에만 붙인다.

## 패킷 형식

Long report 20바이트: `[0x11][0xFF][feature index][fn<<4 | sw_id][params… 16바이트]`
- 응답은 같은 헤더(feature index, fn, sw_id 그대로)
- 에러: feature index 자리에 `0xFF`, params = `[orig feature, orig fn|sw, error code]`
- G HUB의 sw_id = `0xC`, 장치 이벤트(notification)의 sw_id = `0x0`
- set 응답: LED/우퍼는 params 전부 0, EQ는 요청 echo

## 기능 인덱스 (이 펌웨어)

| index | id | name | 비고 |
|---|---|---|---|
| 0 | 0x0000 | ROOT | |
| 1 | 0x0001 | FEATURE_SET | |
| 2 | 0x0003 | DEVICE_FW_VERSION | |
| 3 | 0x0005 | DEVICE_NAME | "G560 Gaming Spea…" |
| 4 | 0x8070 | COLOR_LED_EFFECTS | g560-led와 동일 인덱스 |
| 5 | 0x8010 | GKEY | 사용 안 함 |
| 6 | 0x8310 | EQUALIZER | |
| 7 | 0x8320 | HEADSET_OUT (Solaar 명명) | fn0 → 0. 사용 안 함 |
| 8 | 0x8040 | BRIGHTNESS_CONTROL | |
| 9 | 0x8305 | (미공개) **서브우퍼 레벨** | |

펌웨어/리셋/DFU 계열 기능(0x0020, 0x00C2, 0x00C3, 0x00D0, 0x1801, 0x1802, 0x1E00)은 이 장치에 **노출되지 않음**.

## 서브우퍼 — `0x8305` (idx 9)

| fn | 방향 | params | 근거 |
|---|---|---|---|
| 0 | GET | 응답 `[level]` 1바이트, 0–100 선형 (0x00 / 0x28=40 / 0x32=50 / 0x3c=60 / 0x64=100) | diff 5회 |
| 1 | SET | 요청 `[level]` 1바이트. 응답 params 0 | 리스너 + 재전송 검증 ✅ |

공장 초기값: **40** (`0x28`).

## 볼륨

HID++ 변화 없음. G HUB "시스템 볼륨"은 macOS CoreAudio(USB Audio Class) 볼륨이다.
앱에서는 `AudioObjectSetPropertyData(kAudioDevicePropertyVolumeScalar)`로 처리. HID++ 명령 없음.

## LED — `0x8070 COLOR_LED_EFFECTS` (idx 4)

| fn | 방향 | params | 근거 |
|---|---|---|---|
| 0 | getInfo | `[zones=4][nvCaps 00 03][extCaps 05]` | GET |
| 1 | getZoneInfo(z) | `[z][location 00 0z+1][effects=5]` | GET |
| 2 | getZoneEffectInfo(z,e) | `[z][e][effectId 2B][caps 2B][period 2B]` | GET |
| 3 | setZoneEffect | `[z][01=fixed][r][g][b][02]` (g560-led 포맷). **휘발성** — 전원 재시작 시 장치 기본 조명으로 복귀 | 재전송 검증 ✅ |
| 4 | ? | 응답 `00 01 01` — G HUB 초기화 시 호출 | 리스너 |
| 7, 8 | ? | G HUB 초기화 시 호출, 응답 0 | 리스너 |
| 12 (0xC) | ? | 응답 `[z] ff 00 [counter]` — 존별 상태 조회로 보임 | 리스너 |
| 13 (0xD) | ? | G HUB "동기화" 시 존별 호출, 직후 이벤트 `[z] 09 c4` 수신 | 리스너 |

존 0..3 모두 효과 5종 (getZoneEffectInfo):

| effectIdx | effectId | caps | period | 의미 (HID++ 0x8070 규약) |
|---|---|---|---|---|
| 0 | 0x0000 | — | — | Disabled (off) |
| 1 | 0x0001 | 0x0000 | — | Fixed |
| 2 | 0x0003 | 0xC005 | 1000 ms | Color cycle |
| 3 | 0x0007 | 0x0067 | 1000 ms | Breathing |
| 4 | 0x000A | 0xC105 | 60 ms | (미상, 60ms 주기 — 오디오 시각화 후보. 사용 안 함) |

**현재 LED 색을 읽는 GET은 없다** (v0). 공장 스냅샷에도 LED 색은 없음.
앱 설계 결정: 사이클/브리딩/사운드 반응은 **모두 소프트웨어에서 계산해 Fixed(effectIdx 1) 색을 30Hz로 보낸다.** 장치 쓰기 명령은 fn3 하나만 쓴다. Off = Fixed `000000`.

fn 4/7/8/12/13은 의미 미확인 → **사용 안 함**.

## 밝기 — `0x8040 BRIGHTNESS_CONTROL` (idx 8)

| fn | 방향 | params | 근거 |
|---|---|---|---|
| 0 | getInfo | `[max 00 64][caps 04]` → 최대 100 | GET |
| 1 | getBrightness | `[00 64]` → 100 | GET |
| 2 | setBrightness | `[00 xx]` 0–100. 응답 params 0. 값은 저장·읽히지만 **LED는 0/100처럼 동작**(실측) → 앱은 밝기를 소프트웨어로 스케일 | 재전송 검증 ✅ 2026-09-13 |

공장 초기값: 100.

## EQ — `0x8310 EQUALIZER` (idx 6)

| fn | 방향 | params | 근거 |
|---|---|---|---|
| 0 | getInfo | `[bands=0x0A][dbRange=0x1A][caps=00][dbMin=0xEC(-20)][dbMax=0x06]` | GET |
| 1 | getFrequencies(start) | start 0: 32, 64, 125, 250, 500, 1000, 2000 Hz / start 7: 4000, 8000, 16000 Hz | GET |
| 2 | getEqualizer | `[g0..g9]` signed dB, 현재 전부 0 (flat) | GET |
| 3 | setEqualizer | **`[0x02][g0..g9]`** signed dB. 응답은 요청 echo. 첫 바이트 `0x00`은 INVALID_ARGUMENT로 거부됨. `0x02` = EEPROM 저장(**비휘발성**, LGS/G HUB가 쓰는 값). 근거: ashkitten/g933-utils pcap, TimP4w/HaloDaemon 실기 검증, AprilNEA/OpenLogi | 재전송 검증 ✅ |

10밴드: 32 / 64 / 125 / 250 / 500 / 1k / 2k / 4k / 8k / 16k Hz.
공장 초기값: 전부 0.
검증: `[02 03 00…]` → fn2 = `03 00…` → `[02 00…]` → fn2 = 전부 0 (2026-09-13).
EEPROM 마모 방지: 앱은 슬라이더 드래그 중이 아니라 **놓을 때만** 쓴다. dbMin=-20, dbMax=+6 범위 밖은 장치가 거부.

## 확정된 쓰기 명령 (Task 6 재전송 검증)

| 명령 | 20바이트 hex | 검증 |
|---|---|---|
| setZoneEffect(zone0, fixed, ff0000) | `11ff043a0001ff00000200000000000000000000` | ✅ 2026-09-13 |
| setWoofer(50) | `11ff091a32000000000000000000000000000000` | ✅ 2026-09-13 |
| setEqualizer(band0 +3) | `11ff063a02030000000000000000000000000000` | ✅ 2026-09-13 |
| setEqualizer(flat) | `11ff063a02000000000000000000000000000000` | ✅ 2026-09-13 |
| setBrightness(50) | `11ff082a00320000000000000000000000000000` | ✅ 2026-09-13 |

존 매핑 (실측): **0 = 왼쪽 앞(사이드), 1 = 오른쪽 앞(사이드), 2 = 왼쪽 뒤, 3 = 오른쪽 뒤**.

## 복원 (`g560probe.py restore`)

- 우퍼: fn1 ← 스냅샷 값(40)
- EQ: fn3 ← `02` + 스냅샷 값(전부 0)
- LED: 휘발성이라 복원 불필요 — 전원 재시작이 곧 공장 조명. 앱은 시작 시 항상 자기 프로필을 다시 쓴다.
- 실행 후 dump/diff로 스냅샷과 일치 확인 (검증됨 2026-09-13).

## 운영 메모

- hidapi macOS 백엔드는 기본 **독점 오픈**. 그 상태로 장치를 잡고 있으면 G HUB가 "비활성"으로 표시한다. `hid_darwin_set_open_exclusive(0)` 필수. (앱은 IOHIDManager `kIOHIDOptionsTypeNone`으로 열면 동일.)
- G HUB(macOS) 서브우퍼 숫자 입력창은 장치에 반영되지 않는 버그가 있다. 슬라이더 드래그만 반영됨.
- macOS G HUB에는 EQ, 오디오 시각화, 존별 색 지정 UI가 없다.

## 오디오 포맷 (CoreAudio) — 사용하지 않음

`kAudioStreamPropertyPhysicalFormat`으로 샘플레이트를 바꾸면 G560의 볼륨 컨트롤(`kAudioDevicePropertyVolumeScalar`)이 사라지고 이후 포맷 변경도 반영되지 않는다. USB 재연결 전까지 복구 안 됨 (실측 2026-09-13). 앱에서 포맷 변경 기능을 제거했다.
