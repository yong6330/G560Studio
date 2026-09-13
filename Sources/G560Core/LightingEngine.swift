import Foundation

/// 30Hz로 현재 config의 프레임을 계산해 바뀐 존만 장치에 쓴다.
public final class LightingEngine: @unchecked Sendable {
    public var config: LightingConfig = .off { didSet { queue.async { self.syncScreen() } } }
    public let screen = ScreenSampler()
    public var enabled = true { didSet { if !enabled { blackout() } } }
    public private(set) var lastFrame: ZoneColors = .off
    private let device: G560Device
    private var audio = AudioLevels.silence
    private var envelope: Float = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "lighting")
    private let t0 = Date()

    public init(device: G560Device) { self.device = device }

    public func update(audio: AudioLevels) { queue.async { self.audio = audio } }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))   // ponytail: 30Hz 고정, 장치가 버거우면 여기만 조정
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// 재연결·프로필 교체 시 전 존 강제 재전송
    public func resend() {
        queue.async {
            guard self.enabled else { return }
            self.lastFrame = ZoneColors(all: RGB(1, 1, 1))
            self.push(self.config.frame(t: Date().timeIntervalSince(self.t0), audio: self.audio, envelope: &self.envelope, screen: self.screen.colors))
        }
    }

    private func tick() {
        guard enabled, device.isConnected else { return }
        push(config.frame(t: Date().timeIntervalSince(t0), audio: audio, envelope: &envelope, screen: screen.colors))
    }

    /// 화면 샘플러 모드일 때만 캡처 (권한 팝업도 그때만)
    private func syncScreen() {
        if case .screenSampler(let o) = config {
            screen.inset = Float(o.inset); screen.boost = Float(o.boost); screen.displayID = o.display; screen.start()
        } else { screen.stop() }
    }

    private func push(_ f: ZoneColors) {
        for z in 0..<G560.zoneCount where f.zones[z] != lastFrame.zones[z] {
            do { try device.setZone(z, f.zones[z]) } catch { FileHandle.standardError.write("setZone \(z): \(error)\n".data(using: .utf8)!) }
        }
        lastFrame = f
    }

    private func blackout() { queue.async { self.push(.off) } }
}
