import XCTest
@testable import G560Core

final class LightingTests: XCTestCase {
    let red = Palette.custom(ZoneColors(all: RGB(255, 0, 0)))
    let redZ = ZoneColors(all: RGB(255, 0, 0))
    func testOff() { var e = LightingState(); XCTAssertEqual(LightingConfig.off.frame(t: 1, audio: .silence, state: &e), .off) }
    func testFixedIgnoresAudio() {
        var e = LightingState()
        XCTAssertEqual(LightingConfig.fixed(red).frame(t: 5, audio: AudioLevels(rms: 1, peak: 1, low: 1, mid: 1, high: 1), state: &e), redZ)
    }
    func testBreathingDimsAtHalfPeriod() {
        var e = LightingState()
        let top = LightingConfig.breathing(red, period: 2).frame(t: 1.0, audio: .silence, state: &e).zones[0]
        let bottom = LightingConfig.breathing(red, period: 2).frame(t: 0.0, audio: .silence, state: &e).zones[0]
        XCTAssertGreaterThan(top.r, 200); XCTAssertLessThan(bottom.r, 60)
    }
    func testRainbowChangesHueOverTime() {
        var e = LightingState()
        let a = LightingConfig.fixed(.rainbow(speed: 0.5)).frame(t: 0, audio: .silence, state: &e)
        let b = LightingConfig.fixed(.rainbow(speed: 0.5)).frame(t: 1, audio: .silence, state: &e)
        XCTAssertNotEqual(a, b)
    }
    func testSoundReactiveSilenceIsDimNotOff() {
        var e = LightingState()
        let z = LightingConfig.soundReactive(red, sensitivity: 1, split: .none).frame(t: 0, audio: .silence, state: &e).zones[0]
        XCTAssertGreaterThan(z.r, 0); XCTAssertLessThan(z.r, 60)
    }
    func testSoundReactiveLoudIsBright() {
        var e = LightingState()
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, split: .none)
        let loud = AudioLevels(rms: 0.6, peak: 1, low: 0.5, mid: 0.5, high: 0.5)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: loud, state: &e) }   // 어택 수렴
        XCTAssertGreaterThan(cfg.frame(t: 0, audio: loud, state: &e).zones[0].r, 200)
    }
    func testSplitBandsSendsBassToRear() {
        var e = LightingState()
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, split: .bassRear)
        let bass = AudioLevels(rms: 0.5, peak: 0.8, low: 0.9, mid: 0, high: 0)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: bass, state: &e) }
        let f = cfg.frame(t: 0, audio: bass, state: &e)
        XCTAssertGreaterThan(f.zones[2].r, f.zones[0].r)   // 좌 뒤 > 좌 앞
    }
}

final class AutoLightingTests: XCTestCase {
    func testAutoSensitivityNormalizesQuietMusic() {
        var e = LightingState()
        let cfg = LightingConfig.soundReactive(.custom(ZoneColors(all: RGB(255, 0, 0))), sensitivity: 0, split: .none)
        let quiet = AudioLevels(rms: 0.05, peak: 0.1, low: 0, mid: 0, high: 0)
        for _ in 0..<30 { _ = cfg.frame(t: 0, audio: quiet, state: &e) }
        XCTAssertGreaterThan(cfg.frame(t: 0, audio: quiet, state: &e).zones[0].r, 180)   // 조용해도 꽉 참
    }
    func testAutoRainbowAdvancesFasterWhenLoud() {
        var a = LightingState(), b = LightingState()
        let p = Palette.rainbow(speed: 0)
        _ = p.colors(t: 0, audio: .silence, state: &a); _ = p.colors(t: 0, audio: .silence, state: &b)
        for i in 1...20 {
            _ = p.colors(t: Double(i) * 0.033, audio: .silence, state: &a)
            _ = p.colors(t: Double(i) * 0.033, audio: AudioLevels(rms: 0.5, peak: 1, low: 0, mid: 0, high: 0), state: &b)
        }
        XCTAssertGreaterThan(b.hue, a.hue)
    }
}
