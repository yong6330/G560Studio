import Foundation
import XCTest
@testable import G560Core

/// 2026-09-13 사고 후 안전장치의 순수 로직 (장치·CoreAudio 접근 없음).
final class SafetyTests: XCTestCase {
    // 볼륨 하한: 0·음수·NaN은 하한으로, 상한 1
    func testVolumeFloorAndCeiling() {
        XCTAssertEqual(OutputVolume.safe(0), OutputVolume.minVolume)
        XCTAssertEqual(OutputVolume.safe(-1), OutputVolume.minVolume)
        XCTAssertEqual(OutputVolume.safe(.nan), OutputVolume.minVolume)
        XCTAssertEqual(OutputVolume.safe(0.5), 0.5)
        XCTAssertEqual(OutputVolume.safe(7), 1)
        XCTAssertGreaterThan(OutputVolume.minVolume, 0)
    }
    func testVolumeDedupe() {
        XCTAssertTrue(OutputVolume.shouldWrite(current: nil, target: 0.3))
        XCTAssertFalse(OutputVolume.shouldWrite(current: 0.3, target: 0.3))
        XCTAssertFalse(OutputVolume.shouldWrite(current: 0.3, target: 0.3 + OutputVolume.epsilon / 2))
        XCTAssertTrue(OutputVolume.shouldWrite(current: 0.3, target: 0.3 + OutputVolume.epsilon * 2))
    }
    func testProfileVolumeClampedOnInitAndDecode() throws {
        let p = Profile.makeDefault(name: "t")
        let q = Profile(id: p.id, name: "t", lighting: p.lighting, volume: 0, woofer: 40, eq: p.eq)
        XCTAssertEqual(q.volume, OutputVolume.minVolume)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json["volume"] = 0.0
        let d = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(d.volume, OutputVolume.minVolume)
    }

    // 차단기: BUSY/HW_ERROR 응답은 장애로 세고, INVALID_ARGUMENT 류는 세지 않는다
    func testBreakerErrorClassification() {
        func e(_ c: UInt8) -> HIDPPError { HIDPPError(origFeature: 0, origFnSw: 0, code: c) }
        for c: UInt8 in [1, 4, 5, 8, 0x20] { XCTAssertTrue(Breaker.countsAsFailure(e(c)), "code \(c)") }
        for c: UInt8 in [2, 3, 6, 7, 9] { XCTAssertFalse(Breaker.countsAsFailure(e(c)), "code \(c)") }
    }
    // 명령 간격: 비휘발 쓰기 뒤는 길게, LED·읽기는 짧게 (그래도 0은 아님)
    func testCommandGap() {
        XCTAssertEqual(G560Device.gap(afterFeature: 0x8070, fn: 3), G560Device.minGap)
        XCTAssertEqual(G560Device.gap(afterFeature: 0x8305, fn: 0), G560Device.minGap)
        for (f, fn) in [(0x8305, 1), (0x8310, 3), (0x8040, 2)] as [(UInt16, UInt8)] { XCTAssertEqual(G560Device.gap(afterFeature: f, fn: fn), G560Device.nvGap) }
        XCTAssertGreaterThan(G560Device.minGap, 0)
    }
    func testBreakerOpensOnRepeatedBusy() {
        var b = Breaker(); let t = Date()
        for _ in 0..<Breaker.threshold { b.record(false, at: t) }
        XCTAssertTrue(b.isOpen(at: t))
    }

    // 재연결 반복: 60초 안에 3번째 attach부터 보류, 창이 지나면 풀림
    func testFlapGuard() {
        var f = FlapGuard(); let t = Date()
        f.record(at: t); f.record(at: t + 10)
        XCTAssertFalse(f.isFlapping(at: t + 10))
        f.record(at: t + 20)
        XCTAssertTrue(f.isFlapping(at: t + 20))
        XCTAssertTrue(f.isFlapping(at: t + 59))
        XCTAssertFalse(f.isFlapping(at: t + FlapGuard.window + 11))   // 가장 오래된 둘이 창 밖
    }
    func testFlapGuardSlowReconnectsNeverHold() {
        var f = FlapGuard(); let t = Date()
        for i in 0..<10 { f.record(at: t + Double(i) * 40) }
        XCTAssertFalse(f.isFlapping(at: t + 360))
    }

    // 기능 인덱스 가드
    func testResolveFeatureIndex() {
        let m: [UInt16: UInt8] = [0: 0, 0x8070: 4, 0x8310: 6, 0x8305: 9, 0x8040: 8]
        XCTAssertEqual(G560Device.resolve(m, feature: 0x8070, fn: 3), 4)
        XCTAssertEqual(G560Device.resolve(m, feature: 0x8310, fn: 3), 6)
        XCTAssertNil(G560Device.resolve(m, feature: 0x8070, fn: 1))          // 허용 안 된 fn
        XCTAssertNil(G560Device.resolve(m, feature: 0x8010, fn: 0))          // 모르는 기능 (GKEY)
        XCTAssertNil(G560Device.resolve(m, feature: 0x8320, fn: 0))
        var dup = m; dup[0x8310] = 4                                          // 인덱스 중복 = 표가 뒤섞임
        XCTAssertNil(G560Device.resolve(dup, feature: 0x8070, fn: 3))
        XCTAssertNil(G560Device.resolve(dup, feature: 0x8310, fn: 3))
        var zero = m; zero[0x8070] = 0                                        // 비루트 기능이 ROOT 인덱스
        XCTAssertNil(G560Device.resolve(zero, feature: 0x8070, fn: 3))
    }
}
