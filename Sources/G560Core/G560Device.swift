import Foundation
import IOKit.hid

public enum DeviceError: Error {
    case notConnected, timeout, suspended, hidpp(HIDPPError), unknownFeature(UInt16), ioFailed(Int32)
}

/// G560 HID 인터페이스(HID++ 컬렉션 usage page 0xFF43 포함)를 비독점으로 열고, 동기 요청/응답을 직렬화한다.
/// 리포트 수신은 전용 스레드의 RunLoop에서, 호출자는 세마포어로 대기한다.
/// 주의: HID 스레드(콜백) 안에서 call()이나 callLock을 잡으면 데드락 — attach()는 그래서 global queue로 넘긴다.
public final class G560Device: @unchecked Sendable {
    public var onConnect: (@Sendable () -> Void)?
    public var onDisconnect: (@Sendable () -> Void)?
    public var isConnected: Bool { stateLock.withLock { connected } }
    /// 재연결이 반복되는 중(FlapGuard) — 비휘발·프로필 쓰기와 LED 스트리밍을 보류해야 한다.
    public var isHeld: Bool { stateLock.withLock { flap.isFlapping(at: Date()) } }

    static let vendorID = 0x046D, productID = 0x0A78, hidppUsagePage = 0xFF43
    static let knownFeatures: [UInt16] = [0x8070, 0x8305, 0x8310, 0x8040]
    static let settleDelay: TimeInterval = 2   // ponytail: 실측값 아님, 재연결 직후 불안정이 보이면 늘릴 것

    /// 명령 사이 최소 간격. 연속 전송은 USB 파이프 stall(0xE0005000)을 일으킨다 — 연결 직후 LED 4존 + 프로필 읽기/쓰기가 몰릴 때 실측.
    /// ponytail: 실측값 아님. 시작 직후 stall이 남으면 늘리고, 사운드 반응이 굼뜨면 줄일 것. 비휘발 쓰기는 펌웨어가 굽는 동안 쉬게 더 길게.
    static let minGap: TimeInterval = 0.04, nvGap: TimeInterval = 0.3
    /// LED 프레임(setZone) 뒤 간격. minGap(40ms)이면 4존 프레임이 ≥160ms(~6Hz). ponytail: 실측값 — 15ms는 60초 stall 0회에 실효 10.4Hz, 10ms는 13.6Hz에 stall 0회였으나 보수적으로 15ms. stall(0xE0005000)이 보이면 올릴 것
    static let ledGap: TimeInterval = 0.015
    static func gap(afterFeature f: UInt16, fn: UInt8) -> TimeInterval {
        if f == 0x8070 && fn == 3 { return ledGap }
        return [(0x8305, 1), (0x8310, 3), (0x8040, 2)].contains { $0.0 == Int(f) && $0.1 == Int(fn) } ? nvGap : minGap
    }
    /// 차단기 쿨다운 — 호출자가 suspended 뒤 한 번 기다렸다 재시도할 때 쓴다.
    public static var breakerCooldown: TimeInterval { Breaker.cooldown }

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)   // IOKit이 계속 쓰는 버퍼라 주소가 고정돼야 함
    private let callLock = NSLock()      // call() 한 번에 하나. breaker, nextSwID 보호
    private let stateLock = NSLock()     // pending, device, featureIndex, connected 보호 (짧게만 잡는다)
    private var pending: (feature: UInt8, fn: UInt8, sw: UInt8, sema: DispatchSemaphore, reply: HIDPPReply?)?
    private var device: IOHIDDevice?
    private var featureIndex: [UInt16: UInt8] = [0x0000: 0]
    private var connected = false
    private var breaker = Breaker()
    private var flap = FlapGuard()       // stateLock 보호
    private var nextSwID: UInt8 = 1
    private var nextAllowed = Date.distantPast   // callLock 보호: 이 시각 전엔 다음 명령을 보내지 않는다
    private var nextAllowedNonLED = Date.distantPast   // callLock 보호: LED 프레임이 아닌 명령용 (LED 직후에도 minGap 이상 쉰다)
    private var thread: Thread?

    public init() {}

    /// 이 맥에서 G560에 명령을 보내는 프로세스는 하나만 (개발 빌드·설치본·g560ctl 동시 실행 방지).
    /// 락은 프로세스가 끝나거나 죽으면 OS가 풀어준다.
    static var lockPath: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("G560Studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device.lock").path
    }

    /// 성공하면 열린 fd (프로세스가 살아있는 동안 들고 있음), 다른 프로세스가 쥐고 있으면 nil.
    static func acquireLock(at path: String) -> Int32? {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        return fd
    }

    /// 장치 감시 시작. 다른 G560Studio/g560ctl이 이미 장치를 쓰고 있으면 아무것도 하지 않고 false.
    @discardableResult
    public func start() -> Bool {
        guard Self.acquireLock(at: Self.lockPath) != nil else {
            samplerLog("start refused: another process holds the device lock")
            return false
        }
        let match: [String: Any] = [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().attach(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().detach(dev)
        }, ctx)
        let t = Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        t.name = "G560 HID"
        t.start()
        thread = t
        return true
    }

    /// 같은 VID/PID로 HID 장치가 여러 개 잡힐 수 있다. HID++ 컬렉션(0xFF43)이 있는 것만 쓴다 —
    /// 다른 인터페이스에 HID++ 리포트를 보내거나, 인터페이스마다 attach가 겹쳐 돌지 않도록.
    static func hasHIDPP(_ dev: IOHIDDevice) -> Bool {
        if let pairs = IOHIDDeviceGetProperty(dev, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] {
            return pairs.contains { ($0[kIOHIDDeviceUsagePageKey] as? Int) == hidppUsagePage }
        }
        return (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) == hidppUsagePage
    }

    /// 보낼 수 있는 (기능, fn) 조합. 문서화·재전송 검증된 것만 — 그 밖의 fn은 어떤 기능에도 보내지 않는다.
    static let allowedFns: [UInt16: Set<UInt8>] = [0x0000: [0], 0x8070: [3], 0x8305: [0, 1], 0x8310: [2, 3], 0x8040: [1, 2]]

    /// 기능 id → 보낼 인덱스. 허용된 (기능, fn)이고, 인덱스가 그 기능만의 것일 때만 돌려준다
    /// (표가 뒤섞여 LED fn3가 EQ 인덱스로, EQ set이 엉뚱한 인덱스로 나가는 사고 방지).
    static func resolve(_ map: [UInt16: UInt8], feature: UInt16, fn: UInt8) -> UInt8? {
        guard allowedFns[feature]?.contains(fn) == true, let idx = map[feature] else { return nil }
        guard (idx == 0) == (feature == 0), map.values.filter({ $0 == idx }).count == 1 else { return nil }
        return idx
    }

    /// 기능 인덱스 표가 말이 되는가: 필요한 기능이 다 있고 인덱스가 서로 달라야 한다 (중복 = 응답이 뒤섞였다는 뜻).
    static func plausible(_ map: [UInt16: UInt8]) -> Bool {
        let ids = knownFeatures.compactMap { map[$0] }
        return ids.count == knownFeatures.count && Set(ids).count == ids.count && !ids.contains(0)
    }

    private func attach(_ dev: IOHIDDevice) {
        guard Self.hasHIDPP(dev) else { return }
        let claimed: Bool = stateLock.withLock {
            guard device == nil else { return false }   // 이미 붙은 장치가 있으면 무시
            device = dev; flap.record(at: Date()); return true
        }
        guard claimed else { return }
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, report, len in
            let bytes = Array(UnsafeBufferPointer(start: report, count: len))
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().received(bytes)
        }, Unmanaged.passUnretained(self).toOpaque())
        DispatchQueue.global().async { [self] in
            callLock.withLock { breaker = Breaker() }
            // 기능 인덱스 조회: IRoot.getFeature(id). 재시도 간격은 차단기 쿨다운만큼 — 부팅 중인 장치를 몰아치지 않는다.
            var ok = false
            for attempt in 0..<3 {
                if attempt > 0 { Thread.sleep(forTimeInterval: Breaker.cooldown) }
                var got: [UInt16: UInt8] = [0x0000: 0]
                for id in Self.knownFeatures {
                    if let r = try? call(feature: 0x0000, fn: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]), r.params[0] != 0 {
                        got[id] = r.params[0]
                    }
                }
                if Self.plausible(got) {
                    stateLock.withLock { featureIndex = got }; ok = true; break
                }
                samplerLog("feature lookup attempt \(attempt + 1) implausible: \(got)")
            }
            guard ok else {
                samplerLog("attach failed: feature lookup")
                stateLock.withLock { if device == dev { device = nil } }
                return
            }
            // 방금 부팅한 장치에 곧바로 비휘발 쓰기·LED 스트림을 쏟지 않도록 잠깐 기다린다.
            Thread.sleep(forTimeInterval: Self.settleDelay)
            let still = stateLock.withLock { () -> Bool in
                guard device == dev else { return false }   // 그 사이 분리됨
                connected = true; return true
            }
            guard still else { return }
            samplerLog("attach ok")
            onConnect?()
            if isHeld {   // 보류는 시간이 지나 attach 기록이 창 밖으로 나가면 풀린다 — 그때 onConnect로 프로필을 한 번 적용
                samplerLog("reconnect flapping: holding profile/NV writes and LED streaming")
                DispatchQueue.global().asyncAfter(deadline: .now() + FlapGuard.window + 1) { [self] in
                    if isConnected, !isHeld { samplerLog("flap hold released"); onConnect?() }
                }
            }
        }
    }

    private func detach(_ dev: IOHIDDevice) {
        let mine = stateLock.withLock { () -> Bool in
            guard device == dev else { return false }
            device = nil; connected = false; featureIndex = [0x0000: 0]
            return true
        }
        guard mine else { return }
        samplerLog("detach")
        onDisconnect?()
    }

    private func received(_ bytes: [UInt8]) {
        guard let r = HIDPP.parse(bytes) else { return }
        stateLock.lock(); defer { stateLock.unlock() }
        guard var p = pending, HIDPP.matches(r, feature: p.feature, fn: p.fn, swID: p.sw) else { return }
        p.reply = r; pending = p; p.sema.signal()
    }

    private func write(_ report: [UInt8]) throws {
        guard let dev = stateLock.withLock({ device }) else { throw DeviceError.notConnected }
        let res = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(HIDPP.reportID), $0.baseAddress!, $0.count)
        }
        guard res == kIOReturnSuccess else { throw DeviceError.ioFailed(res) }
    }

    /// 전송 후 같은 요청의 응답(swID까지 일치)을 200ms 대기.
    /// 모든 장치 명령이 지나는 곳이라 차단기도 여기 하나: 연속 무응답이면 쿨다운 동안 아무것도 보내지 않고,
    /// 쿨다운 뒤엔 읽기 전용 ping이 성공해야 다시 쓴다. 멈춘 펌웨어에 쓰기(특히 EEPROM)를 계속 보내지 않기 위함.
    public func call(feature: UInt16, fn: UInt8, params: [UInt8]) throws -> HIDPPReply {
        guard let idx = stateLock.withLock({ Self.resolve(featureIndex, feature: feature, fn: fn) }) else { throw DeviceError.unknownFeature(feature) }
        callLock.lock(); defer { callLock.unlock() }
        let isLED = feature == 0x8070 && fn == 3
        let wait = (isLED ? nextAllowed : nextAllowedNonLED).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        defer {   // 실패·ping 포함 모든 경로 뒤에
            let g = Self.gap(afterFeature: feature, fn: fn), now = Date()
            nextAllowed = now.addingTimeInterval(g); nextAllowedNonLED = now.addingTimeInterval(max(g, Self.minGap))
        }
        if breaker.needsProbe {
            guard !breaker.isOpen(at: Date()) else { throw DeviceError.suspended }
            do { _ = try transact(0, fn: 1, params: [0, 0, 0x5A]) }   // IRoot.ping (읽기 전용)
            catch { breaker.record(false, at: Date()); throw DeviceError.suspended }
            breaker.record(true, at: Date())
            samplerLog("HID++ breaker closed: ping ok")
        }
        do {
            let r = try transact(idx, fn: fn, params: params)
            breaker.record(true, at: Date())
            return r
        } catch DeviceError.hidpp(let e) {
            // INVALID_ARGUMENT 같은 결정적 거부는 장치가 멀쩡히 답한 것. BUSY/HW_ERROR/UNKNOWN 등은 장애 신호라 차단기에 센다.
            if Breaker.countsAsFailure(e) {
                if breaker.record(false, at: Date()) { samplerLog("HID++ breaker open: \(e.name) feature \(String(feature, radix: 16)) fn \(fn)") }
            } else { breaker.record(true, at: Date()) }
            throw DeviceError.hidpp(e)
        } catch {
            if breaker.record(false, at: Date()) { samplerLog("HID++ breaker open: \(error) feature \(String(feature, radix: 16)) fn \(fn)") }
            throw error
        }
    }

    /// callLock 안에서만 호출. 요청마다 swID를 1…11로 돌려서 늦게 온 이전 응답과 구분한다
    /// (0은 장치 알림, 0xC는 G HUB가 쓰므로 피함).
    private func transact(_ idx: UInt8, fn: UInt8, params: [UInt8]) throws -> HIDPPReply {
        let sw = nextSwID
        nextSwID = nextSwID >= 0xB ? 1 : nextSwID + 1
        let sema = DispatchSemaphore(value: 0)
        stateLock.withLock { pending = (idx, fn, sw, sema, nil) }
        defer { stateLock.withLock { pending = nil } }
        try write(HIDPP.build(featureIndex: idx, fn: fn, params: params, swID: sw))
        guard sema.wait(timeout: .now() + .milliseconds(200)) == .success else { throw DeviceError.timeout }
        guard let r = stateLock.withLock({ pending?.reply }) else { throw DeviceError.timeout }
        if let e = r.error { throw DeviceError.hidpp(e) }
        return r
    }
}

/// 연속 무응답 차단기. 2026-09-13 장치가 멈춘 뒤에도 LED/EEPROM 쓰기를 계속 보낸 사고 대응.
struct Breaker {
    static let threshold = 2
    static let cooldown: TimeInterval = 5
    private(set) var failures = 0
    private var openUntil = Date.distantPast

    var needsProbe: Bool { failures >= Self.threshold }
    func isOpen(at now: Date) -> Bool { needsProbe && now < openUntil }

    /// 에러 응답이 차단기에 장애로 세어지는가. 인자·범위·기능/함수 번호·미지원 거부(2,3,6,7,9)는 결정적이라 장치 상태와 무관.
    static func countsAsFailure(_ e: HIDPPError) -> Bool { ![2, 3, 6, 7, 9].contains(e.code) }

    /// 결과 기록. 방금 열렸으면 true (로그 1회용).
    @discardableResult
    mutating func record(_ ok: Bool, at now: Date) -> Bool {
        if ok { failures = 0; return false }
        failures += 1
        guard needsProbe else { return false }
        openUntil = now.addingTimeInterval(Self.cooldown)
        return failures == Self.threshold
    }
}

/// 재연결 반복 감지. 창(60초) 안에 attach가 limit(3)번 이상이면 flapping — 장치가 불안정하니 쓰기를 보류한다.
/// ponytail: 고정 임계값. 오탐(정상 재연결 3번)은 최대 60초 보류로 끝나므로 감수. 실측으로 조정.
struct FlapGuard {
    static let limit = 3
    static let window: TimeInterval = 60
    private var times: [Date] = []

    mutating func record(at now: Date) { times = times.filter { now.timeIntervalSince($0) < Self.window } + [now] }
    func isFlapping(at now: Date) -> Bool { times.filter { now.timeIntervalSince($0) < Self.window }.count >= Self.limit }
}
