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

    public static func build(featureIndex: UInt8, fn: UInt8, params: [UInt8]) -> [UInt8] {
        precondition(fn <= 0xF && params.count <= length - 4)
        var p = [reportID, deviceIndex, featureIndex, (fn << 4) | swID] + params
        p += [UInt8](repeating: 0, count: length - p.count)
        return p
    }

    public static func parse(_ r: [UInt8]) -> HIDPPReply? {
        guard r.count == length, r[0] == reportID else { return nil }
        let params = Array(r[4...])
        let err = r[2] == 0xFF ? HIDPPError(origFeature: params[0], origFnSw: params[1], code: params[2]) : nil
        return HIDPPReply(featureIndex: r[2], fn: r[3] >> 4, swID: r[3] & 0xF, params: params, error: err)
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
