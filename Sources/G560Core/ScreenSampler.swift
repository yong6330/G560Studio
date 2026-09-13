import Foundation
import ScreenCaptureKit
import CoreVideo
import AppKit

/// 메인 화면을 저해상도·저fps로 캡처해 네 구역 평균색을 낸다. 화면 기록 권한 필요.
/// 존 매핑: 2=좌 뒤 ← 좌상, 3=우 뒤 ← 우상, 0=좌 앞 ← 좌하, 1=우 앞 ← 우하.
/// 진단용 파일 로그 (~/Library/Application Support/G560Studio/sampler.log)
func samplerLog(_ msg: String) {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("G560Studio/sampler.log")
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

public final class ScreenSampler: NSObject, SCStreamOutput, @unchecked Sendable {
    public private(set) var colors = ZoneColors.off
    public private(set) var isRunning = false
    public private(set) var lastError: String?
    /// nil = 메인 디스플레이
    public var displayID: CGDirectDisplayID? { didSet { if displayID != oldValue, isRunning { stop(); start() } } }
    public var inset: Float = 0        // 0 = 가장자리, 0.4 = 안쪽
    public var boost: Float = 1        // 채도/밝기 강도
    private var stream: SCStream?
    private var frames = 0

    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    /// 시스템 팝업. 허용 후엔 앱 재시작이 필요할 수 있다.
    public static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    public struct DisplayInfo: Identifiable, Hashable, Sendable { public let id: CGDirectDisplayID; public let name: String; public let isMain: Bool }
    public static func displays() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).map { id in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
            return DisplayInfo(id: id, name: screen?.localizedName ?? "디스플레이 \(id)", isMain: CGDisplayIsMain(id) != 0)
        }
    }
    private let queue = DispatchQueue(label: "screen-sampler")
    private var smooth: [(Float, Float, Float)] = Array(repeating: (0, 0, 0), count: G560.zoneCount)

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        samplerLog("start permission=\(Self.hasPermission)")
        Task { [self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let wanted = displayID ?? CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == wanted }) ?? content.displays.first else {
                    lastError = "디스플레이를 찾지 못했습니다"; isRunning = false; return
                }
                let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.width = 64; cfg.height = 36
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)   // ponytail: 10fps 고정
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.showsCursor = false
                cfg.queueDepth = 2
                let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                stream = s
                lastError = nil
                samplerLog("capturing display \(display.displayID)")
            } catch {
                isRunning = false
                lastError = Self.hasPermission ? "\(error.localizedDescription)" : "화면 기록 권한이 없습니다"
                samplerLog("error: \(error)")
            }
        }
    }

    public func stop() {
        guard let s = stream else { isRunning = false; return }
        stream = nil; isRunning = false
        Task { try? await s.stopCapture() }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        if frames == 0 { samplerLog("first frame \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb))") }
        frames += 1
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb)
        let px = base.assumingMemoryBound(to: UInt8.self)
        // 구역: (x범위, y범위) — 가장자리 40%만 본다 (화면 중앙은 제외)
        func avg(_ xr: Range<Int>, _ yr: Range<Int>) -> (Float, Float, Float) {
            var r: Float = 0, g: Float = 0, b: Float = 0, n: Float = 0
            for y in yr { for x in xr {
                let o = y * stride + x * 4
                b += Float(px[o]); g += Float(px[o + 1]); r += Float(px[o + 2]); n += 1
            } }
            return (r / n, g / n, b / n)
        }
        // 띠 두께 30%, inset 만큼 안쪽으로 이동
        let band = Int(Float(h) * 0.3), off = Int(Float(h) * min(0.4, max(0, inset)))
        let top = off..<min(h, off + band), bottom = max(0, h - off - band)..<(h - off)
        let raw = [avg(0..<w / 2, bottom), avg(w / 2..<w, bottom),   // 0 좌앞(좌하), 1 우앞(우하)
                   avg(0..<w / 2, top), avg(w / 2..<w, top)]         // 2 좌뒤(좌상), 3 우뒤(우상)
        for i in 0..<G560.zoneCount {   // 채도 살짝 올리고 EMA로 부드럽게
            let (r, g, b) = boost(raw[i])
            smooth[i] = (smooth[i].0 + (r - smooth[i].0) * 0.35, smooth[i].1 + (g - smooth[i].1) * 0.35, smooth[i].2 + (b - smooth[i].2) * 0.35)
        }
        colors = ZoneColors(zones: smooth.map { RGB(UInt8(min(255, $0.0)), UInt8(min(255, $0.1)), UInt8(min(255, $0.2))) })
    }

    /// 평균색은 탁해지기 쉬우니 채도를 1.6배, 최대값을 255 쪽으로 당긴다.
    private func boost(_ c: (Float, Float, Float)) -> (Float, Float, Float) {
        let mx = max(c.0, c.1, c.2), mn = min(c.0, c.1, c.2)
        guard mx > 8 else { return (0, 0, 0) }
        let sat: Float = 1.2 + 0.8 * boost
        let mean = (c.0 + c.1 + c.2) / 3
        var r = mean + (c.0 - mean) * sat, g = mean + (c.1 - mean) * sat, b = mean + (c.2 - mean) * sat
        let k = 255 / max(r, g, b, 1) * min(1, (mx - mn) / 60 * boost + 0.5)   // 밝기 정규화 (회색은 덜 밝게)
        r = max(0, r * k); g = max(0, g * k); b = max(0, b * k)
        return (r, g, b)
    }
}
