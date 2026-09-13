import Foundation

public struct ZoneColors: Codable, Equatable, Sendable, Hashable {
    public var zones: [RGB]
    public init(zones: [RGB]) { precondition(zones.count == G560.zoneCount); self.zones = zones }
    public init(all c: RGB) { zones = [RGB](repeating: c, count: G560.zoneCount) }
    public static let off = ZoneColors(all: .off)
}

/// 존 색의 출처: 사용자가 지정한 4색, 또는 시간에 따라 흐르는 레인보우.
public enum Palette: Codable, Equatable, Sendable, Hashable {
    case custom(ZoneColors)
    case rainbow(speed: Double)          // 사이클/초

    public func colors(t: TimeInterval) -> ZoneColors {
        switch self {
        case .custom(let z): return z
        case .rainbow(let speed):
            let base = Float(t * speed)
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
    /// 한 프레임의 4존 색. `envelope`는 사운드 반응 모드의 어택/릴리즈 상태 (호출자가 보관).
    func frame(t: TimeInterval, audio: AudioLevels, envelope: inout Float) -> ZoneColors {
        switch self {
        case .off:
            return .off
        case .fixed(let p):
            return p.colors(t: t)
        case .breathing(let p, let period):
            let k = 0.1 + 0.9 * Float(0.5 - 0.5 * cos(2 * .pi * t / period))
            return ZoneColors(zones: p.colors(t: t).zones.map { $0.scaled(k) })
        case .soundReactive(let p, let sens, let split):
            let z = p.colors(t: t)
            let target = min(1, audio.rms * Float(sens) * 2.5)
            envelope += (target - envelope) * (target > envelope ? 0.5 : 0.12)   // 어택 빠르게, 릴리즈 천천히
            let floor: Float = 0.12
            if split == .none { return ZoneColors(zones: z.zones.map { $0.scaled(floor + (1 - floor) * envelope) }) }
            let bass = floor + (1 - floor) * min(1, audio.low * Float(sens) * 2)
            let treble = floor + (1 - floor) * min(1, audio.high * Float(sens) * 2)
            let (front, rear) = split == .bassRear ? (treble, bass) : (bass, treble)   // 존 0,1 = 앞 / 2,3 = 뒤
            return ZoneColors(zones: [z.zones[0].scaled(front), z.zones[1].scaled(front),
                                      z.zones[2].scaled(rear), z.zones[3].scaled(rear)])
        }
    }
}
