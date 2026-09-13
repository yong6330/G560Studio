import Foundation

public struct ZoneColors: Codable, Equatable, Sendable, Hashable {
    public var zones: [RGB]
    public init(zones: [RGB]) { precondition(zones.count == G560.zoneCount); self.zones = zones }
    public init(all c: RGB) { zones = [RGB](repeating: c, count: G560.zoneCount) }
    public static let off = ZoneColors(all: .off)
}

/// 존 색의 출처: 사용자가 지정한 4색, 또는 시간에 따라 흐르는 레인보우.
/// 프레임 간 유지되는 상태 (호출자가 보관). 어택/릴리즈 포락선, AGC 피크, 자동 속도용 위상.
public struct LightingState: Sendable {
    public var envelope: Float = 0
    public var peak: Float = 0.05        // 최근 피크 (천천히 감쇠) — 자동 감도
    public var hue: Float = 0            // 자동 속도 레인보우의 누적 위상
    public var lastT: TimeInterval = 0
    public init() {}

    /// rms → 0…1 밝기 목표. sensitivity <= 0 이면 자동(AGC).
    mutating func level(rms: Float, sensitivity: Double) -> Float {
        if sensitivity > 0 { return min(1, rms * Float(sensitivity) * 2.5) }
        peak = max(rms, peak * 0.995)                // ponytail: 약 6초 반감, 튜닝 상수
        return min(1, rms / max(peak, 0.02) * 0.9)
    }
    mutating func step(target: Float) -> Float {
        envelope += (target - envelope) * (target > envelope ? 0.5 : 0.12)
        return envelope
    }
}

public enum Palette: Codable, Equatable, Sendable, Hashable {
    case custom(ZoneColors)
    case rainbow(speed: Double)          // 사이클/초. <= 0 이면 자동(소리에 따라 가속)

    public func colors(t: TimeInterval, audio: AudioLevels = .silence, state: inout LightingState) -> ZoneColors {
        switch self {
        case .custom(let z): return z
        case .rainbow(let speed):
            let base: Float
            if speed > 0 { base = Float(t * speed) }
            else {   // 자동: 기본 0.03/초 + 소리 크기에 비례해 최대 +0.5/초
                let dt = state.lastT == 0 ? 0 : max(0, min(0.2, t - state.lastT))
                state.hue += Float(dt) * (0.03 + 0.5 * min(1, audio.rms * 3))
                state.lastT = t
                base = state.hue
            }
            return ZoneColors(zones: (0..<G560.zoneCount).map { RGB.hue(base + Float($0) * 0.08) })
        }
    }
}

/// 사운드 반응 시 저음/고음을 어느 존에 보낼지.
public enum BandSplit: String, Codable, CaseIterable, Sendable {
    case none, bassRear, bassFront
}

public enum LightingConfig: Codable, Equatable, Sendable, Hashable {
    case off
    case fixed(Palette)
    case breathing(Palette, period: Double)                            // 초
    case soundReactive(Palette, sensitivity: Double, split: BandSplit)
    case screenSampler(ScreenOptions)
}

/// 화면 샘플러 옵션. 저장 파일에 키가 없으면 기본값 (버전 간 호환).
public struct ScreenOptions: Codable, Equatable, Sendable, Hashable {
    public var display: UInt32? = nil     // nil = 메인 디스플레이
    public var inset: Double = 0.0        // 0 = 가장자리, 0.4 = 화면 안쪽
    public var boost: Double = 1.0        // 채도/밝기 강도 0.5…2
    public var audio: Bool = false        // true = 다이나믹: 밝기는 소리로
    public var sensitivity: Double = 1.5  // 다이나믹 감도. <= 0 이면 자동
    public init(display: UInt32? = nil, inset: Double = 0, boost: Double = 1, audio: Bool = false, sensitivity: Double = 1.5) {
        self.display = display; self.inset = inset; self.boost = boost; self.audio = audio; self.sensitivity = sensitivity
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        display = try c.decodeIfPresent(UInt32.self, forKey: .display)
        inset = try c.decodeIfPresent(Double.self, forKey: .inset) ?? 0
        boost = try c.decodeIfPresent(Double.self, forKey: .boost) ?? 1
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.5
    }
}

extension RGB {
    func scaled(_ k: Float) -> RGB {
        let k = max(0, min(1, k))
        return RGB(UInt8(Float(r) * k), UInt8(Float(g) * k), UInt8(Float(b) * k))
    }
    /// h 0…1 → 채도/명도 1인 색상환
    static func hue(_ h: Float) -> RGB {
        let x = (h - floor(h)) * 6, i = Int(x), f = x - Float(i)
        let q = UInt8((1 - f) * 255), t = UInt8(f * 255)
        switch i {
        case 0: return RGB(255, t, 0)
        case 1: return RGB(q, 255, 0)
        case 2: return RGB(0, 255, t)
        case 3: return RGB(0, q, 255)
        case 4: return RGB(t, 0, 255)
        default: return RGB(255, 0, q)
        }
    }
}

public extension LightingConfig {
    /// 한 프레임의 4존 색. `state`는 프레임 간 상태 (호출자가 보관).
    func frame(t: TimeInterval, audio: AudioLevels, state: inout LightingState, screen: ZoneColors = .off) -> ZoneColors {
        defer { state.lastT = t }
        switch self {
        case .off:
            return .off
        case .screenSampler(let o):
            guard o.audio else { return screen }
            let env = state.step(target: state.level(rms: audio.rms, sensitivity: o.sensitivity))
            let floor: Float = 0.15
            return ZoneColors(zones: screen.zones.map { $0.scaled(floor + (1 - floor) * env) })
        case .fixed(let p):
            return p.colors(t: t, audio: audio, state: &state)
        case .breathing(let p, let period):
            let k = 0.1 + 0.9 * Float(0.5 - 0.5 * cos(2 * .pi * t / period))
            return ZoneColors(zones: p.colors(t: t, audio: audio, state: &state).zones.map { $0.scaled(k) })
        case .soundReactive(let p, let sens, let split):
            let z = p.colors(t: t, audio: audio, state: &state)
            let env = state.step(target: state.level(rms: audio.rms, sensitivity: sens))
            let floor: Float = 0.12
            if split == .none { return ZoneColors(zones: z.zones.map { $0.scaled(floor + (1 - floor) * env) }) }
            let gain = sens > 0 ? Float(sens) * 2 : 0.9 / max(state.peak, 0.02)   // 자동이면 AGC 게인 공유
            let bass = floor + (1 - floor) * min(1, audio.low * gain)
            let treble = floor + (1 - floor) * min(1, audio.high * gain)
            let (front, rear) = split == .bassRear ? (treble, bass) : (bass, treble)   // 존 0,1 = 앞 / 2,3 = 뒤
            return ZoneColors(zones: [z.zones[0].scaled(front), z.zones[1].scaled(front),
                                      z.zones[2].scaled(rear), z.zones[3].scaled(rear)])
        }
    }
}
