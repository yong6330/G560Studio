import Foundation

/// 20Hz로 현재 config의 프레임을 계산해 바뀐 존만 장치에 쓴다.
public final class LightingEngine: @unchecked Sendable {
    public var config: LightingConfig {
        get { lock.withLock { _config } }
        set { lock.withLock { _config = newValue }; queue.async { self.syncScreen() } }
    }
    public let screen = ScreenSampler()
    /// 소프트웨어 밝기 0…100. 장치의 0x8040은 실질적으로 on/off라(실측) 프레임 단계에서 스케일한다.
    public var brightness: Int {
        get { lock.withLock { _brightness } }
        set { lock.withLock { _brightness = newValue } }
    }
    public var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue }; if !newValue { blackout() } }
    }
    public var lastFrame: ZoneColors { lock.withLock { _lastFrame } }
    /// 메인 스레드가 쓰고 엔진 큐가 읽는 값. enum·배열을 락 없이 공유하면 크래시할 수 있다.
    private let lock = NSLock()
    private var _config = LightingConfig.off, _brightness = 100, _enabled = true, _lastFrame = ZoneColors.off
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
        t.schedule(deadline: .now(), repeating: .milliseconds(50))   // 20Hz. 장치 USB 부하를 낮추려 빈도 제한
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// 재연결·프로필 교체 시 전 존 강제 재전송
    public func resend() {
        queue.async {
            guard self.enabled, self.device.isConnected else { return }
            self.sent = ZoneColors(all: RGB(1, 1, 1))
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
            // 채널당 6 미만 변화는 눈에 안 띄므로 전송 생략 → 느린 페이드에서 USB 왕복 대폭 감소
            let d = max(abs(Int(c.r) - Int(p.r)), abs(Int(c.g) - Int(p.g)), abs(Int(c.b) - Int(p.b)))
            if d >= 6 || (c == .off && p != .off) {
                do { try device.setZone(z, c); sent.zones[z] = c }
                catch DeviceError.suspended { break }    // 차단기 열림: 남은 존도 보내지 않음
                catch { FileHandle.standardError.write("setZone \(z): \(error)\n".data(using: .utf8)!) }
            }
        }
        lock.withLock { _lastFrame = f }
    }

    private func blackout() { queue.async { self.push(.off) } }
}
