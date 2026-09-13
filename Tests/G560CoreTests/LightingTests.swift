import XCTest
@testable import G560Core

final class LightingTests: XCTestCase {
    let red = Palette.custom(ZoneColors(all: RGB(255, 0, 0)))
    let redZ = ZoneColors(all: RGB(255, 0, 0))
    func testOff() { var e: Float = 0; XCTAssertEqual(LightingConfig.off.frame(t: 1, audio: .silence, envelope: &e), .off) }
    func testFixedIgnoresAudio() {
        var e: Float = 0
        XCTAssertEqual(LightingConfig.fixed(red).frame(t: 5, audio: AudioLevels(rms: 1, peak: 1, low: 1, mid: 1, high: 1), envelope: &e), redZ)
    }
    func testBreathingDimsAtHalfPeriod() {
        var e: Float = 0
        let top = LightingConfig.breathing(red, period: 2).frame(t: 1.0, audio: .silence, envelope: &e).zones[0]
        let bottom = LightingConfig.breathing(red, period: 2).frame(t: 0.0, audio: .silence, envelope: &e).zones[0]
        XCTAssertGreaterThan(top.r, 200); XCTAssertLessThan(bottom.r, 60)
    }
    func testRainbowChangesHueOverTime() {
        var e: Float = 0
        let a = LightingConfig.fixed(.rainbow(speed: 0.5)).frame(t: 0, audio: .silence, envelope: &e)
        let b = LightingConfig.fixed(.rainbow(speed: 0.5)).frame(t: 1, audio: .silence, envelope: &e)
        XCTAssertNotEqual(a, b)
    }
    func testSoundReactiveSilenceIsDimNotOff() {
        var e: Float = 0
        let z = LightingConfig.soundReactive(red, sensitivity: 1, split: .none).frame(t: 0, audio: .silence, envelope: &e).zones[0]
        XCTAssertGreaterThan(z.r, 0); XCTAssertLessThan(z.r, 60)
    }
    func testSoundReactiveLoudIsBright() {
        var e: Float = 0
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, split: .none)
        let loud = AudioLevels(rms: 0.6, peak: 1, low: 0.5, mid: 0.5, high: 0.5)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: loud, envelope: &e) }   // 어택 수렴
        XCTAssertGreaterThan(cfg.frame(t: 0, audio: loud, envelope: &e).zones[0].r, 200)
    }
    func testSplitBandsSendsBassToRear() {
        var e: Float = 0
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, split: .bassRear)
        let bass = AudioLevels(rms: 0.5, peak: 0.8, low: 0.9, mid: 0, high: 0)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: bass, envelope: &e) }
        let f = cfg.frame(t: 0, audio: bass, envelope: &e)
        XCTAssertGreaterThan(f.zones[2].r, f.zones[0].r)   // 좌 뒤 > 좌 앞
    }
}
