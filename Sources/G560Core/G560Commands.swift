public struct RGB: Codable, Equatable, Sendable, Hashable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let off = RGB(0, 0, 0)
    public var hex: String { String(format: "%02X%02X%02X", r, g, b) }
}

public enum G560 {
    public static let zoneCount = 4
    public static let zoneNames = ["좌 앞", "우 앞", "좌 뒤", "우 뒤"]      // protocol.md 실측 매핑
    public static let eqBands = 10
    public static let eqFrequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let eqRange = -20...6
    public static let wooferRange = 0...100
    public static let factoryWoofer = 40
    public static let factoryEQ = [Int](repeating: 0, count: eqBands)
}

/// docs/protocol.md 에서 재전송 검증된 명령만.
public extension G560Device {
    /// 0x8070 fn3 setZoneEffect(zone, fixed, rgb). 휘발성.
    func setZone(_ zone: Int, _ c: RGB) throws {
        try send(feature: 0x8070, fn: 3, params: [UInt8(zone), 0x01, c.r, c.g, c.b, 0x02])
    }
    /// 0x8305 fn0
    func woofer() throws -> Int { Int(try call(feature: 0x8305, fn: 0, params: []).params[0]) }
    /// 0x8305 fn1
    func setWoofer(_ level: Int) throws {
        _ = try call(feature: 0x8305, fn: 1, params: [UInt8(level.clamped(to: G560.wooferRange))])
    }
    /// 0x8310 fn2
    func equalizer() throws -> [Int] {
        try call(feature: 0x8310, fn: 2, params: []).params.prefix(G560.eqBands).map { Int(Int8(bitPattern: $0)) }
    }
    /// 0x8310 fn3 [0x02][g0..g9] — EEPROM 쓰기. 슬라이더를 놓을 때만 호출할 것.
    func setEqualizer(_ gains: [Int]) throws {
        precondition(gains.count == G560.eqBands)
        let bytes = gains.map { UInt8(bitPattern: Int8($0.clamped(to: G560.eqRange))) }
        _ = try call(feature: 0x8310, fn: 3, params: [0x02] + bytes)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
