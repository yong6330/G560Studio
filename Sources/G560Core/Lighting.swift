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
