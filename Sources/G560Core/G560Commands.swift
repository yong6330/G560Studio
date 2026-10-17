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
    public static let factoryBrightness = 100
}

/// docs/protocol.md 에서 재전송 검증된 명령만.
public extension G560Device {
    /// 0x8070 fn3 setZoneEffect(zone, fixed, rgb). 휘발성.
    /// 응답을 기다린다 — 연속 전송하면 USB 파이프가 stall 나므로(실측) 간격이 필요.
    func setZone(_ zone: Int, _ c: RGB) throws {
        _ = try call(feature: 0x8070, fn: 3, params: [UInt8(zone), 0x01, c.r, c.g, c.b, 0x02])
    }
    /// 0x8305 fn0
    func woofer() throws -> Int { Int(try call(feature: 0x8305, fn: 0, params: []).params[0]) }
    /// 0x8305 fn1
    /// 비휘발 설정(우퍼·밝기·EQ)은 읽어서 다를 때만 쓴다 — 연결·프로필 전환마다 같은 값을 다시 굽지 않도록.
    func setWoofer(_ level: Int) throws {
        let v = level.clamped(to: G560.wooferRange)
        if try woofer() == v { return }
        _ = try call(feature: 0x8305, fn: 1, params: [UInt8(v)])
    }
    /// 0x8040 fn1
    func brightness() throws -> Int { Int(try call(feature: 0x8040, fn: 1, params: []).params[1]) }
    /// 0x8040 fn2 [00 xx]
    func setBrightness(_ v: Int) throws {
        let v = v.clamped(to: 0...100)
        if try brightness() == v { return }
        _ = try call(feature: 0x8040, fn: 2, params: [0, UInt8(v)])
    }
    /// 0x8310 fn2
    func equalizer() throws -> [Int] {
        try call(feature: 0x8310, fn: 2, params: []).params.prefix(G560.eqBands).map { Int(Int8(bitPattern: $0)) }
    }
    /// 0x8310 fn3 [0x02][g0..g9] — EEPROM 쓰기. 슬라이더를 놓을 때만 호출할 것.
    func setEqualizer(_ gains: [Int]) throws {
        precondition(gains.count == G560.eqBands)
        let clamped = gains.map { $0.clamped(to: G560.eqRange) }
        if try equalizer() == clamped { return }
        let bytes = clamped.map { UInt8(bitPattern: Int8($0)) }
        _ = try call(feature: 0x8310, fn: 3, params: [0x02] + bytes)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
