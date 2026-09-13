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
    if feat == 0xFF:   # 에러: [11][ff][ff][origFeature][origFn|sw][code] (실측)
        return Reply(feat, report[4] >> 4, report[4] & 0xF, report[4:], (report[3], report[4], report[5]))
    return Reply(feat, fnsw >> 4, fnsw & 0xF, report[4:], None)
