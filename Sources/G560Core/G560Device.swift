import Foundation
import IOKit.hid

public enum DeviceError: Error {
    case notConnected, timeout, hidpp(HIDPPError), unknownFeature(UInt16), ioFailed(Int32)
}

/// G560 HID 인터페이스(HID++ 컬렉션 usage page 0xFF43 포함)를 비독점으로 열고, 동기 요청/응답을 직렬화한다.
/// 리포트 수신은 전용 스레드의 RunLoop에서, 호출자는 세마포어로 대기한다.
/// 주의: HID 스레드(콜백) 안에서 call()을 부르면 데드락 — attach()는 그래서 global queue로 넘긴다.
public final class G560Device: @unchecked Sendable {
    public var onConnect: (@Sendable () -> Void)?
    public var onDisconnect: (@Sendable () -> Void)?
    public private(set) var isConnected = false

    static let vendorID = 0x046D, productID = 0x0A78
    static let knownFeatures: [UInt16] = [0x8070, 0x8305, 0x8310]

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private let callLock = NSLock()      // call() 한 번에 하나
    private let stateLock = NSLock()     // pending 보호
    private var pending: (feature: UInt8, fn: UInt8, sema: DispatchSemaphore, reply: HIDPPReply?)?
    private var featureIndex: [UInt16: UInt8] = [0x0000: 0]
    private var thread: Thread?

    public init() {}

    public func start() {
        // macOS는 USB 인터페이스당 IOHIDDevice 하나. 0xFF43 HID++ 컬렉션은 그 안에 있으므로 VID/PID로만 매칭.
        let match: [String: Any] = [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().attach(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().detach()
        }, ctx)
        let t = Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        t.name = "G560 HID"
        t.start()
        thread = t
    }

    private func attach(_ dev: IOHIDDevice) {
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(dev, buf.baseAddress!, buf.count, { ctx, _, _, _, _, report, len in
                let bytes = Array(UnsafeBufferPointer(start: report, count: len))
                Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().received(bytes)
            }, ctx)
        }
        isConnected = true
        DispatchQueue.global().async { [self] in
            // 기능 인덱스 조회: IRoot.getFeature(id) — 검증된 읽기. 펌웨어마다 인덱스가 다를 수 있어 하드코딩 안 함.
            for id in Self.knownFeatures {
                if let r = try? call(feature: 0x0000, fn: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]), r.params[0] != 0 {
                    featureIndex[id] = r.params[0]
                }
            }
            onConnect?()
        }
    }

    private func detach() {
        device = nil
        isConnected = false
        featureIndex = [0x0000: 0]
        onDisconnect?()
    }

    private func received(_ bytes: [UInt8]) {
        guard let r = HIDPP.parse(bytes) else { return }
        stateLock.lock(); defer { stateLock.unlock() }
        guard var p = pending else { return }
        let matches = (r.featureIndex == p.feature && r.fn == p.fn && r.swID == HIDPP.swID)
            || (r.error != nil && r.error!.origFeature == p.feature)
        if matches { p.reply = r; pending = p; p.sema.signal() }
    }

    private func write(_ report: [UInt8]) throws {
        guard let dev = device else { throw DeviceError.notConnected }
        let res = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(HIDPP.reportID), $0.baseAddress!, $0.count)
        }
        guard res == kIOReturnSuccess else { throw DeviceError.ioFailed(res) }
    }

    private func index(of feature: UInt16) throws -> UInt8 {
        guard let i = featureIndex[feature] else { throw DeviceError.unknownFeature(feature) }
        return i
    }

    /// 응답을 기다리지 않는 전송 (LED 프레임용).
    public func send(feature: UInt16, fn: UInt8, params: [UInt8]) throws {
        try write(HIDPP.build(featureIndex: try index(of: feature), fn: fn, params: params))
    }

    /// 전송 후 같은 feature/fn 응답(또는 그 feature의 에러)을 200ms 대기.
    public func call(feature: UInt16, fn: UInt8, params: [UInt8]) throws -> HIDPPReply {
        let idx = try index(of: feature)
        callLock.lock(); defer { callLock.unlock() }
        let sema = DispatchSemaphore(value: 0)
        stateLock.lock(); pending = (idx, fn, sema, nil); stateLock.unlock()
        defer { stateLock.lock(); pending = nil; stateLock.unlock() }
        try write(HIDPP.build(featureIndex: idx, fn: fn, params: params))
        guard sema.wait(timeout: .now() + .milliseconds(200)) == .success else { throw DeviceError.timeout }
        stateLock.lock(); let reply = pending?.reply; stateLock.unlock()
        guard let r = reply else { throw DeviceError.timeout }
        if let e = r.error { throw DeviceError.hidpp(e) }
        return r
    }
}
