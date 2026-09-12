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
    0x8010: "GKEY", 0x8040: "BRIGHTNESS_CONTROL",
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
    dev.write(build(feature_index, fn, params))
    deadline = time.time() + TIMEOUT_MS / 1000
    while time.time() < deadline:
        raw = dev.read(20, timeout=TIMEOUT_MS)
        if not raw or raw[0] != 0x11:
            continue
        r = parse(raw)
        if r.error and r.error[0] == feature_index:
            raise RuntimeError(f"HID++ error {ERROR_NAMES.get(r.error[2], r.error[2])} "
                               f"on feature idx {feature_index} fn {fn}")
        if r.feature_index == feature_index and r.sw_id == SW_ID:
            return r
    raise TimeoutError(f"no reply from feature idx {feature_index} fn {fn}")


def enumerate_features(dev):
    fs_idx = call(dev, 0x00, 0, bytes([0x00, 0x01])).params[0]   # IRoot.getFeature(FEATURE_SET)
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
        if fid not in by_id:
            return None
        r = _safe(dev, by_id[fid], fn, params)
        state.setdefault(f"{fid:#06x}", {})[key or str(fn)] = r
        return None if r.startswith("ERR") else bytes.fromhex(r)

    get(0x0003, 0); get(0x0003, 1, bytes([0]))
    get(0x0005, 0); get(0x0005, 1, bytes([0]))

    info = get(0x8070, 0)
    if info:
        for z in range(info[0]):
            zi = get(0x8070, 1, bytes([z]), key=f"1/zone{z}")
            if zi:
                for e in range(zi[3]):
                    get(0x8070, 2, bytes([z, e]), key=f"2/zone{z}/effect{e}")

    if get(0x8310, 0):
        get(0x8310, 1, bytes([0]), key="1/start0"); get(0x8310, 1, bytes([7]), key="1/start7"); get(0x8310, 2)

    if get(0x8040, 0):
        get(0x8040, 1)

    for fid in (0x8300, 0x8320):
        get(fid, 0)
    for f in feats:
        if f["name"] == "?" and f["id"] not in FORBIDDEN:
            get(f["id"], 0)
    return {"features": feats, "state": state}


def cmd_dump(args):
    if not args:
        sys.exit("usage: g560probe.py dump <out.json>")
    dev = open_device()
    json.dump(dump_state(dev), open(args[0], "w"), indent=2)
    print("wrote", args[0])


if __name__ == "__main__":
    cmds = {"enumerate": cmd_enumerate, "dump": cmd_dump}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit("usage: g560probe.py enumerate | dump <out.json>")
    cmds[sys.argv[1]](sys.argv[2:])
