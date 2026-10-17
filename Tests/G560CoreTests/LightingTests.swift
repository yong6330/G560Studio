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
    /// 프레임율이 달라도 포락선 속도는 같아야 한다 (10Hz 1틱 ≈ 30Hz 3틱)
    func testEnvelopeIsFrameRateIndependent() {
        let loud = AudioLevels(rms: 0.6, peak: 1, low: 0.5, mid: 0.5, high: 0.5)
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, split: .none)
        var a = LightingState(), b = LightingState()
        _ = cfg.frame(t: 0.1, audio: loud, state: &a); _ = cfg.frame(t: 0.2, audio: loud, state: &a)
        _ = cfg.frame(t: 0.1, audio: loud, state: &b)
        for i in 1...3 { _ = cfg.frame(t: 0.1 + Double(i) / 30, audio: loud, state: &b) }
        XCTAssertEqual(a.envelope, b.envelope, accuracy: 0.02)
    }
    /// 입력 평활: 버퍼마다 튀는 레벨의 분산은 줄고, 계단 입력은 ~50ms 안에 대부분 올라간다
    func testInputSmoothingCalmsJitterButFollowsStep() {
        var st = LightingState(); st.dt = 1.0 / 30
        var raw: [Float] = [], out: [Float] = []
        var seed: UInt32 = 1
        for _ in 0..<300 {
            seed = seed &* 1664525 &+ 1013904223
            let r = 0.1 + 0.4 * Float(seed >> 8) / Float(1 << 24)   // 0.1…0.5 무작위
            raw.append(r); out.append(st.smooth(AudioLevels(rms: r, peak: r, low: r, mid: r, high: r)).low)
        }
        func sd(_ v: ArraySlice<Float>) -> Float { let m = v.reduce(0, +) / Float(v.count); return sqrt(v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(v.count)) }
        XCTAssertLessThan(sd(out[30...]), sd(raw[30...]) * 0.6)
        var s2 = LightingState(); s2.dt = 0.025
        let up = AudioLevels(rms: 1, peak: 1, low: 1, mid: 1, high: 1)
        _ = s2.smooth(up)
        XCTAssertGreaterThan(s2.smooth(up).low, 0.6)   // 2틱 = 50ms
    }
    /// 오프라인 시뮬: 120BPM 킥(rms 0.25→0.06, ±30% 버퍼 요동)을 100Hz 버퍼 → 30Hz 프레임으로 먹여 실제 frame()의 밝기를 잰다.
    /// 박자마다 뚜렷이 꺼졌다 켜지고, 일정하게 큰 소리는 풀 밝기에 고정되지 않고, 무음은 어둡고, 박자 사이 요동은 억제돼야 한다.
    func testBeatsModulateBrightnessButJitterAndSteadyDont() {
        let cfg = LightingConfig.soundReactive(.rainbow(speed: 0.8), sensitivity: 0, split: .none)
        func sim(secs: Double, _ gen: (Double, inout UInt32) -> Float) -> [Float] {
            var st = LightingState(), seed: UInt32 = 12345, out: [Float] = [], buf: Float = 0, bt = 0.0
            for k in 0..<Int(secs * 30) {
                let t = Double(k) / 30
                while bt <= t { buf = gen(bt, &seed); bt += 0.01 }
                let z = cfg.frame(t: t + 1, audio: AudioLevels(rms: buf, peak: buf, low: buf, mid: buf, high: buf), state: &st).zones[0]
                out.append(Float(max(z.r, z.g, z.b)) / 255)
            }
            return out
        }
        func u(_ s: inout UInt32) -> Float { s = s &* 1664525 &+ 1013904223; return 2 * Float(s >> 8) / Float(1 << 24) - 1 }
        func beat(_ t: Double, _ jit: Float, _ s: inout UInt32) -> Float {
            let p = (t - 0.0137 + 0.5).truncatingRemainder(dividingBy: 0.5)
            return (0.06 + 0.19 * Float(exp(-p / 0.05))) * (1 + jit * u(&s))
        }
        let j = sim(secs: 20) { beat($0, 0.3, &$1) }, clean = sim(secs: 20) { beat($0, 0, &$1) }
        // 비트당 변조 깊이 (정상상태). 15프레임 = 1박
        let depths = (8..<39).map { b -> Float in let w = j[b * 15..<b * 15 + 15]; return w.max()! - w.min()! }
        XCTAssertGreaterThan(depths.reduce(0, +) / Float(depths.count), 0.4)
        // 박자 사이(비트 후 250ms~)의 프레임 간 변화 중 깨끗한 신호로 설명 안 되는 몫 = 요동. 직접 매핑(포락선 없음)은 ~0.05
        var dd: [Float] = []
        for k in 241..<j.count {
            let a = (Double(k - 1) / 30 - 0.0137).truncatingRemainder(dividingBy: 0.5), b = (Double(k) / 30 - 0.0137).truncatingRemainder(dividingBy: 0.5)
            if a >= 0.25 && b > a { dd.append((j[k] - j[k - 1]) - (clean[k] - clean[k - 1])) }
        }
        let sd = sqrt(dd.map { $0 * $0 }.reduce(0, +) / Float(dd.count))
        XCTAssertLessThan(sd, 0.015)
        // 일정하게 큰 소리(작은 요동): 풀 밝기에 고정되지 않는다
        let steady = Array(sim(secs: 20) { 0.3 * (1 + 0.1 * Float(sin(2 * .pi * 0.3 * $0))) * (1 + 0.08 * u(&$1)) }[240...])
        XCTAssertLessThan(Float(steady.filter { $0 >= 0.85 }.count) / Float(steady.count), 0.05)
        XCTAssertLessThan(steady.reduce(0, +) / Float(steady.count), 0.65)
        // 음악 → 무음: 다시 어두워진다
        let m = sim(secs: 15) { t, s in t < 3 || t >= 11 ? 0 : beat(t, 0.3, &s) }
        XCTAssertLessThan(m[390..<450].reduce(0, +) / 60, 0.2)
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
        let q = cfg.frame(t: 0, audio: quiet, state: &e).zones[0].r
        XCTAssertGreaterThan(q, 100)   // 조용해도 무음 바닥(~30)보다 훨씬 밝다. (일정한 소리는 풀 밝기가 아니라 중간 — 박자 대비를 위해)
        var l = LightingState()
        let loud = AudioLevels(rms: 0.5, peak: 1, low: 0, mid: 0, high: 0)
        for _ in 0..<30 { _ = cfg.frame(t: 0, audio: loud, state: &l) }
        XCTAssertEqual(Float(q), Float(cfg.frame(t: 0, audio: loud, state: &l).zones[0].r), accuracy: 30)   // 크기와 무관(정규화)
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
