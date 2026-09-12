from hidpp import build, parse, ERROR_NAMES

# g560-led가 실제로 보내는 패킷 (feature idx 4, fn 3, sw 0xA, zone 0 red fixed)
KNOWN = bytes.fromhex("11ff043a0001ff00000200000000000000000000")

def test_build_matches_known_g560led_packet():
    assert build(0x04, 0x3, bytes.fromhex("0001ff000002")) == KNOWN

def test_build_pads_to_20_bytes():
    p = build(0x00, 0x0, b"\x80\x70")
    assert len(p) == 20 and p[:4] == bytes([0x11, 0xFF, 0x00, 0x0A])

def test_parse_normal_reply():
    r = parse(bytes.fromhex("11ff000a04030100000000000000000000000000"))
    assert r.feature_index == 0 and r.fn == 0 and r.sw_id == 0xA
    assert r.params[:3] == bytes([0x04, 0x03, 0x01]) and r.error is None

def test_parse_error_reply():
    r = parse(bytes.fromhex("11ffff0a04050700000000000000000000000000"))
    assert r.error == (0x04, 0x05, 0x07) and ERROR_NAMES[0x07] == "INVALID_FUNCTION_ID"

if __name__ == "__main__":
    for n, f in list(globals().items()):
        if n.startswith("test_"):
            f(); print("ok", n)
