import Foundation

public struct ZoneColors: Codable, Equatable, Sendable, Hashable {
    public var zones: [RGB]
    public init(zones: [RGB]) { precondition(zones.count == G560.zoneCount); self.zones = zones }
    public init(all c: RGB) { zones = [RGB](repeating: c, count: G560.zoneCount) }
    public static let off = ZoneColors(all: .off)
}

public enum LightingConfig: Codable, Equatable, Sendable, Hashable {
    case off
    case fixed(ZoneColors)
    case colorCycle(speed: Double)                                  // 사이클/초
    case breathing(ZoneColors, period: Double)                      // 초
    case soundReactive(ZoneColors, sensitivity: Double, splitBands: Bool)
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
        case .fixed(let z):
            return z
        case .colorCycle(let speed):
            let base = Float(t * speed)
            return ZoneColors(zones: (0..<G560.zoneCount).map { RGB.hue(base + Float($0) * 0.08) })
        case .breathing(let z, let period):
            let k = 0.1 + 0.9 * Float(0.5 - 0.5 * cos(2 * .pi * t / period))
            return ZoneColors(zones: z.zones.map { $0.scaled(k) })
        case .soundReactive(let z, let sens, let split):
            let target = min(1, audio.rms * Float(sens) * 2.5)
            envelope += (target - envelope) * (target > envelope ? 0.5 : 0.12)   // 어택 빠르게, 릴리즈 천천히
            let floor: Float = 0.12
            if !split { return ZoneColors(zones: z.zones.map { $0.scaled(floor + (1 - floor) * envelope) }) }
            let front = floor + (1 - floor) * min(1, audio.high * Float(sens) * 2)   // 존 0,1 = 앞
            let rear = floor + (1 - floor) * min(1, audio.low * Float(sens) * 2)     // 존 2,3 = 뒤
            return ZoneColors(zones: [z.zones[0].scaled(front), z.zones[1].scaled(front),
                                      z.zones[2].scaled(rear), z.zones[3].scaled(rear)])
        }
    }
}
