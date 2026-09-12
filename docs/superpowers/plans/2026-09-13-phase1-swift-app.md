# Phase 1: G560Studio Swift 앱 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** G HUB 없이 G560의 조명(4존, 사운드 반응 포함)·우퍼·EQ·볼륨을 제어하고 프로필로 저장하는 macOS 메뉴바 앱. 메뉴바 아이콘은 재생 중 오디오 파형을 4존 색으로 실시간 렌더링.

**Architecture:** SwiftPM 패키지 하나. `G560Core`(순수 로직: HID++, 장치, 조명 엔진, 오디오 탭, 프로필) + `G560Studio`(SwiftUI 앱) + `g560ctl`(CLI). 장치 쓰기는 `docs/protocol.md`에서 검증된 3개 명령(LED fn3, 우퍼 fn1, EQ fn3)뿐. 모든 조명 애니메이션은 소프트웨어가 계산해 Fixed 색을 30Hz로 전송.

**Tech Stack:** Swift 6.3, SwiftUI `MenuBarExtra`, IOKit.hid, CoreAudio Process Tap (macOS 14.2+), Accelerate.vDSP. 외부 의존성 0. XCTest.

## Global Constraints

- 스펙 §안전 원칙: 검증되지 않은 HID++ 기능/함수는 절대 호출하지 않는다. 쓰기는 `0x8070 fn3`, `0x8305 fn1`, `0x8310 fn3`만. 읽기는 `0x0000 fn0`, `0x8305 fn0`, `0x8310 fn2`만.
- HID 장치는 **비독점**으로 연다 (`kIOHIDOptionsTypeNone`).
- EQ 쓰기는 EEPROM → 슬라이더를 **놓을 때만** 전송. 드래그 중 전송 금지.
- 장치 상수: VID `0x046D`, PID `0x0A78`, usage page `0xFF43`. 존: 0=좌 앞, 1=우 앞, 2=좌 뒤, 3=우 뒤.
- EQ: 10밴드 32/64/125/250/500/1k/2k/4k/8k/16k Hz, 게인 −20…+6 dB 정수.
- 우퍼: 0–100 정수.
- 볼륨: CoreAudio `kAudioDevicePropertyVolumeScalar` (HID++ 아님).
- 색 UI에는 항상 색 이름/hex 텍스트를 함께 표시 (사용자 색약).
- 빌드: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 후 `swift build/test`. 모든 Run 명령은 이 환경변수를 앞에 붙인다.
- macOS 배포 타깃 14.2. 개인용, ad-hoc 서명.
- 파일당 하나의 책임. 프레임워크 추가 없음.

---

## File Structure

```
Package.swift
Sources/G560Core/
  HIDPP.swift            패킷 조립/파싱 (Python hidpp.py 포팅)
  G560Device.swift       IOHIDManager: 열기/핫플러그/송수신/기능 인덱스
  G560Commands.swift     setZone / woofer get·set / eq get·set  (검증된 것만)
  AudioLevels.swift      struct AudioLevels + 버퍼→레벨 계산 (순수 함수)
  AudioTap.swift         Process Tap → AudioLevels 스트림
  Lighting.swift         RGB, ZoneColors, LightingConfig(enum), frame 계산 (순수)
  LightingEngine.swift   30Hz 타이머, 변경 시에만 전송
  OutputVolume.swift     CoreAudio 볼륨 get/set
  Profile.swift          Profile + ProfileStore (JSON)
Sources/G560Studio/
  App.swift              @main, MenuBarExtra + Settings 씬
  AppState.swift         @Observable: 장치·오디오·엔진·프로필 묶음, 프로필 적용
  MenuBarIcon.swift      NSImage 렌더러 (컬러 파형)
  QuickPanel.swift       메뉴바 패널
  SettingsView.swift     탭 3개 컨테이너
  LightingTab.swift
  OutputTab.swift
  ProfilesTab.swift
  Info.plist             LSUIElement, NSAudioCaptureUsageDescription
Sources/g560ctl/main.swift
Tests/G560CoreTests/
  HIDPPTests.swift  LightingTests.swift  AudioLevelsTests.swift  ProfileTests.swift
scripts/bundle.sh        .app 번들 생성 + ad-hoc 서명
```

---

### Task 1: SwiftPM 스켈레톤 + 번들 스크립트

**Files:**
- Create: `Package.swift`, `Sources/G560Core/Placeholder.swift`(Task 2에서 삭제), `Sources/G560Studio/App.swift`, `Sources/G560Studio/Info.plist`, `Sources/g560ctl/main.swift`, `Tests/G560CoreTests/SmokeTests.swift`, `scripts/bundle.sh`

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "G560Studio",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "G560Core", linkerSettings: [
            .linkedFramework("IOKit"), .linkedFramework("CoreAudio"), .linkedFramework("Accelerate"),
        ]),
        .executableTarget(name: "G560Studio", dependencies: ["G560Core"],
                          exclude: ["Info.plist"]),
        .executableTarget(name: "g560ctl", dependencies: ["G560Core"]),
        .testTarget(name: "G560CoreTests", dependencies: ["G560Core"]),
    ]
)
```

- [ ] **Step 2: 최소 소스**

`Sources/G560Core/Placeholder.swift`:
```swift
public enum G560Core { public static let version = "0.1.0" }
```
`Sources/G560Studio/App.swift`:
```swift
import SwiftUI

@main
struct G560StudioApp: App {
    var body: some Scene {
        MenuBarExtra("G560", systemImage: "hifispeaker") {
            Text("G560Studio").padding()
        }.menuBarExtraStyle(.window)
    }
}
```
`Sources/g560ctl/main.swift`:
```swift
import G560Core
print("g560ctl", G560Core.version)
```
`Tests/G560CoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import G560Core
final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(G560Core.version, "0.1.0") }
}
```
`Sources/G560Studio/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.onestudio.G560Studio</string>
  <key>CFBundleName</key><string>G560Studio</string>
  <key>CFBundleExecutable</key><string>G560Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>재생 중인 소리에 맞춰 G560 조명과 메뉴바 아이콘을 움직이기 위해 시스템 오디오를 읽습니다. 녹음하거나 저장하지 않습니다.</string>
</dict></plist>
```

- [ ] **Step 3: bundle.sh**

`scripts/bundle.sh`:
```bash
#!/bin/bash
# G560Studio.app 번들 생성 (개인용, ad-hoc 서명). 사용: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
CFG=${1:-debug}
swift build -c "$CFG" --product G560Studio
APP=build/G560Studio.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CFG/G560Studio" "$APP/Contents/MacOS/"
cp Sources/G560Studio/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "built $APP"
```
`.gitignore`에 `build/` 추가.

- [ ] **Step 4: 빌드·테스트·번들 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift build && swift test 2>&1 | tail -3 && chmod +x scripts/bundle.sh && scripts/bundle.sh && open build/G560Studio.app
```
Expected: 테스트 1개 통과, 메뉴바에 스피커 아이콘, 클릭 시 "G560Studio" 팝업. 확인 후 `pkill G560Studio`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests scripts .gitignore && git commit -m "Scaffold SwiftPM app, CLI, tests, bundle script"
```

---

### Task 2: HIDPP 패킷 (순수)

**Files:**
- Create: `Sources/G560Core/HIDPP.swift`, `Tests/G560CoreTests/HIDPPTests.swift`
- Delete: `Sources/G560Core/Placeholder.swift`, `Tests/G560CoreTests/SmokeTests.swift`

**Interfaces:**
- Produces:
  - `public enum HIDPP { static let reportID: UInt8 = 0x11; static let length = 20; static let swID: UInt8 = 0x0A }`
  - `public struct HIDPPReply { featureIndex: UInt8; fn: UInt8; swID: UInt8; params: [UInt8] /*16*/; error: HIDPPError? }`
  - `public struct HIDPPError: Error { origFeature: UInt8; origFnSw: UInt8; code: UInt8; var name: String }`
  - `public static func build(featureIndex: UInt8, fn: UInt8, params: [UInt8]) -> [UInt8]` (20바이트)
  - `public static func parse(_ report: [UInt8]) -> HIDPPReply?` (길이/ID 틀리면 nil)

- [ ] **Step 1: 실패하는 테스트** — `docs/protocol.md` 실측 바이트 사용

```swift
import XCTest
@testable import G560Core

final class HIDPPTests: XCTestCase {
    func hex(_ s: String) -> [UInt8] { stride(from: 0, to: s.count, by: 2).map { i in
        UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i+2)], radix: 16)! } }

    func testBuildLEDZone0Red() {   // 검증된 패킷
        XCTAssertEqual(HIDPP.build(featureIndex: 4, fn: 3, params: [0,1,0xff,0,0,2]),
                       hex("11ff043a0001ff00000200000000000000000000"))
    }
    func testBuildWoofer50() {
        XCTAssertEqual(HIDPP.build(featureIndex: 9, fn: 1, params: [50]),
                       hex("11ff091a32000000000000000000000000000000"))
    }
    func testParseWooferGet() {
        let r = HIDPP.parse(hex("11ff090a28000000000000000000000000000000"))!
        XCTAssertEqual(r.featureIndex, 9); XCTAssertEqual(r.fn, 0); XCTAssertEqual(r.swID, 0xA)
        XCTAssertEqual(r.params[0], 40); XCTAssertNil(r.error)
    }
    func testParseError() {          // EQ set with 0x00 prefix → INVALID_ARGUMENT (실측)
        let r = HIDPP.parse(hex("11ffff063a020000000000000000000000000000"))!
        XCTAssertEqual(r.error?.code, 2); XCTAssertEqual(r.error?.name, "INVALID_ARGUMENT")
        XCTAssertEqual(r.error?.origFeature, 6)
    }
    func testParseRejectsWrongLength() { XCTAssertNil(HIDPP.parse([0x11, 0xff])) }
}
```

- [ ] **Step 2: 실패 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift test 2>&1 | grep -E "error:|Executed" | head -3
```
Expected: `cannot find 'HIDPP'` 컴파일 에러.

- [ ] **Step 3: 구현**

```swift
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
```
Placeholder.swift / SmokeTests.swift 삭제. `g560ctl/main.swift`의 `G560Core.version` 줄은 `print("g560ctl")`로.

- [ ] **Step 4: 통과 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift test 2>&1 | grep Executed
```
Expected: `Executed 5 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add -A Sources Tests && git commit -m "Add HIDPP packet build/parse with captured-byte tests"
```

---

### Task 3: G560Device — IOHIDManager 송수신 + 핫플러그

**Files:**
- Create: `Sources/G560Core/G560Device.swift`

**Interfaces:**
- Consumes: `HIDPP.build/parse`
- Produces:
  ```swift
  public final class G560Device: @unchecked Sendable {
      public init()
      public var onConnect: (@Sendable () -> Void)?        // 기능 인덱스 조회 완료 후 호출
      public var onDisconnect: (@Sendable () -> Void)?
      public var isConnected: Bool { get }
      public func start()                                   // 매칭 시작 (이미 꽂혀 있으면 즉시 onConnect)
      public func call(feature: UInt16, fn: UInt8, params: [UInt8]) throws -> HIDPPReply  // 응답 대기, 200ms
      public func send(feature: UInt16, fn: UInt8, params: [UInt8]) throws               // 응답 안 기다림 (LED용)
  }
  public enum DeviceError: Error { case notConnected, timeout, hidpp(HIDPPError), unknownFeature(UInt16), ioFailed(Int32) }
  ```
  `feature`는 ID(0x8070 등). 인덱스 변환은 내부에서 (연결 시 IRoot.getFeature로 조회해 캐시).

- [ ] **Step 1: 구현**

```swift
import Foundation
import IOKit.hid

public enum DeviceError: Error { case notConnected, timeout, hidpp(HIDPPError), unknownFeature(UInt16), ioFailed(Int32) }

/// G560 HID++ 인터페이스 하나를 비독점으로 열고, 동기 요청/응답을 직렬화한다.
/// 리포트 수신은 전용 스레드의 RunLoop에서, 호출자는 세마포어로 대기한다.
public final class G560Device: @unchecked Sendable {
    public var onConnect: (@Sendable () -> Void)?
    public var onDisconnect: (@Sendable () -> Void)?
    public private(set) var isConnected = false

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private let lock = NSLock()                    // call() 직렬화
    private var pending: (feature: UInt8, fn: UInt8, sema: DispatchSemaphore, reply: HIDPPReply?)?
    private var featureIndex: [UInt16: UInt8] = [0x0000: 0]
    private var thread: Thread?

    public init() {}

    public func start() {
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x046D, kIOHIDProductIDKey: 0x0A78,
                                    kIOHIDPrimaryUsagePageKey: 0xFF43]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().attach(dev) }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().detach() }, ctx)
        let t = Thread { [manager] in
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        t.name = "G560 HID"; t.start(); thread = t
    }

    private func attach(_ dev: IOHIDDevice) {
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(dev, buf.baseAddress!, buf.count, { ctx, _, _, _, _, report, len in
                let bytes = Array(UnsafeBufferPointer(start: report, count: len))
                Unmanaged<G560Device>.fromOpaque(ctx!).takeUnretainedValue().received(bytes) }, ctx)
        }
        isConnected = true
        // 기능 인덱스 조회 (IRoot.getFeature) — 검증된 읽기
        for id: UInt16 in [0x8070, 0x8305, 0x8310] {
            if let r = try? call(feature: 0x0000, fn: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]), r.params[0] != 0 {
                featureIndex[id] = r.params[0]
            }
        }
        onConnect?()
    }

    private func detach() {
        device = nil; isConnected = false
        featureIndex = [0x0000: 0]
        onDisconnect?()
    }

    private func received(_ bytes: [UInt8]) {
        guard let r = HIDPP.parse(bytes) else { return }
        lock.lock(); defer { lock.unlock() }
        guard var p = pending else { return }
        let matches = (r.featureIndex == p.feature && r.fn == p.fn && r.swID == HIDPP.swID)
                   || (r.error != nil && r.error!.origFeature == p.feature)
        if matches { p.reply = r; pending = p; p.sema.signal() }
    }

    private func write(_ report: [UInt8]) throws {
        guard let dev = device else { throw DeviceError.notConnected }
        let res = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(HIDPP.reportID), $0.baseAddress!, $0.count) }
        guard res == kIOReturnSuccess else { throw DeviceError.ioFailed(res) }
    }

    private func index(of feature: UInt16) throws -> UInt8 {
        guard let i = featureIndex[feature] else { throw DeviceError.unknownFeature(feature) }
        return i
    }

    public func send(feature: UInt16, fn: UInt8, params: [UInt8]) throws {
        try write(HIDPP.build(featureIndex: try index(of: feature), fn: fn, params: params))
    }

    public func call(feature: UInt16, fn: UInt8, params: [UInt8]) throws -> HIDPPReply {
        let idx = try index(of: feature)
        let sema = DispatchSemaphore(value: 0)
        lock.lock(); pending = (idx, fn, sema, nil); lock.unlock()
        defer { lock.lock(); pending = nil; lock.unlock() }
        try write(HIDPP.build(featureIndex: idx, fn: fn, params: params))
        guard sema.wait(timeout: .now() + .milliseconds(200)) == .success else { throw DeviceError.timeout }
        lock.lock(); let reply = pending?.reply; lock.unlock()
        guard let r = reply else { throw DeviceError.timeout }
        if let e = r.error { throw DeviceError.hidpp(e) }
        return r
    }
}
```
주의: `call()`은 HID 스레드에서 호출하면 데드락 (콜백이 같은 스레드). `attach()`는 HID 스레드에서 실행되므로 그 안의 `call`은 데드락된다 → `attach`의 기능 인덱스 조회와 `onConnect` 호출은 `DispatchQueue.global().async { ... }`로 감싼다. 구현 시 반드시 적용.

- [ ] **Step 2: g560ctl로 실기 확인**

`Sources/g560ctl/main.swift`:
```swift
import Foundation
import G560Core

let dev = G560Device()
let done = DispatchSemaphore(value: 0)
dev.onConnect = {
    do {
        let r = try dev.call(feature: 0x8305, fn: 0, params: [])
        print("woofer =", r.params[0])
    } catch { print("error:", error) }
    done.signal()
}
dev.start()
if done.wait(timeout: .now() + 3) == .timedOut { print("G560 not found") }
```

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift run g560ctl
```
Expected: `woofer = 40`. 뽑았다 꽂아도 다시 잡히는지는 Task 11에서 앱으로 확인.

- [ ] **Step 3: Commit**

```bash
git add Sources && git commit -m "Add G560Device: non-exclusive IOHID open, request/reply, hotplug"
```

---

### Task 4: G560Commands + g560ctl 명령

**Files:**
- Create: `Sources/G560Core/G560Commands.swift`
- Modify: `Sources/g560ctl/main.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct RGB: Codable, Equatable, Sendable { public var r, g, b: UInt8 }
  public extension G560Device {
      func setZone(_ zone: Int, _ c: RGB) throws           // 0x8070 fn3, 응답 안 기다림
      func woofer() throws -> Int                          // 0x8305 fn0
      func setWoofer(_ level: Int) throws                  // 0x8305 fn1, 0...100 clamp
      func equalizer() throws -> [Int]                     // 0x8310 fn2, 10개 signed
      func setEqualizer(_ gains: [Int]) throws             // 0x8310 fn3, [0x02]+10개, -20...6 clamp
  }
  public enum G560 { static let zoneCount = 4; static let eqBands = 10
      static let eqFrequencies = [32,64,125,250,500,1000,2000,4000,8000,16000]
      static let eqRange = -20...6; static let zoneNames = ["좌 앞","우 앞","좌 뒤","우 뒤"] }
  ```

- [ ] **Step 1: 구현**

```swift
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
}

/// docs/protocol.md 에서 재전송 검증된 명령만.
public extension G560Device {
    func setZone(_ zone: Int, _ c: RGB) throws {
        try send(feature: 0x8070, fn: 3, params: [UInt8(zone), 0x01, c.r, c.g, c.b, 0x02])
    }
    func woofer() throws -> Int { Int(try call(feature: 0x8305, fn: 0, params: []).params[0]) }
    func setWoofer(_ level: Int) throws {
        _ = try call(feature: 0x8305, fn: 1, params: [UInt8(level.clamped(to: G560.wooferRange))])
    }
    func equalizer() throws -> [Int] {
        try call(feature: 0x8310, fn: 2, params: []).params.prefix(G560.eqBands).map { Int(Int8(bitPattern: $0)) }
    }
    /// EEPROM 쓰기 — 슬라이더를 놓을 때만 호출할 것.
    func setEqualizer(_ gains: [Int]) throws {
        precondition(gains.count == G560.eqBands)
        let bytes = gains.map { UInt8(bitPattern: Int8($0.clamped(to: G560.eqRange))) }
        _ = try call(feature: 0x8310, fn: 3, params: [0x02] + bytes)
    }
}

extension Comparable { func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) } }
```

- [ ] **Step 2: g560ctl**

```swift
import Foundation
import G560Core

let usage = """
g560ctl status | led <zone|all> <RRGGBB> | woofer <0-100> | eq <g0> ... <g9> | restore
"""
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(1) }

let dev = G560Device()
let done = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
dev.onConnect = {
    do {
        switch cmd {
        case "status":
            print("woofer:", try dev.woofer()); print("eq:", try dev.equalizer())
        case "led":
            let c = UInt32(args[2], radix: 16)!
            let rgb = RGB(UInt8(c >> 16), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF))
            let zones = args[1] == "all" ? Array(0..<G560.zoneCount) : [Int(args[1])!]
            for z in zones { try dev.setZone(z, rgb) }
        case "woofer": try dev.setWoofer(Int(args[1])!); print("woofer:", try dev.woofer())
        case "eq": try dev.setEqualizer(args.dropFirst().map { Int($0)! }); print("eq:", try dev.equalizer())
        case "restore":   // factory-defaults.json 기준 (protocol.md): woofer 40, eq flat. LED는 휘발성.
            try dev.setWoofer(40); try dev.setEqualizer([Int](repeating: 0, count: 10))
            print("restored: woofer", try dev.woofer(), "eq", try dev.equalizer())
        default: print(usage); exitCode = 1
        }
    } catch { print("error:", error); exitCode = 2 }
    done.signal()
}
dev.start()
if done.wait(timeout: .now() + 3) == .timedOut { print("G560 not found"); exitCode = 3 }
exit(exitCode)
```

- [ ] **Step 3: 실기 검증 (Python restore와 교차 확인)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift run g560ctl status && swift run g560ctl led 0 FF0000 && swift run g560ctl woofer 50 && swift run g560ctl eq 3 0 0 0 0 0 0 0 0 0 && swift run g560ctl restore && tools/.venv/bin/python tools/g560probe.py dump /tmp/x.json >/dev/null && tools/.venv/bin/python tools/g560probe.py diff factory-defaults.json /tmp/x.json
```
Expected: 좌 앞 존 빨강 → `woofer: 50` → `eq: [3, 0, …]` → `restored: woofer 40 eq [0…]` → `no differences`.

- [ ] **Step 4: Commit**

```bash
git add Sources && git commit -m "Add verified G560 commands (LED, woofer, EQ) and g560ctl"
```

---

### Task 5: Profile + ProfileStore

**Files:**
- Create: `Sources/G560Core/Lighting.swift` (타입만 먼저), `Sources/G560Core/Profile.swift`, `Tests/G560CoreTests/ProfileTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ZoneColors: Codable, Equatable, Sendable { public var zones: [RGB] /* 4 */ }
  public enum LightingConfig: Codable, Equatable, Sendable {
      case off
      case fixed(ZoneColors)
      case colorCycle(speed: Double)                       // 사이클/초, 기본 0.1
      case breathing(ZoneColors, period: Double)           // 초, 기본 3
      case soundReactive(ZoneColors, sensitivity: Double, splitBands: Bool)   // sens 0.5–4, 기본 1.5
  }
  public struct Profile: Codable, Identifiable, Equatable, Sendable {
      public var id: UUID; public var name: String
      public var lighting: LightingConfig; public var volume: Double /*0–1*/; public var woofer: Int; public var eq: [Int]
      public static func makeDefault(name: String) -> Profile   // 흰색 soundReactive, volume 0.5, woofer 40, eq flat
  }
  public struct ProfileStore { public var profiles: [Profile]; public var activeID: UUID?
      public init(url: URL)  // 없으면 기본 프로필 1개 생성
      public mutating func save() throws; public var active: Profile? }
  ```

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import G560Core

final class ProfileTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }

    func testFreshStoreHasDefaultProfileActive() {
        let s = ProfileStore(url: tmp())
        XCTAssertEqual(s.profiles.count, 1); XCTAssertEqual(s.activeID, s.profiles[0].id)
        XCTAssertEqual(s.active?.woofer, 40); XCTAssertEqual(s.active?.eq, [Int](repeating: 0, count: 10))
    }
    func testRoundTrip() throws {
        let url = tmp()
        var s = ProfileStore(url: url)
        var p = Profile.makeDefault(name: "밤")
        p.woofer = 10; p.lighting = .breathing(ZoneColors(zones: [RGB(1,2,3), .off, .off, RGB(9,9,9)]), period: 4)
        s.profiles.append(p); s.activeID = p.id
        try s.save()
        let t = ProfileStore(url: url)
        XCTAssertEqual(t.profiles, s.profiles); XCTAssertEqual(t.active, p)
    }
    func testCorruptFileFallsBackToDefault() throws {
        let url = tmp(); try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProfileStore(url: url).profiles.count, 1)
    }
}
```

- [ ] **Step 2: 실패 확인** — `swift test 2>&1 | grep -E "error:" | head -2` → `cannot find 'ProfileStore'`

- [ ] **Step 3: 구현**

`Lighting.swift` (타입 부분; frame 계산은 Task 7에서 같은 파일에 추가):
```swift
public struct ZoneColors: Codable, Equatable, Sendable, Hashable {
    public var zones: [RGB]
    public init(zones: [RGB]) { precondition(zones.count == G560.zoneCount); self.zones = zones }
    public init(all c: RGB) { zones = [RGB](repeating: c, count: G560.zoneCount) }
    public static let off = ZoneColors(all: .off)
}

public enum LightingConfig: Codable, Equatable, Sendable, Hashable {
    case off
    case fixed(ZoneColors)
    case colorCycle(speed: Double)
    case breathing(ZoneColors, period: Double)
    case soundReactive(ZoneColors, sensitivity: Double, splitBands: Bool)
}
```
`Profile.swift`:
```swift
import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var lighting: LightingConfig
    public var volume: Double
    public var woofer: Int
    public var eq: [Int]

    public static func makeDefault(name: String) -> Profile {
        Profile(id: UUID(), name: name,
                lighting: .soundReactive(ZoneColors(all: RGB(255, 255, 255)), sensitivity: 1.5, splitBands: false),
                volume: 0.5, woofer: 40, eq: [Int](repeating: 0, count: G560.eqBands))
    }
}

/// profiles.json 하나. 파일이 없거나 깨지면 기본 프로필 1개로 시작.
public struct ProfileStore {
    public var profiles: [Profile]
    public var activeID: UUID?
    let url: URL

    private struct File: Codable { var profiles: [Profile]; var activeID: UUID? }

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("G560Studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    public init(url: URL = ProfileStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: data), !f.profiles.isEmpty {
            profiles = f.profiles; activeID = f.activeID ?? f.profiles[0].id
        } else {
            let p = Profile.makeDefault(name: "기본"); profiles = [p]; activeID = p.id
        }
    }

    public var active: Profile? { profiles.first { $0.id == activeID } }

    public func save() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(profiles: profiles, activeID: activeID)).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: 통과 확인** — `swift test 2>&1 | grep Executed` → `Executed 8 tests, with 0 failures`

- [ ] **Step 5: Commit** — `git add Sources Tests && git commit -m "Add Profile model and JSON ProfileStore"`

---

### Task 6: AudioLevels (순수) + AudioTap

**Files:**
- Create: `Sources/G560Core/AudioLevels.swift`, `Sources/G560Core/AudioTap.swift`, `Tests/G560CoreTests/AudioLevelsTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct AudioLevels: Sendable, Equatable { public var rms, peak, low, mid, high: Float /* 0…1 */; static let silence }
  public enum LevelMeter { public static func measure(_ samples: [Float], sampleRate: Float) -> AudioLevels }
  public final class AudioTap { public init(); public var onLevels: (@Sendable (AudioLevels) -> Void)?
      public func start() throws; public func stop(); public private(set) var isRunning: Bool
      public enum TapError: Error { case createTap(OSStatus), createAggregate(OSStatus), ioProc(OSStatus), noOutputDevice } }
  ```
  `low` = <250Hz, `mid` = 250–2k, `high` = >2k 대역 에너지(각각 0…1 정규화). 3초 무음 감지는 소비자(엔진)가 rms로 판단.

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import G560Core

final class AudioLevelsTests: XCTestCase {
    func sine(_ hz: Float, n: Int = 1024, sr: Float = 48000, amp: Float = 0.5) -> [Float] {
        (0..<n).map { amp * sin(2 * .pi * hz * Float($0) / sr) }
    }
    func testSilence() {
        XCTAssertEqual(LevelMeter.measure([Float](repeating: 0, count: 1024), sampleRate: 48000), .silence)
    }
    func testRMSAndPeakOfSine() {
        let l = LevelMeter.measure(sine(1000), sampleRate: 48000)
        XCTAssertEqual(l.peak, 0.5, accuracy: 0.01); XCTAssertEqual(l.rms, 0.354, accuracy: 0.02)
    }
    func testBassGoesToLow() {
        let l = LevelMeter.measure(sine(60), sampleRate: 48000)
        XCTAssertGreaterThan(l.low, l.mid); XCTAssertGreaterThan(l.low, l.high)
    }
    func testTrebleGoesToHigh() {
        let l = LevelMeter.measure(sine(8000), sampleRate: 48000)
        XCTAssertGreaterThan(l.high, l.low); XCTAssertGreaterThan(l.high, l.mid)
    }
}
```

- [ ] **Step 2: 실패 확인** — `cannot find 'LevelMeter'`

- [ ] **Step 3: LevelMeter 구현**

```swift
import Accelerate

public struct AudioLevels: Sendable, Equatable {
    public var rms: Float, peak: Float, low: Float, mid: Float, high: Float
    public static let silence = AudioLevels(rms: 0, peak: 0, low: 0, mid: 0, high: 0)
}

/// 모노 샘플 버퍼 → 레벨. 256포인트 FFT 하나. 순수 함수.
public enum LevelMeter {
    static let n = 256
    static let log2n = vDSP_Length(8)
    nonisolated(unsafe) static let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

    public static func measure(_ samples: [Float], sampleRate: Float) -> AudioLevels {
        guard samples.count >= n else { return .silence }
        var rms: Float = 0, peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        if peak < 1e-5 { return .silence }

        // 마지막 256 샘플에 Hann 창 → 실수 FFT → 대역별 에너지
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var frame = [Float](repeating: 0, count: n)
        vDSP_vmul(Array(samples.suffix(n)), 1, window, 1, &frame, 1, vDSP_Length(n))
        var re = [Float](repeating: 0, count: n / 2), im = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        re.withUnsafeMutableBufferPointer { rp in im.withUnsafeMutableBufferPointer { ip in
            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
            frame.withUnsafeBufferPointer { fp in
                fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                    vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2)) } }
            vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
        } }
        let binHz = sampleRate / Float(n)
        func band(_ lo: Float, _ hi: Float) -> Float {
            let a = max(1, Int(lo / binHz)), b = min(n / 2 - 1, Int(hi / binHz))
            guard b >= a else { return 0 }
            var s: Float = 0; vDSP_sve(Array(mags[a...b]), 1, &s, vDSP_Length(b - a + 1))
            return min(1, sqrt(s / Float(b - a + 1)) / Float(n) * 8)     // ponytail: 경험적 스케일, 감도 슬라이더로 보정
        }
        return AudioLevels(rms: min(1, rms), peak: min(1, peak),
                           low: band(20, 250), mid: band(250, 2000), high: band(2000, sampleRate / 2))
    }
}
```

- [ ] **Step 4: 통과 확인** — `Executed 12 tests, with 0 failures`. 스케일 상수 때문에 대역 테스트가 실패하면 `* 8` 계수만 조정 (테스트는 상대 비교라 통과해야 정상).

- [ ] **Step 5: AudioTap 구현** (테스트 없음 — 실기 확인)

```swift
import CoreAudio
import Foundation

/// 시스템 출력 전체를 Process Tap으로 읽어 AudioLevels를 흘린다. macOS 14.2+.
public final class AudioTap: @unchecked Sendable {
    public enum TapError: Error { case createTap(OSStatus), createAggregate(OSStatus), ioProc(OSStatus), noOutputDevice }
    public var onLevels: (@Sendable (AudioLevels) -> Void)?
    public private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sampleRate: Float = 48000

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID(); desc.muteBehavior = .unmuted; desc.name = "G560Studio"
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw TapError.createTap(st) }

        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt)
        sampleRate = Float(fmt.mSampleRate)

        let outUID = try Self.defaultOutputUID()
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "G560Studio Tap",
            kAudioAggregateDeviceUIDKey: "com.onestudio.G560Studio.tap",
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard st == noErr else { stop(); throw TapError.createAggregate(st) }

        let channels = Int(fmt.mChannelsPerFrame)
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { [weak self] _, inData, _, _, _ in
            guard let self, let buf = UnsafeMutableAudioBufferListPointer(inData).first,
                  let p = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
            let frames = Int(buf.mDataByteSize) / MemoryLayout<Float>.size / max(1, channels)
            guard frames > 0 else { return }
            // 인터리브 스테레오 → 모노 (L+R)/2
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames { var s: Float = 0; for c in 0..<channels { s += p[i * channels + c] }; mono[i] = s / Float(channels) }
            self.onLevels?(LevelMeter.measure(mono, sampleRate: self.sampleRate))
        }
        guard st == noErr else { stop(); throw TapError.ioProc(st) }
        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else { stop(); throw TapError.ioProc(st) }
        isRunning = true
    }

    public func stop() {
        if let p = procID, aggID != kAudioObjectUnknown { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p); procID = nil }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
        isRunning = false
    }

    static func defaultOutputUID() throws -> String {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != kAudioObjectUnknown else { throw TapError.noOutputDevice }
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid) == noErr else { throw TapError.noOutputDevice }
        return uid as String
    }
    deinit { stop() }
}
```

- [ ] **Step 6: 실기 확인 — g560ctl에 `levels` 추가**

`main.swift` switch에:
```swift
case "levels":   // 5초간 오디오 레벨 출력. 앱 번들이 아니라 TCC 팝업이 안 뜰 수 있음 → 그 경우 Task 11 앱에서 확인
    let tap = AudioTap()
    tap.onLevels = { l in print(String(format: "rms %.2f peak %.2f low %.2f mid %.2f high %.2f", l.rms, l.peak, l.low, l.mid, l.high)) }
    try tap.start(); Thread.sleep(forTimeInterval: 5); tap.stop()
```
이 케이스는 장치 불필요 → `dev.onConnect` 밖에서 처리하도록 `if cmd == "levels" { ...; exit(0) }`를 `dev.start()` 앞에 둔다.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift run g560ctl levels
```
음악을 틀고 실행. Expected: 값이 소리에 따라 변함. 전부 0이면 시스템 설정 → 개인정보 보호 → 화면 및 시스템 오디오 녹음에서 터미널 허용 후 재시도.

- [ ] **Step 7: Commit** — `git add Sources Tests && git commit -m "Add LevelMeter (FFT bands) and CoreAudio process tap"`

---

### Task 7: 조명 프레임 계산 + LightingEngine

**Files:**
- Modify: `Sources/G560Core/Lighting.swift`
- Create: `Sources/G560Core/LightingEngine.swift`, `Tests/G560CoreTests/LightingTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public extension LightingConfig { func frame(t: TimeInterval, audio: AudioLevels, envelope: inout Float) -> ZoneColors }
  public final class LightingEngine {
      public init(device: G560Device)
      public var config: LightingConfig { get set }     // 교체 시 즉시 다음 틱 반영
      public var enabled: Bool { get set }              // false → 4존 off 한 번 보내고 정지
      public private(set) var lastFrame: ZoneColors     // 아이콘이 읽음
      public func update(audio: AudioLevels)            // AudioTap 콜백에서 호출
      public func start(); public func stop()
  }
  ```

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import G560Core

final class LightingTests: XCTestCase {
    let red = ZoneColors(all: RGB(255, 0, 0))
    func testOff() { var e: Float = 0; XCTAssertEqual(LightingConfig.off.frame(t: 1, audio: .silence, envelope: &e), .off) }
    func testFixedIgnoresAudio() {
        var e: Float = 0
        XCTAssertEqual(LightingConfig.fixed(red).frame(t: 5, audio: AudioLevels(rms: 1, peak: 1, low: 1, mid: 1, high: 1), envelope: &e), red)
    }
    func testBreathingDimsAtHalfPeriod() {
        var e: Float = 0
        let top = LightingConfig.breathing(red, period: 2).frame(t: 0.5, audio: .silence, envelope: &e).zones[0]
        let bottom = LightingConfig.breathing(red, period: 2).frame(t: 1.5, audio: .silence, envelope: &e).zones[0]
        XCTAssertGreaterThan(top.r, 200); XCTAssertLessThan(bottom.r, 60)
    }
    func testColorCycleChangesHueOverTime() {
        var e: Float = 0
        let a = LightingConfig.colorCycle(speed: 0.5).frame(t: 0, audio: .silence, envelope: &e)
        let b = LightingConfig.colorCycle(speed: 0.5).frame(t: 1, audio: .silence, envelope: &e)
        XCTAssertNotEqual(a, b)
    }
    func testSoundReactiveSilenceIsDimNotOff() {
        var e: Float = 0
        let z = LightingConfig.soundReactive(red, sensitivity: 1, splitBands: false).frame(t: 0, audio: .silence, envelope: &e).zones[0]
        XCTAssertGreaterThan(z.r, 0); XCTAssertLessThan(z.r, 60)
    }
    func testSoundReactiveLoudIsBright() {
        var e: Float = 0
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, splitBands: false)
        let loud = AudioLevels(rms: 0.6, peak: 1, low: 0.5, mid: 0.5, high: 0.5)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: loud, envelope: &e) }   // 어택 수렴
        XCTAssertGreaterThan(cfg.frame(t: 0, audio: loud, envelope: &e).zones[0].r, 200)
    }
    func testSplitBandsSendsBassToRear() {
        var e: Float = 0
        let cfg = LightingConfig.soundReactive(red, sensitivity: 1, splitBands: true)
        let bass = AudioLevels(rms: 0.5, peak: 0.8, low: 0.9, mid: 0, high: 0)
        for _ in 0..<10 { _ = cfg.frame(t: 0, audio: bass, envelope: &e) }
        let f = cfg.frame(t: 0, audio: bass, envelope: &e)
        XCTAssertGreaterThan(f.zones[2].r, f.zones[0].r)   // 좌 뒤 > 좌 앞
    }
}
```

- [ ] **Step 2: 실패 확인** — `value of type 'LightingConfig' has no member 'frame'`

- [ ] **Step 3: frame 구현** (`Lighting.swift`에 추가)

```swift
import Foundation

extension RGB {
    func scaled(_ k: Float) -> RGB {
        let k = max(0, min(1, k))
        return RGB(UInt8(Float(r) * k), UInt8(Float(g) * k), UInt8(Float(b) * k))
    }
    static func hue(_ h: Float) -> RGB {           // h 0…1, 채도/명도 1
        let x = h.truncatingRemainder(dividingBy: 1) * 6, i = Int(x), f = x - Float(i)
        let q = UInt8((1 - f) * 255), t = UInt8(f * 255)
        switch i { case 0: return RGB(255, t, 0); case 1: return RGB(q, 255, 0); case 2: return RGB(0, 255, t)
                   case 3: return RGB(0, q, 255); case 4: return RGB(t, 0, 255); default: return RGB(255, 0, q) }
    }
}

public extension LightingConfig {
    /// 한 프레임의 4존 색. `envelope`는 사운드 반응 모드의 어택/릴리즈 상태 (호출자가 보관).
    func frame(t: TimeInterval, audio: AudioLevels, envelope: inout Float) -> ZoneColors {
        switch self {
        case .off: return .off
        case .fixed(let z): return z
        case .colorCycle(let speed):
            let base = Float(t * speed)
            return ZoneColors(zones: (0..<G560.zoneCount).map { RGB.hue(base + Float($0) * 0.08) })
        case .breathing(let z, let period):
            let k = 0.1 + 0.9 * Float(0.5 - 0.5 * cos(2 * .pi * t / period))
            return ZoneColors(zones: z.zones.map { $0.scaled(k) })
        case .soundReactive(let z, let sens, let split):
            let target = min(1, audio.rms * Float(sens) * 2.5)
            envelope += (target - envelope) * (target > envelope ? 0.5 : 0.12)   // 어택 빠르게, 릴리즈 천천히
            let floor: Float = 0.12
            if !split { return ZoneColors(zones: z.zones.map { $0.scaled(floor + (1 - floor) * envelope) }) }
            let front = floor + (1 - floor) * min(1, audio.high * Float(sens) * 2)   // 존 0,1 = 앞
            let rear  = floor + (1 - floor) * min(1, audio.low  * Float(sens) * 2)   // 존 2,3 = 뒤
            return ZoneColors(zones: [z.zones[0].scaled(front), z.zones[1].scaled(front),
                                      z.zones[2].scaled(rear),  z.zones[3].scaled(rear)])
        }
    }
}
```

- [ ] **Step 4: 통과 확인** — `Executed 19 tests, with 0 failures`

- [ ] **Step 5: LightingEngine**

```swift
import Foundation

/// 30Hz로 현재 config의 프레임을 계산해 바뀐 존만 장치에 쓴다.
public final class LightingEngine: @unchecked Sendable {
    public var config: LightingConfig = .off
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
        let t = DispatchSource.makeTimer(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))   // ponytail: 30Hz 고정, 장치가 버거우면 여기만 조정
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume(); timer = t
    }
    public func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard enabled, device.isConnected else { return }
        let f = config.frame(t: Date().timeIntervalSince(t0), audio: audio, envelope: &envelope)
        push(f)
    }

    private func push(_ f: ZoneColors) {
        for z in 0..<G560.zoneCount where f.zones[z] != lastFrame.zones[z] {
            try? device.setZone(z, f.zones[z])
        }
        lastFrame = f
    }

    private func blackout() { queue.async { self.push(.off) } }

    /// 재연결 시 강제 재전송
    public func resend() { queue.async { self.lastFrame = ZoneColors(all: RGB(1, 1, 1)); self.push(self.config.frame(t: 0, audio: self.audio, envelope: &self.envelope)) } }
}
```

- [ ] **Step 6: 실기 확인 — g560ctl에 `demo` 추가**

```swift
case "demo":   // 10초 사운드 반응 데모
    let engine = LightingEngine(device: dev)
    engine.config = .soundReactive(ZoneColors(all: RGB(0, 120, 255)), sensitivity: 1.5, splitBands: true)
    let tap = AudioTap(); tap.onLevels = { engine.update(audio: $0) }
    try tap.start(); engine.start(); Thread.sleep(forTimeInterval: 10); engine.enabled = false; Thread.sleep(forTimeInterval: 0.2); tap.stop()
```
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift run g560ctl demo
```
음악 재생 중 실행. Expected: 파란 조명이 소리에 맞춰 밝기 변화, 저음에 뒤쪽이 더 반응. 끝나면 꺼짐. 장치가 명령을 놓치거나 지연되면 `.milliseconds(33)`을 50으로.

- [ ] **Step 7: Commit** — `git add Sources Tests && git commit -m "Add lighting frame math and 30Hz engine"`

---

### Task 8: OutputVolume (CoreAudio)

**Files:**
- Create: `Sources/G560Core/OutputVolume.swift`

**Interfaces:**
- Produces: `public enum OutputVolume { static func g560DeviceID() -> AudioObjectID?; static func get() -> Double?; static func set(_ v: Double) throws }` — G560 장치를 이름("G560")으로 찾고, 없으면 기본 출력 장치. 채널 1·2 개별 설정(main element 미지원 대비).

- [ ] **Step 1: 구현**

```swift
import CoreAudio

public enum OutputVolume {
    public enum VolumeError: Error { case noDevice, setFailed(OSStatus) }

    static func allOutputDevices() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }
    static func name(_ id: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var s: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &s); return s as String
    }
    public static func g560DeviceID() -> AudioObjectID? { allOutputDevices().first { name($0).contains("G560") } }

    static func volAddr(_ ch: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: ch)
    }
    public static func get() -> Double? {
        guard let id = g560DeviceID() else { return nil }
        for ch: UInt32 in [0, 1] {
            var a = volAddr(ch); var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(id, &a), AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr { return Double(v) }
        }
        return nil
    }
    public static func set(_ value: Double) throws {
        guard let id = g560DeviceID() else { throw VolumeError.noDevice }
        var v = Float32(max(0, min(1, value))); let size = UInt32(MemoryLayout<Float32>.size)
        var ok = false
        for ch: UInt32 in [0, 1, 2] {           // main, L, R — 지원되는 것만
            var a = volAddr(ch)
            if AudioObjectHasProperty(id, &a) { let st = AudioObjectSetPropertyData(id, &a, 0, nil, size, &v); ok = ok || st == noErr }
        }
        if !ok { throw VolumeError.setFailed(-1) }
    }
}
```

- [ ] **Step 2: g560ctl `volume <0-100>` 추가 후 실기 확인**

```swift
case "volume": try OutputVolume.set(Double(args[1])! / 100); print("volume:", OutputVolume.get().map { Int($0 * 100) } ?? -1)
```
(장치 불필요 → `levels`처럼 `dev.start()` 앞에서 처리.)
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift run g560ctl volume 30 && swift run g560ctl volume 50
```
Expected: 시스템 볼륨 표시가 따라 움직이고 `volume: 30`, `volume: 50`.

- [ ] **Step 3: Commit** — `git add Sources && git commit -m "Add CoreAudio output volume for G560"`

---

### Task 9: AppState + 프로필 적용

**Files:**
- Create: `Sources/G560Studio/AppState.swift`

**Interfaces:**
- Produces:
  ```swift
  @Observable @MainActor final class AppState {
      let device: G560Device; let tap: AudioTap; let engine: LightingEngine
      var store: ProfileStore
      var connected: Bool; var audioError: String?; var deviceError: String?
      var levels: AudioLevels; var zoneColors: ZoneColors        // 아이콘용, 30Hz 갱신
      var draft: Profile                                          // 편집 중 값 (설정 창 바인딩)
      func apply(_ p: Profile)          // 조명 config + 우퍼 + 볼륨 + EQ 전송, activeID 저장
      func applyDraft(eq: Bool = false) // draft를 장치에 (EQ는 명시적일 때만)
      func saveDraftAsActive()          // draft → store.profiles[active], save()
      func restoreFactory()             // woofer 40, eq flat, 조명 off → draft에도 반영
      init()
  }
  ```

- [ ] **Step 1: 구현**

```swift
import Foundation
import G560Core
import Observation

@Observable @MainActor
final class AppState {
    let device = G560Device()
    let tap = AudioTap()
    let engine: LightingEngine
    var store = ProfileStore()
    var connected = false
    var audioError: String?
    var deviceError: String?
    var levels = AudioLevels.silence
    var zoneColors = ZoneColors.off
    var draft: Profile
    private var iconTimer: Timer?

    init() {
        engine = LightingEngine(device: device)
        draft = store.active ?? Profile.makeDefault(name: "기본")
        device.onConnect = { [weak self] in Task { @MainActor in self?.connected = true; self?.deviceError = nil; self?.apply(self!.draft) } }
        device.onDisconnect = { [weak self] in Task { @MainActor in self?.connected = false } }
        tap.onLevels = { [weak self] l in self?.engine.update(audio: l); Task { @MainActor in self?.levels = l } }
        device.start()
        do { try tap.start() } catch { audioError = "시스템 오디오 접근 실패: \(error). 시스템 설정 → 개인정보 보호 → 화면 및 시스템 오디오 녹음에서 G560Studio를 허용하세요." }
        engine.start()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.zoneColors = self?.engine.lastFrame ?? .off }
        }
    }

    func apply(_ p: Profile) {
        draft = p
        engine.config = p.lighting
        engine.resend()
        try? OutputVolume.set(p.volume)
        guard connected else { return }
        do { try device.setWoofer(p.woofer); try device.setEqualizer(p.eq); deviceError = nil }
        catch { deviceError = "장치 명령 실패: \(error)" }
        store.activeID = p.id; try? store.save()
    }

    /// 설정 창의 슬라이더/색 변경을 즉시 반영. EQ는 EEPROM이라 명시적으로만.
    func applyDraft(eq: Bool = false) {
        engine.config = draft.lighting
        try? OutputVolume.set(draft.volume)
        guard connected else { return }
        do { try device.setWoofer(draft.woofer); if eq { try device.setEqualizer(draft.eq) }; deviceError = nil }
        catch { deviceError = "장치 명령 실패: \(error)" }
    }

    func saveDraftAsActive() {
        if let i = store.profiles.firstIndex(where: { $0.id == store.activeID }) { store.profiles[i] = draft }
        try? store.save()
    }

    func restoreFactory() {
        draft.woofer = 40; draft.eq = [Int](repeating: 0, count: G560.eqBands); draft.lighting = .off
        applyDraft(eq: true)
    }
}
```

- [ ] **Step 2: 빌드 확인** — `swift build 2>&1 | grep -E "error|Compiling" | tail -2` → 에러 없음
- [ ] **Step 3: Commit** — `git add Sources && git commit -m "Add AppState: wiring, profile apply, factory restore"`

---

### Task 10: MenuBarIcon (실시간 컬러 파형) + QuickPanel

**Files:**
- Create: `Sources/G560Studio/MenuBarIcon.swift`, `Sources/G560Studio/QuickPanel.swift`
- Modify: `Sources/G560Studio/App.swift`

- [ ] **Step 1: MenuBarIcon**

```swift
import AppKit
import G560Core

/// 매 프레임 그리는 메뉴바 아이콘: 오디오 파형(형태) + 좌→우 4존 색 그라데이션(색). 템플릿 아님.
enum MenuBarIcon {
    static let size = NSSize(width: 44, height: 18)
    private static var phase: CGFloat = 0

    static func render(levels: AudioLevels, zones: ZoneColors, connected: Bool) -> NSImage {
        phase += 0.25 + CGFloat(levels.rms) * 0.6
        let img = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(); path.lineWidth = 2; path.lineCapStyle = .round
            let mid = rect.midY, amp = CGFloat(min(1, levels.rms * 2.2)) * (rect.height / 2 - 1)
            for x in stride(from: 0, through: rect.width, by: 1) {
                let p = x / rect.width
                let env = sin(p * .pi)
                let y = mid + env * amp * sin(p * 14 + phase) * sin(phase * 0.35 + p * 2)
                x == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
            }
            let colors: [NSColor] = connected
                ? zones.zones.map { NSColor(red: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1) }
                : [NSColor.gray, .gray, .gray, .gray]
            // 존 순서는 0=좌앞,1=우앞,2=좌뒤,3=우뒤 → 왼쪽부터 좌뒤, 좌앞, 우앞, 우뒤
            let ordered = [colors[2], colors[0], colors[1], colors[3]]
            let allBlack = zones.zones.allSatisfy { $0 == .off }
            let grad = NSGradient(colors: allBlack || !connected ? [.gray, .gray] : ordered)!
            // 선을 굵기 2의 영역으로 바꿔 클립한 뒤 그라데이션을 채운다
            let cg = NSGraphicsContext.current!.cgContext
            cg.saveGState(); cg.addPath(path.cgPath); cg.setLineWidth(2); cg.setLineCap(.round)
            cg.replacePathWithStrokedPath(); cg.clip()
            grad.draw(from: NSPoint(x: 0, y: 0), to: NSPoint(x: rect.width, y: 0), options: [])
            cg.restoreGState()
            return true
        }
        img.isTemplate = false
        return img
    }
}
```
`NSBezierPath.cgPath`는 macOS 14+에 있음. 무음(rms 0)이면 amp 0 → 평평한 그라데이션 선.

- [ ] **Step 2: QuickPanel**

```swift
import SwiftUI
import G560Core

struct QuickPanel: View {
    @Environment(AppState.self) var state
    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(state.connected ? .green : .red).frame(width: 8, height: 8)
                Text(state.connected ? "G560 연결됨" : "G560 연결 안 됨").font(.caption)
                Spacer()
                Toggle("조명", isOn: Binding(get: { state.engine.enabled }, set: { state.engine.enabled = $0 })).toggleStyle(.switch).controlSize(.mini)
            }
            if let e = state.deviceError ?? state.audioError { Text(e).font(.caption2).foregroundStyle(.red) }
            Divider()
            Text("프로필").font(.caption).foregroundStyle(.secondary)
            ForEach(state.store.profiles) { p in
                Button { state.apply(p) } label: {
                    HStack { Text(p.name); Spacer(); if p.id == state.store.activeID { Image(systemName: "checkmark") } }
                }.buttonStyle(.plain)
            }
            Divider()
            LabeledContent("볼륨 \(Int(state.draft.volume * 100))") {
                Slider(value: $state.draft.volume, in: 0...1) { if !$0 { state.applyDraft() } }
            }
            LabeledContent("우퍼 \(state.draft.woofer)") {
                Slider(value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0) }), in: 0...100, step: 1) { if !$0 { state.applyDraft() } }
            }
            Divider()
            HStack {
                SettingsLink { Text("설정 열기…") }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
        }
        .padding(12).frame(width: 260)
    }
}
```

- [ ] **Step 3: App.swift**

```swift
import SwiftUI
import G560Core

@main
struct G560StudioApp: App {
    @State private var state = AppState()
    var body: some Scene {
        MenuBarExtra {
            QuickPanel().environment(state)
        } label: {
            Image(nsImage: MenuBarIcon.render(levels: state.levels, zones: state.zoneColors, connected: state.connected))
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView().environment(state) }
    }
}
```
`SettingsView`는 Task 11에서. 지금은 `Sources/G560Studio/SettingsView.swift`에 `struct SettingsView: View { var body: some View { Text("설정").frame(width: 400, height: 300) } }` 임시.

- [ ] **Step 4: 번들 실행 확인**

```bash
scripts/bundle.sh && open build/G560Studio.app
```
Expected: 첫 실행 시 시스템 오디오 권한 팝업 → 허용. 메뉴바에 컬러 파형이 음악에 맞춰 움직임(장치 색 = 활성 프로필 흰색 사운드 반응). 클릭 → 패널에 연결 상태·프로필·슬라이더. 우퍼 슬라이더 놓으면 우퍼 변경. USB 뽑으면 아이콘 회색·"연결 안 됨", 꽂으면 복귀 + 조명 재적용.

- [ ] **Step 5: Commit** — `git add Sources && git commit -m "Add live color-waveform menu bar icon and quick panel"`

---

### Task 11: 설정 창 (조명 / 출력 / 프로필)

**Files:**
- Create: `Sources/G560Studio/SettingsView.swift`(교체), `LightingTab.swift`, `OutputTab.swift`, `ProfilesTab.swift`

- [ ] **Step 1: SettingsView**

```swift
import SwiftUI
struct SettingsView: View {
    var body: some View {
        TabView {
            LightingTab().tabItem { Label("조명", systemImage: "lightbulb") }
            OutputTab().tabItem { Label("출력", systemImage: "speaker.wave.2") }
            ProfilesTab().tabItem { Label("프로필", systemImage: "person.crop.rectangle.stack") }
        }.frame(width: 520, height: 420).padding()
    }
}
```

- [ ] **Step 2: LightingTab** — 모드 Picker + 존별 ColorPicker(이름+hex 표시) + 파라미터

```swift
import SwiftUI
import G560Core

struct LightingTab: View {
    @Environment(AppState.self) var state
    enum Mode: String, CaseIterable { case off = "끄기", fixed = "고정", cycle = "컬러 사이클", breathing = "브리딩", sound = "사운드 반응" }

    var mode: Mode {
        switch state.draft.lighting { case .off: .off; case .fixed: .fixed; case .colorCycle: .cycle; case .breathing: .breathing; case .soundReactive: .sound }
    }
    var colors: ZoneColors {
        switch state.draft.lighting { case .fixed(let z), .breathing(let z, _), .soundReactive(let z, _, _): z; default: ZoneColors(all: RGB(255, 255, 255)) }
    }
    func set(_ m: Mode) {
        let z = colors
        switch m {
        case .off: state.draft.lighting = .off
        case .fixed: state.draft.lighting = .fixed(z)
        case .cycle: state.draft.lighting = .colorCycle(speed: 0.1)
        case .breathing: state.draft.lighting = .breathing(z, period: 3)
        case .sound: state.draft.lighting = .soundReactive(z, sensitivity: 1.5, splitBands: false)
        }
        state.applyDraft()
    }
    func setColor(_ zone: Int, _ c: RGB) {
        var z = colors; z.zones[zone] = c
        switch state.draft.lighting {
        case .fixed: state.draft.lighting = .fixed(z)
        case .breathing(_, let p): state.draft.lighting = .breathing(z, period: p)
        case .soundReactive(_, let s, let b): state.draft.lighting = .soundReactive(z, sensitivity: s, splitBands: b)
        default: break
        }
        state.applyDraft()
    }

    var body: some View {
        Form {
            Picker("모드", selection: Binding(get: { mode }, set: set)) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
            if mode == .fixed || mode == .breathing || mode == .sound {
                Section("존 색상") {
                    ForEach(0..<G560.zoneCount, id: \.self) { z in
                        let c = colors.zones[z]
                        HStack {
                            ColorPicker(G560.zoneNames[z], selection: Binding(
                                get: { Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255) },
                                set: { col in let n = NSColor(col).usingColorSpace(.sRGB)!
                                       setColor(z, RGB(UInt8(n.redComponent * 255), UInt8(n.greenComponent * 255), UInt8(n.blueComponent * 255))) }), supportsOpacity: false)
                            Text("#\(c.hex)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    Button("모든 존 같은 색으로") { let c = colors.zones[0]; for z in 1..<G560.zoneCount { setColor(z, c) } }
                }
            }
            if case .soundReactive(let z, let s, let b) = state.draft.lighting {
                Section("사운드 반응") {
                    LabeledContent("감도 \(String(format: "%.1f", s))") {
                        Slider(value: Binding(get: { s }, set: { state.draft.lighting = .soundReactive(z, sensitivity: $0, splitBands: b); state.applyDraft() }), in: 0.5...4)
                    }
                    Toggle("저음은 뒤쪽, 고음은 앞쪽", isOn: Binding(get: { b }, set: { state.draft.lighting = .soundReactive(z, sensitivity: s, splitBands: $0); state.applyDraft() }))
                }
            }
            if case .breathing(let z, let p) = state.draft.lighting {
                LabeledContent("주기 \(String(format: "%.1f", p))초") {
                    Slider(value: Binding(get: { p }, set: { state.draft.lighting = .breathing(z, period: $0); state.applyDraft() }), in: 1...10)
                }
            }
            if case .colorCycle(let sp) = state.draft.lighting {
                LabeledContent("속도") {
                    Slider(value: Binding(get: { sp }, set: { state.draft.lighting = .colorCycle(speed: $0); state.applyDraft() }), in: 0.02...0.5)
                }
            }
        }.formStyle(.grouped)
    }
}
```

- [ ] **Step 3: OutputTab** — 볼륨·우퍼 슬라이더 + EQ 10밴드 (놓을 때만 전송) + 프리셋

```swift
import SwiftUI
import G560Core

struct OutputTab: View {
    @Environment(AppState.self) var state
    static let presets: [(String, [Int])] = [
        ("Flat", [0,0,0,0,0,0,0,0,0,0]),
        ("Bass Boost", [5,4,3,1,0,0,0,0,0,0]),
        ("Night (저음 줄임)", [-8,-6,-4,-2,0,0,0,0,0,0]),
        ("Vocal", [-2,-1,0,1,3,3,2,1,0,0]),
    ]
    var body: some View {
        @Bindable var state = state
        Form {
            Section("출력") {
                LabeledContent("볼륨 \(Int(state.draft.volume * 100))") {
                    Slider(value: $state.draft.volume, in: 0...1) { if !$0 { state.applyDraft() } }
                }
                LabeledContent("서브우퍼 \(state.draft.woofer)") {
                    Slider(value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0) }), in: 0...100, step: 1) { if !$0 { state.applyDraft() } }
                }
            }
            Section("이퀄라이저 (−20…+6 dB, 놓을 때 저장됨)") {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<G560.eqBands, id: \.self) { i in
                        VStack {
                            Text("\(state.draft.eq[i] > 0 ? "+" : "")\(state.draft.eq[i])").font(.caption2).monospacedDigit()
                            Slider(value: Binding(get: { Double(state.draft.eq[i]) }, set: { state.draft.eq[i] = Int($0.rounded()) }),
                                   in: Double(G560.eqRange.lowerBound)...Double(G560.eqRange.upperBound), step: 1) { if !$0 { state.applyDraft(eq: true) } }
                                .rotationEffect(.degrees(-90)).frame(width: 20, height: 120)
                            Text(G560.eqFrequencies[i] >= 1000 ? "\(G560.eqFrequencies[i] / 1000)k" : "\(G560.eqFrequencies[i])").font(.caption2)
                        }
                    }
                }.frame(maxWidth: .infinity)
                HStack {
                    ForEach(Self.presets, id: \.0) { name, g in Button(name) { state.draft.eq = g; state.applyDraft(eq: true) } }
                }
            }
        }.formStyle(.grouped)
    }
}
```

- [ ] **Step 4: ProfilesTab** — 목록, 새 프로필(현재 draft 복제), 이름 변경, 삭제, 적용, 현재 설정 저장, 기본값 초기화

```swift
import SwiftUI
import G560Core

struct ProfilesTab: View {
    @Environment(AppState.self) var state
    @State private var confirmRestore = false
    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading) {
            List {
                ForEach($state.store.profiles) { $p in
                    HStack {
                        TextField("이름", text: $p.name).onSubmit { try? state.store.save() }
                        Spacer()
                        if p.id == state.store.activeID { Text("활성").font(.caption).foregroundStyle(.secondary) }
                        Button("적용") { state.apply(p) }
                        Button(role: .destructive) {
                            state.store.profiles.removeAll { $0.id == p.id }
                            if state.store.activeID == p.id { state.store.activeID = state.store.profiles.first?.id }
                            try? state.store.save()
                        } label: { Image(systemName: "trash") }.disabled(state.store.profiles.count == 1)
                    }
                }
            }
            HStack {
                Button("새 프로필 (현재 설정으로)") {
                    var p = state.draft; p.id = UUID(); p.name = "프로필 \(state.store.profiles.count + 1)"
                    state.store.profiles.append(p); state.store.activeID = p.id; try? state.store.save()
                }
                Button("현재 설정을 활성 프로필에 저장") { state.saveDraftAsActive() }
                Spacer()
                Button("기본값으로 초기화", role: .destructive) { confirmRestore = true }
                    .confirmationDialog("우퍼 40, EQ Flat, 조명 끄기로 되돌립니다. (프로필 파일은 그대로)", isPresented: $confirmRestore) {
                        Button("초기화", role: .destructive) { state.restoreFactory() }
                    }
            }
        }.padding()
    }
}
```

- [ ] **Step 5: 실행 확인**

```bash
scripts/bundle.sh && open build/G560Studio.app
```
체크리스트:
- 조명 탭: 모드 전환 즉시 장치 반영, 존 색 변경 시 해당 존만 바뀜, hex 표시
- 출력 탭: 우퍼 슬라이더 놓을 때 `tools/.venv/bin/python tools/g560probe.py dump /tmp/a.json && ...diff` 로 값 확인, EQ 밴드 놓을 때만 저장 (드래그 중 변화 없음), 프리셋 Night 적용 후 diff에 `0x8310 fn 2` 변화
- 프로필 탭: 새 프로필 → 이름 변경 → 적용 → 앱 재시작 후 마지막 프로필 복원
- 기본값 초기화 → `g560probe.py diff factory-defaults.json` = `no differences`

- [ ] **Step 6: Commit** — `git add Sources && git commit -m "Add settings window: lighting, output/EQ, profiles"`

---

### Task 12: 마무리 — 로그인 시 시작 옵션, README

**Files:**
- Modify: `Sources/G560Studio/QuickPanel.swift` (로그인 시 시작 토글), `README.md`

- [ ] **Step 1: 로그인 항목** — `ServiceManagement`의 `SMAppService.mainApp` 토글을 QuickPanel 하단에 추가

```swift
import ServiceManagement
// QuickPanel 하단 HStack 위에:
Toggle("로그인 시 시작", isOn: Binding(
    get: { SMAppService.mainApp.status == .enabled },
    set: { on in try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }
)).controlSize(.small)
```
번들이 `/Applications`에 있어야 안정적 — bundle.sh 끝에 안내 문구 출력: `echo "설치: cp -R $APP /Applications/"`.

- [ ] **Step 2: README.md** (기존 내용 교체)

```markdown
# G560Studio

Logitech G560을 G HUB 없이 macOS 메뉴바에서 제어. 사운드 반응 LightSync, 서브우퍼 레벨, 10밴드 EQ, 프로필.

## 빌드
Xcode 26 필요.
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    scripts/bundle.sh release && cp -R build/G560Studio.app /Applications/
첫 실행 시 "시스템 오디오 녹음" 권한을 허용.

## CLI / 복구
    swift run g560ctl status | led all 00A0FF | woofer 40 | eq 0 0 0 0 0 0 0 0 0 0 | restore
    tools/.venv/bin/python tools/g560probe.py restore   # Python 쪽 복구

## 프로토콜
docs/protocol.md — 실측한 HID++ 명령. 검증된 3개 쓰기 명령만 사용.
```

- [ ] **Step 3: 전체 테스트 + 번들 + Commit**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; swift test 2>&1 | grep Executed && scripts/bundle.sh release && git add -A && git commit -m "Add login item toggle and README" && git push
```

---

## Phase 1 완료 조건

- `swift test` 전부 통과 (19개)
- `build/G560Studio.app` 실행: 메뉴바 컬러 파형이 음악에 반응, 4존 조명이 사운드 반응 모드로 동작
- 우퍼·EQ·볼륨 변경이 장치/시스템에 반영되고 프로필로 저장·복원됨
- USB 재연결 시 자동 복구
- "기본값으로 초기화" 후 `g560probe.py diff factory-defaults.json` = `no differences`
- 앱 종료 후에도 우퍼/EQ는 마지막 값 유지(장치 저장), 조명은 장치 기본으로 복귀(휘발성) — 의도된 동작
