# Phase 0: G560 프로토콜 캡처 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱 코드를 쓰기 전에, G560의 HID++ 기능 목록과 공장 초기 상태를 읽어 저장하고, G HUB 조작 전후 상태 diff로 볼륨·우퍼·EQ·LED 명령의 실제 바이트를 `docs/protocol.md`에 확정한다.

**Architecture:** Python 스크립트 하나(`tools/g560probe.py`)가 hidapi로 G560의 HID++ 벤더 인터페이스를 열고, `IRoot`/`IFeatureSet`로 기능을 열거한 뒤 **문서화된 GET 함수만** 호출해 상태를 JSON으로 덤프한다. G HUB로 값을 하나 바꾸고 다시 덤프해서 diff → 어떤 feature/function/바이트가 바뀌는지 확정. Wireshark는 이 맥(Apple Silicon, XHC 인터페이스 없음)에서 USB 캡처가 안 되므로 사용하지 않는다.

**Tech Stack:** Python 3.14, `hidapi` (pip `hid`), venv in `tools/.venv`. 테스트는 표준 `assert`만.

## Global Constraints

- 펌웨어 쓰기/업데이트 계열 명령은 절대 보내지 않는다. (스펙 §안전 원칙 1)
- HID++ 기능 ID를 무작위로 시도하지 않는다. 커뮤니티(Solaar, logiops, g560-led)에서 확인된 ID 또는 diff로 확인된 것만 사용. (§2)
- 어떤 쓰기 명령도 보내기 전에 `factory-defaults.json`을 GET으로 만들어 커밋한다. 이 파일은 생성 후 덮어쓰지 않는다. (§3)
- G560: VID `0x046D`, PID `0x0A78`, HID++ 인터페이스 usage page `0xFF43`. 오디오 인터페이스는 열지 않는다.
- 패킷: long report `0x11`, 20바이트 `[0x11][0xFF][feature index][fn<<4 | sw id][params…]`. 에러는 feature index 자리에 `0xFF`. 타임아웃 200ms, 자동 재시도 없음.
- Task 5까지는 **쓰기(`send` 서브커맨드) 금지**. Task 6에서만, diff로 확인된 바이트만 재전송한다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `tools/hidpp.py` | 순수 함수: 패킷 조립/파싱, 에러 디코드. 장치 접근 없음 → 테스트 가능 |
| `tools/test_hidpp.py` | `hidpp.py` 검증 (`python3 tools/test_hidpp.py`) |
| `tools/g560probe.py` | CLI: `enumerate`, `dump <out.json>`, `diff <a.json> <b.json>`, `send <hex20>` (Task 6부터) |
| `tools/requirements.txt` | `hid` 한 줄 |
| `factory-defaults.json` | Task 4 산출물. 커밋. 이후 불변 |
| `docs/protocol.md` | 기능 인덱스 표 + 확정된 명령 바이트 표 |

---

### Task 1: 환경 + 패킷 조립/파싱 (순수 함수)

**Files:**
- Create: `tools/requirements.txt`, `tools/hidpp.py`, `tools/test_hidpp.py`

**Interfaces:**
- Produces:
  - `build(feature_index: int, fn: int, params: bytes = b"", sw_id: int = 0x0A) -> bytes` — 20바이트 long report
  - `parse(report: bytes) -> Reply` where `Reply = namedtuple("Reply", "feature_index fn sw_id params error")`; `error`는 `None` 또는 `(orig_feature, orig_fn, code)`
  - `ERROR_NAMES: dict[int, str]`

- [ ] **Step 1: venv + hidapi 설치**

```bash
cd /Users/yongmacbookpro/Documents/ONESTUDIO/G560Studio
printf 'hid\n' > tools/requirements.txt
python3 -m venv tools/.venv && tools/.venv/bin/pip install -q -r tools/requirements.txt
tools/.venv/bin/python -c "import hid; print(hid.__version__ if hasattr(hid,'__version__') else 'ok')"
```
Expected: `ok` 또는 버전 출력. (실패 시 `brew install hidapi` 후 재시도 — `hid` 패키지는 시스템 libhidapi를 dlopen함.)

`.gitignore`에 `tools/.venv/` 추가:
```bash
printf 'tools/.venv/\n' >> .gitignore
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tools/test_hidpp.py`:
```python
from hidpp import build, parse, ERROR_NAMES

# g560-led가 실제로 보내는 패킷 (feature idx 4, fn 3, sw 0xA, zone 0 red fixed)
KNOWN = bytes.fromhex("11ff043a0001ff0000020000000000000000000000")

def test_build_matches_known_g560led_packet():
    assert build(0x04, 0x3, bytes.fromhex("0001ff000002")) == KNOWN

def test_build_pads_to_20_bytes():
    p = build(0x00, 0x0, b"\x80\x70")
    assert len(p) == 20 and p[:4] == bytes([0x11, 0xFF, 0x00, 0x0A])

def test_parse_normal_reply():
    r = parse(bytes.fromhex("11ff000a0403010000000000000000000000000000"))
    assert r.feature_index == 0 and r.fn == 0 and r.sw_id == 0xA
    assert r.params[:3] == bytes([0x04, 0x03, 0x01]) and r.error is None

def test_parse_error_reply():
    # feature index 0xFF = HID++ 2.0 error; params = [orig feature, orig fn|sw, code]
    r = parse(bytes.fromhex("11ffff0a0405070000000000000000000000000000"))
    assert r.error == (0x04, 0x05, 0x07) and ERROR_NAMES[0x07] == "INVALID_FUNCTION_ID"

if __name__ == "__main__":
    for n, f in list(globals().items()):
        if n.startswith("test_"):
            f(); print("ok", n)
```

- [ ] **Step 3: 실패 확인**

```bash
cd tools && ../tools/.venv/bin/python test_hidpp.py
```
Expected: `ModuleNotFoundError: No module named 'hidpp'`

- [ ] **Step 4: 구현**

`tools/hidpp.py`:
```python
"""HID++ 2.0 long-report helpers. Pure functions, no device access."""
from collections import namedtuple

LONG = 0x11
DEVICE_IDX = 0xFF          # USB 직결 장치
LEN = 20
SW_ID = 0x0A

Reply = namedtuple("Reply", "feature_index fn sw_id params error")

ERROR_NAMES = {
    0: "NO_ERROR", 1: "UNKNOWN", 2: "INVALID_ARGUMENT", 3: "OUT_OF_RANGE",
    4: "HW_ERROR", 5: "LOGITECH_INTERNAL", 6: "INVALID_FEATURE_INDEX",
    7: "INVALID_FUNCTION_ID", 8: "BUSY", 9: "UNSUPPORTED",
}

def build(feature_index, fn, params=b"", sw_id=SW_ID):
    assert 0 <= fn <= 0xF and 1 <= sw_id <= 0xF and len(params) <= LEN - 4
    p = bytes([LONG, DEVICE_IDX, feature_index, (fn << 4) | sw_id]) + bytes(params)
    return p.ljust(LEN, b"\x00")

def parse(report):
    report = bytes(report)
    assert report[0] == LONG and len(report) == LEN, report.hex()
    feat, fnsw = report[2], report[3]
    params = report[4:]
    if feat == 0xFF:
        return Reply(feat, fnsw >> 4, fnsw & 0xF, params, (params[0], params[1], params[2]))
    return Reply(feat, fnsw >> 4, fnsw & 0xF, params, None)
```

- [ ] **Step 5: 통과 확인**

```bash
cd tools && ../tools/.venv/bin/python test_hidpp.py
```
Expected: `ok test_...` 4줄.

- [ ] **Step 6: Commit**

```bash
git add .gitignore tools/requirements.txt tools/hidpp.py tools/test_hidpp.py
git commit -m "Add HID++ packet helpers with tests"
```

---

### Task 2: 장치 열기 + 기능 열거 (`enumerate`)

**Files:**
- Create: `tools/g560probe.py`

**Interfaces:**
- Consumes: `hidpp.build/parse`
- Produces:
  - `open_device() -> hid.Device` — usage page 0xFF43 인터페이스만
  - `call(dev, feature_index, fn, params=b"") -> Reply` — 전송 + 200ms 내 sw_id/feature 일치 응답 대기, 에러면 `RuntimeError`
  - `enumerate_features(dev) -> list[dict(index, id, type, version, name)]`
  - CLI: `g560probe.py enumerate`

- [ ] **Step 1: 구현**

`tools/g560probe.py`:
```python
#!/usr/bin/env python3
"""G560 HID++ probe. Phase 0 tool. Read-only until Task 6."""
import json, sys, time
import hid
from hidpp import build, parse, ERROR_NAMES, SW_ID

VID, PID, USAGE_PAGE = 0x046D, 0x0A78, 0xFF43
TIMEOUT_MS = 200

# Solaar hidpp20_constants 에서 확인된 ID → 이름 (알려진 것만; 나머지는 "?" 로 표시)
FEATURE_NAMES = {
    0x0000: "ROOT", 0x0001: "FEATURE_SET", 0x0003: "DEVICE_FW_VERSION",
    0x0005: "DEVICE_NAME", 0x0007: "DEVICE_FRIENDLY_NAME", 0x0020: "RESET",
    0x00C2: "DFU_CONTROL_SIGNED", 0x00C3: "DFU_CONTROL_BLE", 0x00D0: "DFU",
    0x1801: "MANUFACTURING_MODE", 0x1802: "DEVICE_RESET", 0x1E00: "HIDDEN_FEATURES",
    0x1F1F: "OOB_STATE", 0x8070: "COLOR_LED_EFFECTS", 0x8071: "RGB_EFFECTS",
    0x8300: "SIDETONE", 0x8310: "EQUALIZER", 0x8320: "HEADSET_OUT",
}
# 절대 호출하지 않는 기능 (펌웨어/리셋/제조 모드)
FORBIDDEN = {0x0020, 0x00C2, 0x00C3, 0x00D0, 0x1801, 0x1802, 0x1E00}

def open_device():
    for d in hid.enumerate(VID, PID):
        if d["usage_page"] == USAGE_PAGE:
            dev = hid.Device(path=d["path"])
            dev.nonblocking = False
            return dev
    sys.exit("G560 HID++ interface (usage page 0xFF43) not found. Is it plugged in?")

def call(dev, feature_index, fn, params=b""):
    req = build(feature_index, fn, params)
    dev.write(req)
    deadline = time.time() + TIMEOUT_MS / 1000
    while time.time() < deadline:
        raw = dev.read(20, timeout=TIMEOUT_MS)
        if not raw or raw[0] != 0x11:
            continue
        r = parse(raw)
        if r.error and r.error[0] == feature_index:
            raise RuntimeError(f"HID++ error {ERROR_NAMES.get(r.error[2], r.error[2])} "
                               f"on feature {feature_index:#04x} fn {fn}")
        if r.feature_index == feature_index and r.sw_id == SW_ID:
            return r
    raise TimeoutError(f"no reply from feature {feature_index:#04x} fn {fn}")

def enumerate_features(dev):
    # IRoot.getFeature(0x0001) → FEATURE_SET index
    fs_idx = call(dev, 0x00, 0, bytes([0x00, 0x01])).params[0]
    count = call(dev, fs_idx, 0).params[0]
    out = [{"index": 0, "id": 0x0000, "type": 0, "version": 0, "name": "ROOT"}]
    for i in range(1, count + 1):
        p = call(dev, fs_idx, 1, bytes([i])).params
        fid = (p[0] << 8) | p[1]
        out.append({"index": i, "id": fid, "type": p[2], "version": p[3],
                    "name": FEATURE_NAMES.get(fid, "?")})
    return out

def cmd_enumerate(_):
    dev = open_device()
    for f in enumerate_features(dev):
        flag = " FORBIDDEN" if f["id"] in FORBIDDEN else ""
        print(f'{f["index"]:2d}  {f["id"]:#06x}  v{f["version"]}  {f["name"]}{flag}')

if __name__ == "__main__":
    cmds = {"enumerate": cmd_enumerate}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit("usage: g560probe.py enumerate")
    cmds[sys.argv[1]](sys.argv[2:])
```

- [ ] **Step 2: 실행 (읽기만)**

```bash
tools/.venv/bin/python tools/g560probe.py enumerate
```
Expected: 기능 목록 10~25줄. `0x8070 COLOR_LED_EFFECTS`가 있어야 함(g560-led 근거). `0x8310 EQUALIZER` 유무 확인. `?` 로 표시된 ID는 `docs/protocol.md`에 기록.

만약 `hid.Device` 열기 실패("device not found"/permission): macOS 입력 모니터링 권한 문제가 아니라 hidapi가 인터페이스를 못 찾은 것. `hid.enumerate(VID, PID)` 전체를 출력해서 usage_page 값 확인 후 상수 수정.

- [ ] **Step 3: Commit**

```bash
git add tools/g560probe.py
git commit -m "Add g560probe enumerate (read-only feature listing)"
```

---

### Task 3: 상태 덤프 (`dump`) — 문서화된 GET만

**Files:**
- Modify: `tools/g560probe.py`

**Interfaces:**
- Produces:
  - `dump_state(dev) -> dict` — `{"features": [...], "state": {"<feature_id hex>": {"<fn>": "<hex params>"}}}`
  - CLI: `g560probe.py dump <out.json>`

호출하는 GET (HID++ 2.0 공개 문서 + Solaar 구현 기준, 모두 인자 없는 읽기):

| Feature | fn | 이름 | 비고 |
|---|---|---|---|
| 0x0003 | 0 | getDeviceInfo | 엔티티 수 |
| 0x0003 | 1 | getFwInfo(entity 0) | 펌웨어 버전 문자열 — 스냅샷 식별용 |
| 0x0005 | 0 | getDeviceNameCount | |
| 0x0005 | 1 | getDeviceName(0) | |
| 0x8070 | 0 | getInfo | zone 수, 지원 효과 |
| 0x8070 | 1 | getZoneInfo(z) | z = 0..zones-1 |
| 0x8070 | 2 | getZoneEffectInfo(z, e) | 각 존 각 효과의 파라미터 |
| 0x8070 | 0xE? | — | **호출 안 함** (문서에 없는 fn) |
| 0x8310 | 0 | getEqInfo | 밴드 수, 범위, dB 스텝 |
| 0x8310 | 1 | getFrequencies(start) | 밴드 중심 주파수 |
| 0x8310 | 2 | getEqualizer | 현재 밴드 게인 (**우퍼/EQ 확인용 핵심**) |
| 0x8300 | 0 | getSidetoneLevel | 있을 경우만 |
| 0x8320 | 0 | getSpeakerLevel? | 존재하면 fn 0만 |

미상(`?`) 기능은 **fn 0만** 호출한다 — HID++ 2.0 관례상 fn 0은 `getInfo`/`getCapabilities` 류의 읽기이며, 인자 없이 호출 시 최악의 경우 `INVALID_ARGUMENT` 에러로 끝난다. FORBIDDEN 집합은 fn 0조차 호출하지 않는다.

- [ ] **Step 1: 구현 추가**

`tools/g560probe.py`의 `cmd_enumerate` 아래에 추가:
```python
def _safe(dev, idx, fn, params=b""):
    try:
        return call(dev, idx, fn, params).params.hex()
    except (RuntimeError, TimeoutError) as e:
        return f"ERR {e}"

def dump_state(dev):
    feats = enumerate_features(dev)
    by_id = {f["id"]: f["index"] for f in feats}
    state = {}
    def get(fid, fn, params=b"", key=None):
        if fid not in by_id: return None
        r = _safe(dev, by_id[fid], fn, params)
        state.setdefault(f"{fid:#06x}", {})[key or str(fn)] = r
        return None if r.startswith("ERR") else bytes.fromhex(r)

    get(0x0003, 0); get(0x0003, 1, bytes([0]))
    get(0x0005, 0); get(0x0005, 1, bytes([0]))

    info = get(0x8070, 0)
    if info:
        zones = info[0]
        for z in range(zones):
            zi = get(0x8070, 1, bytes([z]), key=f"1/zone{z}")
            if zi:
                effects = zi[2]
                for e in range(effects):
                    get(0x8070, 2, bytes([z, e]), key=f"2/zone{z}/effect{e}")

    eq = get(0x8310, 0)
    if eq:
        get(0x8310, 1, bytes([0])); get(0x8310, 2)

    for fid in (0x8300, 0x8320):
        get(fid, 0)
    for f in feats:
        if f["name"] == "?" and f["id"] not in FORBIDDEN:
            get(f["id"], 0)
    return {"features": feats, "state": state}

def cmd_dump(args):
    if not args: sys.exit("usage: g560probe.py dump <out.json>")
    dev = open_device()
    json.dump(dump_state(dev), open(args[0], "w"), indent=2)
    print("wrote", args[0])
```
`cmds` 딕셔너리에 `"dump": cmd_dump` 추가, usage 문자열 갱신.

- [ ] **Step 2: 실행**

```bash
tools/.venv/bin/python tools/g560probe.py dump /tmp/g560-dump1.json && cat /tmp/g560-dump1.json
```
Expected: JSON. `0x8070` 아래 zone 4개(존 수가 4가 아니면 그대로 기록). `0x8310`이 있으면 `2` 키에 밴드 게인 바이트열.
ERR가 있는 항목은 정상 — 해당 fn이 없다는 뜻. **장치가 응답 안 하거나 소리가 끊기면 즉시 중단하고 USB 재연결.** (읽기만 하므로 상태는 바뀌지 않음.)

- [ ] **Step 3: 두 번 덤프해서 동일한지 확인 (재현성)**

```bash
tools/.venv/bin/python tools/g560probe.py dump /tmp/g560-dump2.json && diff /tmp/g560-dump1.json /tmp/g560-dump2.json && echo SAME
```
Expected: `SAME`. 다르면 어느 키가 흔들리는지 기록(타이머성 값일 수 있음) — 그 키는 diff 비교에서 제외 목록에 넣는다.

- [ ] **Step 4: Commit**

```bash
git add tools/g560probe.py
git commit -m "Add g560probe dump (documented GET calls only)"
```

---

### Task 4: 공장 초기값 스냅샷 확정 + `diff` 서브커맨드

**Files:**
- Create: `factory-defaults.json`
- Modify: `tools/g560probe.py`

**Interfaces:**
- Produces: CLI `g560probe.py diff <a.json> <b.json>` — `state`에서 달라진 키만 `feature/fn: old → new` 로 출력

- [ ] **Step 1: 스냅샷 저장 (G HUB 설치 전, 장치 전원 껐다 켠 직후)**

G560 전원을 끄고 5초 후 켠 다음:
```bash
tools/.venv/bin/python tools/g560probe.py dump factory-defaults.json
```

- [ ] **Step 2: diff 구현**

`tools/g560probe.py`에 추가:
```python
def cmd_diff(args):
    if len(args) != 2: sys.exit("usage: g560probe.py diff <a.json> <b.json>")
    a, b = (json.load(open(p))["state"] for p in args)
    changed = 0
    for fid in sorted(set(a) | set(b)):
        for fn in sorted(set(a.get(fid, {})) | set(b.get(fid, {}))):
            x, y = a.get(fid, {}).get(fn), b.get(fid, {}).get(fn)
            if x != y:
                changed += 1
                print(f"{fid} fn {fn}:\n  {x}\n  {y}")
    print("no differences" if not changed else f"{changed} changed")
```
`cmds`에 `"diff": cmd_diff` 추가.

- [ ] **Step 3: diff 자기검증**

```bash
tools/.venv/bin/python tools/g560probe.py diff factory-defaults.json factory-defaults.json
```
Expected: `no differences`

- [ ] **Step 4: Commit — 이 파일은 이후 절대 수정하지 않음**

```bash
git add factory-defaults.json tools/g560probe.py
git commit -m "Snapshot G560 factory defaults (read-only); add diff"
git push origin main
```

---

### Task 5: G HUB 설치 + 조작별 diff → `docs/protocol.md`

**Files:**
- Create: `docs/protocol.md`

이 태스크는 사람이 G HUB를 조작하고 에이전트가 덤프/diff를 돌리는 **수동 반복**이다. 각 조작마다: 조작 전 덤프 → G HUB에서 값 하나만 변경 → 조작 후 덤프 → diff → 표에 기록.

- [ ] **Step 1: G HUB 설치**

https://www.logitechg.com/ko-kr/innovation/g-hub.html 에서 다운로드·설치. (사용자가 직접.) 설치 후 G560이 G HUB에 잡히는지 확인. **G HUB 안에서 펌웨어 업데이트를 제안하면 거절**한다 — 스냅샷과 펌웨어가 어긋나면 안 됨.

- [ ] **Step 2: G HUB 공존 확인**

```bash
tools/.venv/bin/python tools/g560probe.py dump /tmp/ghub-base.json && tools/.venv/bin/python tools/g560probe.py diff factory-defaults.json /tmp/ghub-base.json
```
Expected: 동작함(G HUB가 인터페이스를 독점하지 않음). 차이가 있으면 "G HUB 설치만으로 바뀐 것"으로 표에 기록.
만약 `dump`가 TimeoutError를 내면 G HUB가 독점 중 → G HUB 메뉴에서 종료(Quit) 후 재시도. 종료해도 안 되면 Task 5를 "G HUB 종료 → 덤프 → G HUB 실행 → 조작 → G HUB 종료 → 덤프" 순서로 진행.

- [ ] **Step 3: 조작 하나당 덤프 반복**

각 항목에 대해:
```bash
D=/tmp/cap; mkdir -p $D
# 조작 전
tools/.venv/bin/python tools/g560probe.py dump $D/<name>-before.json
# (G HUB에서 값 하나 변경)
tools/.venv/bin/python tools/g560probe.py dump $D/<name>-after.json
tools/.venv/bin/python tools/g560probe.py diff $D/<name>-before.json $D/<name>-after.json
```
`<name>` 목록 (순서대로):
1. `volume-50` — 볼륨 50%
2. `volume-100` — 볼륨 100% (선형인지 확인)
3. `woofer-min`, `woofer-mid`, `woofer-max` — 우퍼/서브 레벨 최소·중간·최대
4. `eq-band1-plus6` … 밴드 하나만 +6 dB (밴드 수만큼)
5. `eq-preset-flat` — EQ 프리셋 Flat
6. `led-zone0-red` — 존 하나만 고정 빨강 (`ff0000`)
7. `led-all-blue` — 전 존 파랑 (한 패킷인지 존별 4패킷인지 판단 근거)
8. `led-off`
9. `restore-defaults` — G HUB의 "기본값으로 복원" (있을 경우)

각 diff 결과에서 (feature id, fn, 바뀐 바이트 오프셋, 값)을 아래 표에 기록.

**볼륨 diff가 비어 있으면**: G HUB 볼륨은 CoreAudio(USB Audio Class)로 가는 것. 그 경우 protocol.md에 "볼륨 = CoreAudio, HID++ 아님"으로 기록하고 앱은 `AudioObjectSetPropertyData(kAudioDevicePropertyVolumeScalar)`를 쓴다.
**우퍼 diff가 비어 있으면**: `0x8310 getEqualizer` 외 다른 `?` 기능의 fn 0에서 바뀌었는지 본다. 그래도 없으면 우퍼 상태를 읽는 GET이 없는 것 → Task 6에서 `send`로 확인할 후보가 없으므로 사용자에게 보고하고 멈춘다. (무작위 시도 금지.)

- [ ] **Step 4: protocol.md 작성**

`docs/protocol.md` 틀:
```markdown
# G560 HID++ 프로토콜 (실측)

펌웨어: <0x0003 fn1 결과>   측정일: 2026-09-XX   방법: G HUB 조작 전후 GET diff

## 기능 인덱스 (이 펌웨어)
| index | id | name | version |
|---|---|---|---|
| (enumerate 출력 붙여넣기) |

## 상태 읽기 (GET)
| 항목 | feature | fn | 응답 바이트 해석 |
|---|---|---|---|
| EQ 게인 | 0x8310 | 2 | byte[i] = 밴드 i 게인 (signed, dB×?) |
| ... |

## 조작 → 변화 (diff 결과)
| 조작 | feature | fn | 변한 오프셋 | before → after | 해석 |
|---|---|---|---|---|---|
| volume-50 | ... |
| woofer-mid | ... |

## 확정된 쓰기 명령 (Task 6에서 재전송으로 검증된 것만)
| 명령 | 20바이트 hex | 검증 |
|---|---|---|
| setZone(0, ff0000, fixed) | 11ff??3a0001ff000002... | ✅ 2026-09-XX |

## 미확인 / 사용 안 함
- ...
```
`??` 자리는 enumerate에서 얻은 실제 인덱스로 채운다.

- [ ] **Step 5: G HUB 제거**

G HUB 메뉴 → Quit, 그다음 `/Applications/lghub.app`을 휴지통으로. `~/Library/Application Support/LGHUB`, `~/Library/LaunchAgents/com.logi.*` 확인 후 제거 (사용자가 직접). 재부팅 없이 `pgrep -il lghub`가 비어 있으면 됨.

- [ ] **Step 6: Commit**

```bash
git add docs/protocol.md
git commit -m "Document G560 HID++ protocol from G HUB diff captures"
```

---

### Task 6: 확정 명령 재전송 검증 (`send`) + 복구 확인

**Files:**
- Modify: `tools/g560probe.py`

**Interfaces:**
- Produces: CLI `g560probe.py send <40 hex chars>` — 20바이트 그대로 전송하고 응답 출력. `--yes` 없으면 전송 전 바이트를 보여주고 `y` 입력 요구.

이 태스크에서 처음으로 장치에 **쓰기**를 한다. 보내는 바이트는 `docs/protocol.md`의 "조작 → 변화" 표에서 얻은 (feature, fn, 값) 조합으로만 만든다.

- [ ] **Step 1: send 구현**

```python
def cmd_send(args):
    if not args or len(args[0]) != 40: sys.exit("usage: g560probe.py send <40 hex> [--yes]")
    raw = bytes.fromhex(args[0])
    feat = raw[2]
    dev = open_device()
    ids = {f["index"]: f["id"] for f in enumerate_features(dev)}
    if ids.get(feat) in FORBIDDEN or ids.get(feat) is None:
        sys.exit(f"refusing: feature index {feat} is forbidden/unknown")
    if "--yes" not in args:
        print("about to send:", raw.hex()); 
        if input("y to continue: ").strip() != "y": sys.exit("aborted")
    dev.write(raw)
    raw_r = dev.read(20, timeout=TIMEOUT_MS)
    print("reply:", bytes(raw_r).hex() if raw_r else "(none)")
```
`cmds`에 `"send": cmd_send` 추가.

- [ ] **Step 2: 첫 쓰기 — 커뮤니티 검증 명령(LED 존 0 빨강)부터**

`enumerate`에서 0x8070의 index를 `XX`로 확인한 뒤:
```bash
tools/.venv/bin/python tools/g560probe.py send 11ffXX3a0001ff000002000000000000000000000000
```
Expected: 왼쪽 스피커 한 존이 빨간색. 응답 첫 4바이트 `11 ff XX 3a`. 에러(`11 ff ff ...`)면 protocol.md에 기록하고 중단.

- [ ] **Step 3: 복구 확인 — 스냅샷 값으로 되돌리기**

`factory-defaults.json`의 `0x8070` `2/zone0/effect*` 응답에서 원래 색을 읽어 같은 형식으로 send. 눈으로 원래 색 복귀 확인. 그다음:
```bash
tools/.venv/bin/python tools/g560probe.py dump /tmp/after-restore.json && tools/.venv/bin/python tools/g560probe.py diff factory-defaults.json /tmp/after-restore.json
```
Expected: `no differences` (또는 Task 3 Step 3에서 확인한 흔들리는 키만).

- [ ] **Step 4: 우퍼·EQ·볼륨 명령 검증**

Task 5 표의 각 항목에 대해 `send` → 귀로/눈으로 확인 → 스냅샷 값으로 `send` 복귀 → `dump`+`diff`로 복귀 확인. 검증된 것만 protocol.md "확정된 쓰기 명령" 표에 ✅와 날짜로 추가.

- [ ] **Step 5: `restore` 서브커맨드**

```python
def cmd_restore(args):
    """factory-defaults.json 의 확정 항목을 장치에 다시 쓴다. 명령 목록은 protocol.md 확정 표와 동일."""
    snap = json.load(open("factory-defaults.json"))["state"]
    dev = open_device()
    ids = {f["id"]: f["index"] for f in enumerate_features(dev)}
    # LED: 존별 fixed 색 복원 (0x8070 fn 3, 형식은 protocol.md 확정 표 기준)
    for z in range(4):
        rgb = RESTORE_LED[z]                 # protocol.md 에서 확정한 값으로 채움
        dev.write(build(ids[0x8070], 3, bytes([z, 0x01]) + rgb + bytes([0x02])))
        time.sleep(0.02)
    # EQ / 우퍼: protocol.md 확정 표의 set 명령을 같은 방식으로 추가
    print("restored")
```
`RESTORE_LED`는 Step 3에서 읽어낸 실제 값을 상수로 넣는다. 우퍼/EQ set이 확정되면 같은 함수에 한 줄씩 추가. `cmds`에 `"restore": cmd_restore` 추가.

```bash
tools/.venv/bin/python tools/g560probe.py send <아무 확정 LED 명령>   # 상태 바꾸고
tools/.venv/bin/python tools/g560probe.py restore
tools/.venv/bin/python tools/g560probe.py dump /tmp/r.json && tools/.venv/bin/python tools/g560probe.py diff factory-defaults.json /tmp/r.json
```
Expected: `no differences`.

- [ ] **Step 6: Commit + push**

```bash
git add tools/g560probe.py docs/protocol.md
git commit -m "Verify G560 write commands by replay; add restore"
git push origin main
```

---

## Phase 0 완료 조건

- `factory-defaults.json` 커밋됨, 이후 변경 없음
- `docs/protocol.md`에 LED / 우퍼 / EQ / 볼륨 각각 "확정" 또는 "HID++ 아님(CoreAudio)" 또는 "미확인(이유)"로 결론이 적혀 있음
- `g560probe.py restore` 실행 후 `diff`가 `no differences`
- G HUB 제거됨 (`pgrep -il lghub` 비어 있음)

이 조건이 충족되면 Plan 2 (Swift 앱)를 protocol.md 기준으로 작성한다.
