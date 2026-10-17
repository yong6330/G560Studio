/// HID++ 2.0 long report helpers. 순수 함수, 장치 접근 없음. (tools/hidpp.py 포팅)
public enum HIDPP {
    public static let reportID: UInt8 = 0x11
    public static let deviceIndex: UInt8 = 0xFF
    public static let length = 20
    public static let swID: UInt8 = 0x0A

    static let errorNames: [UInt8: String] = [
        0: "NO_ERROR", 1: "UNKNOWN", 2: "INVALID_ARGUMENT", 3: "OUT_OF_RANGE", 4: "HW_ERROR",
        5: "LOGITECH_INTERNAL", 6: "INVALID_FEATURE_INDEX", 7: "INVALID_FUNCTION_ID", 8: "BUSY", 9: "UNSUPPORTED",
    ]

    public static func build(featureIndex: UInt8, fn: UInt8, params: [UInt8], swID: UInt8 = swID) -> [UInt8] {
        precondition(fn <= 0xF && swID <= 0xF && params.count <= length - 4)
        var p = [reportID, deviceIndex, featureIndex, (fn << 4) | swID] + params
        p += [UInt8](repeating: 0, count: length - p.count)
        return p
    }

    /// 요청(feature, fn, swID)에 대한 응답인가. swID를 요청마다 바꾸므로 타임아웃 뒤 늦게 온 응답은 걸러진다.
    public static func matches(_ r: HIDPPReply, feature: UInt8, fn: UInt8, swID: UInt8) -> Bool {
        if let e = r.error { return e.origFeature == feature && e.origFnSw == (fn << 4 | swID) }
        return r.featureIndex == feature && r.fn == fn && r.swID == swID
    }

    public static func parse(_ r: [UInt8]) -> HIDPPReply? {
        guard r.count == length, r[0] == reportID else { return nil }
        // 에러: [11][ff][ff][origFeature][origFn|sw][code] (실측)
        if r[2] == 0xFF {
            return HIDPPReply(featureIndex: 0xFF, fn: r[4] >> 4, swID: r[4] & 0xF, params: Array(r[4...]),
                              error: HIDPPError(origFeature: r[3], origFnSw: r[4], code: r[5]))
        }
        return HIDPPReply(featureIndex: r[2], fn: r[3] >> 4, swID: r[3] & 0xF, params: Array(r[4...]), error: nil)
    }
}

public struct HIDPPReply: Sendable {
    public let featureIndex: UInt8, fn: UInt8, swID: UInt8
    public let params: [UInt8]
    public let error: HIDPPError?
}

public struct HIDPPError: Error, Sendable {
    public let origFeature: UInt8, origFnSw: UInt8, code: UInt8
    public var name: String { HIDPP.errorNames[code] ?? "0x\(String(code, radix: 16))" }
}
