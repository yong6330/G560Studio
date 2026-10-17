import Foundation

/// 30Hz로 현재 config의 프레임을 계산(화면 표시용)하고, 그 최신 프레임을 별도 큐에서 (실효 ~10Hz) 바뀐 존만 장치에 쓴다.
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
    private var pending: [AudioLevels] = []   // 마지막 프레임 이후 도착한 버퍼 레벨들. 최신 하나만 읽으면 버퍼 간 요동이 그대로 깜빡임이 되므로 프레임마다 평균
    private var state = LightingState()
    private var timer: DispatchSourceTimer?
    private var pusher: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "lighting")
    private let pushQueue = DispatchQueue(label: "lighting.push")   // 장치 쓰기는 수십~100ms 막히므로 표시 계산과 분리. sent는 이 큐에서만 만진다
    private let t0 = Date()

    public init(device: G560Device) { self.device = device }

    public func update(audio: AudioLevels) { queue.async { self.pending.append(audio) } }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))   // 30Hz 표시용 (장치 부하 없음)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
        // ponytail: 66ms 타이머지만 4존 × (LED 간격 15ms + 왕복) ≈ 96ms라 실효 ~10Hz (실측 10.4). 막히면 쌓이지 않고 합쳐진다. stall이 보이면 ledGap을 올릴 것
        let p = DispatchSource.makeTimerSource(queue: pushQueue)
        p.schedule(deadline: .now(), repeating: .milliseconds(66))
        p.setEventHandler { [weak self] in self?.pushLatest() }
        p.resume()
        pusher = p
    }

    public func stop() { timer?.cancel(); timer = nil; pusher?.cancel(); pusher = nil }

    /// 재연결·프로필 교체 시 전 존 강제 재전송
    public func resend() {
        pushQueue.async {
            guard self.enabled, self.device.isConnected, !self.device.isHeld else { return }
            self.sent = ZoneColors(all: RGB(1, 1, 1))
            self.push(self.lastFrame)
        }
    }

    /// 표시용 프레임 계산. 장치 상태와 무관 (연결이 없어도 미리보기는 움직인다).
    private func tick() {
        if !pending.isEmpty {
            let n = Float(pending.count)
            func m(_ k: KeyPath<AudioLevels, Float>) -> Float { pending.reduce(0) { $0 + $1[keyPath: k] } / n }
            audio = AudioLevels(rms: m(\.rms), peak: m(\.peak), low: m(\.low), mid: m(\.mid), high: m(\.high))
            pending.removeAll(keepingCapacity: true)
        }
        guard enabled else { return }
        let frame = config.frame(t: Date().timeIntervalSince(t0), audio: audio, state: &state, screen: screen.colors)
        let k = Float(max(0, min(100, brightness))) / 100
        let f = k >= 1 ? frame : ZoneColors(zones: frame.zones.map { $0.scaled(k) })
        lock.withLock { _lastFrame = f }
    }

    private func pushLatest() {
        guard enabled, device.isConnected, !device.isHeld else { return }   // isHeld: 재연결 반복 중엔 스트리밍 보류
        push(lastFrame)
    }

    /// 화면 샘플러 모드일 때만 캡처 (권한 팝업도 그때만)
    private func syncScreen() {
        if case .screenSampler(let o) = config {
            screen.inset = Float(o.inset); screen.boost = Float(o.boost); screen.displayID = o.display; screen.start()
        } else { screen.stop() }
    }

    private func push(_ f: ZoneColors) {
        for z in 0..<G560.zoneCount {
            let c = f.zones[z], p = sent.zones[z]
            // 채널당 6 미만 변화는 눈에 안 띄므로 전송 생략 → 느린 페이드에서 USB 왕복 대폭 감소
            let d = max(abs(Int(c.r) - Int(p.r)), abs(Int(c.g) - Int(p.g)), abs(Int(c.b) - Int(p.b)))
            if d >= 6 || (c == .off && p != .off) {
                do { try device.setZone(z, c); sent.zones[z] = c }
                catch {   // stall·타임아웃·차단기 열림: 이 프레임은 버리고 남은 존도 보내지 않는다 (sent는 그대로라 다음 틱이 다시 시도). UI엔 올리지 않음
                    if case DeviceError.suspended = error {} else { samplerLog("setZone \(z) skipped: \(error)") }
                    break
                }
            }
        }
    }

    private func blackout() { queue.async { self.lock.withLock { self._lastFrame = .off }; self.pushQueue.async { self.push(.off) } } }
}
