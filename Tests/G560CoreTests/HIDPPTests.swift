import XCTest
@testable import G560Core

func hex(_ s: String) -> [UInt8] {
    stride(from: 0, to: s.count, by: 2).map { i in
        UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i + 2)], radix: 16)!
    }
}

final class HIDPPTests: XCTestCase {
    func testBuildLEDZone0Red() {   // 검증된 패킷 (docs/protocol.md)
        XCTAssertEqual(HIDPP.build(featureIndex: 4, fn: 3, params: [0, 1, 0xff, 0, 0, 2]),
                       hex("11ff043a0001ff00000200000000000000000000"))
    }
    func testBuildWoofer50() {
        XCTAssertEqual(HIDPP.build(featureIndex: 9, fn: 1, params: [50]),
                       hex("11ff091a32000000000000000000000000000000"))
    }
    func testParseWooferGet() {
        let r = HIDPP.parse(hex("11ff090a28000000000000000000000000000000"))!
        XCTAssertEqual(r.featureIndex, 9); XCTAssertEqual(r.fn, 0); XCTAssertEqual(r.swID, 0xA)
        XCTAssertEqual(r.params[0], 40); XCTAssertNil(r.error)
    }
    func testParseError() {          // EQ set with 0x00 prefix → INVALID_ARGUMENT (실측)
        let r = HIDPP.parse(hex("11ffff063a020000000000000000000000000000"))!
        XCTAssertEqual(r.error?.code, 2); XCTAssertEqual(r.error?.name, "INVALID_ARGUMENT")
        XCTAssertEqual(r.error?.origFeature, 6)
    }
    func testParseRejectsWrongLength() { XCTAssertNil(HIDPP.parse([0x11, 0xff])) }
}
