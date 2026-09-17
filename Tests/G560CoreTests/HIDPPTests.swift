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

final class BreakerTests: XCTestCase {
    func testTripsAfterConsecutiveFailuresAndNeedsProbeAfterCooldown() {
        var b = Breaker()
        let t0 = Date()
        XCTAssertFalse(b.record(false, at: t0))                  // 1회 실패: 아직 닫힘
        XCTAssertFalse(b.needsProbe)
        XCTAssertTrue(b.record(false, at: t0))                   // 2회 연속: 열림 (최초 1회만 true)
        XCTAssertTrue(b.isOpen(at: t0.addingTimeInterval(1)))
        XCTAssertFalse(b.isOpen(at: t0.addingTimeInterval(Breaker.cooldown + 0.1)))
        XCTAssertTrue(b.needsProbe)                              // 쿨다운 끝나도 probe 성공 전까진 복구 아님
        XCTAssertFalse(b.record(false, at: t0.addingTimeInterval(6)))   // probe 실패 → 다시 쿨다운
        XCTAssertTrue(b.isOpen(at: t0.addingTimeInterval(7)))
        b.record(true, at: t0.addingTimeInterval(12))
        XCTAssertFalse(b.needsProbe)
    }
    func testSuccessResetsFailureCount() {
        var b = Breaker()
        b.record(false, at: Date()); b.record(true, at: Date()); b.record(false, at: Date())
        XCTAssertFalse(b.needsProbe)
    }
}

/// 2026-09 점검: 타임아웃 뒤 늦게 온 응답이 다음 요청의 답으로 잘못 매칭되면 안 된다.
/// 특히 IRoot.getFeature 응답엔 기능 id가 없어서, 매칭이 틀리면 LED 쓰기가 EQ(EEPROM) 인덱스로 갈 수 있다.
final class ReplyMatchTests: XCTestCase {
    func testBuildUsesGivenSwID() {
        XCTAssertEqual(HIDPP.build(featureIndex: 0, fn: 0, params: [], swID: 3)[3], 0x03)
    }
    func testStaleReplyWithOtherSwIDDoesNotMatch() {
        let late = HIDPP.parse(HIDPP.build(featureIndex: 0, fn: 0, params: [4], swID: 1))!   // 이전 요청(sw 1)의 응답
        XCTAssertFalse(HIDPP.matches(late, feature: 0, fn: 0, swID: 2))
        XCTAssertTrue(HIDPP.matches(late, feature: 0, fn: 0, swID: 1))
    }
    func testErrorReplyMatchesOnlySameSwID() {
        let err = HIDPP.parse(hex("11ffff0633020000000000000000000000000000"))!   // feature 6, fn3|sw3, INVALID_ARGUMENT
        XCTAssertTrue(HIDPP.matches(err, feature: 6, fn: 3, swID: 3))
        XCTAssertFalse(HIDPP.matches(err, feature: 6, fn: 3, swID: 4))
    }
    func testFeatureMapMustHaveDistinctIndices() {
        XCTAssertTrue(G560Device.plausible([0: 0, 0x8070: 4, 0x8305: 9, 0x8310: 6, 0x8040: 8]))
        XCTAssertFalse(G560Device.plausible([0: 0, 0x8070: 4, 0x8305: 4, 0x8310: 6]))   // 같은 인덱스 두 번 = 응답 뒤섞임
        XCTAssertFalse(G560Device.plausible([0: 0, 0x8305: 9]))                          // LED 없음
    }
}

/// 개발 빌드·설치본·g560ctl이 동시에 스피커에 명령을 보내지 못하게 하는 프로세스 락.
final class DeviceLockTests: XCTestCase {
    func testSecondHolderIsRefusedUntilFirstReleases() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("g560-lock-\(UUID()).lock").path
        let first = G560Device.acquireLock(at: path)
        XCTAssertNotNil(first)
        XCTAssertNil(G560Device.acquireLock(at: path))        // 다른 열린 파일은 같은 프로세스여도 거부됨 (flock)
        close(first!)
        let again = G560Device.acquireLock(at: path)
        XCTAssertNotNil(again)
        close(again!)
    }
}
