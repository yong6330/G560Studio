import Foundation

/// 30Hz로 현재 config의 프레임을 계산해 바뀐 존만 장치에 쓴다.
public final class LightingEngine: @unchecked Sendable {
    public var config: LightingConfig = .off { didSet { queue.async { self.syncScreen() } } }
    public let screen = ScreenSampler()
    /// 소프트웨어 밝기 0…100. 장치의 0x8040은 실질적으로 on/off라(실측) 프레임 단계에서 스케일한다.
    public var brightness = 100
    public var enabled = true { didSet { if !enabled { blackout() } } }
    public private(set) var lastFrame: ZoneColors = .off
    private var sent = ZoneColors(all: RGB(1, 1, 1))   // 장치에 실제로 보낸 마지막 색
    private let device: G560Device
    private var audio = AudioLevels.silence
    private var state = LightingState()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "lighting")
    private let t0 = Date()

    public init(device: G560Device) { self.device = device }

    public func update(audio: AudioLevels) { queue.async { self.audio = audio } }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(42))   // ~24Hz. 존별 HID 왕복이 CPU 대부분이라 여기가 최대 지렛대
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// 재연결·프로필 교체 시 전 존 강제 재전송
    public func resend() {
        queue.async {
            guard self.enabled else { return }
            self.lastFrame = ZoneColors(all: RGB(1, 1, 1)); self.sent = ZoneColors(all: RGB(1, 1, 1))
            self.push(self.config.frame(t: Date().timeIntervalSince(self.t0), audio: self.audio, state: &self.state, screen: self.screen.colors))
        }
    }

    private func tick() {
        guard enabled, device.isConnected else { return }
        push(config.frame(t: Date().timeIntervalSince(t0), audio: audio, state: &state, screen: screen.colors))
    }

    /// 화면 샘플러 모드일 때만 캡처 (권한 팝업도 그때만)
    private func syncScreen() {
        if case .screenSampler(let o) = config {
            screen.inset = Float(o.inset); screen.boost = Float(o.boost); screen.displayID = o.display; screen.start()
        } else { screen.stop() }
    }

    private func push(_ frame: ZoneColors) {
        let k = Float(max(0, min(100, brightness))) / 100
        let f = k >= 1 ? frame : ZoneColors(zones: frame.zones.map { $0.scaled(k) })
        for z in 0..<G560.zoneCount {
            let c = f.zones[z], p = sent.zones[z]
            // 채널당 4 미만 변화는 눈에 안 띄므로 전송 생략 → 느린 페이드에서 USB 왕복 대폭 감소
            let d = max(abs(Int(c.r) - Int(p.r)), abs(Int(c.g) - Int(p.g)), abs(Int(c.b) - Int(p.b)))
            if d >= 4 || (c == .off && p != .off) {
                do { try device.setZone(z, c); sent.zones[z] = c }
                catch { FileHandle.standardError.write("setZone \(z): \(error)\n".data(using: .utf8)!) }
            }
        }
        lastFrame = f
    }

    private func blackout() { queue.async { self.push(.off) } }
}
