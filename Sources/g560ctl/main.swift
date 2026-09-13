import Foundation
import G560Core

let usage = "g560ctl status | led <zone|all> <RRGGBB> | woofer <0-100> | eq <g0> ... <g9> | restore | levels | demo | cycle | volume <0-100>"
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(1) }

if cmd == "levels" {   // 5초간 오디오 레벨 출력 (장치 불필요)
    let tap = AudioTap()
    tap.onLevels = { l in print(String(format: "rms %.2f peak %.2f low %.2f mid %.2f high %.2f", l.rms, l.peak, l.low, l.mid, l.high)) }
    do { try tap.start() } catch { print("tap error:", error); exit(2) }
    Thread.sleep(forTimeInterval: 5); tap.stop(); exit(0)
}

if cmd == "volume" {   // CoreAudio (장치 HID 불필요)
    do { try OutputVolume.set(Double(args[1])! / 100) } catch { print("error:", error); exit(2) }
    print("volume:", OutputVolume.get().map { Int(($0 * 100).rounded()) } ?? -1); exit(0)
}

if cmd == "screen" {   // 5초 화면 샘플링 진단
    let sp = ScreenSampler(); print("permission:", ScreenSampler.hasPermission, "displays:", ScreenSampler.displays())
    sp.start()
    for _ in 0..<5 { Thread.sleep(forTimeInterval: 1); print("running:", sp.isRunning, "err:", sp.lastError ?? "-", "colors:", sp.colors.zones.map { $0.hex }) }
    exit(0)
}

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
        case "demo":   // 10초 사운드 반응 데모 (오디오 권한 없으면 어두운 파랑으로 고정)
            let engine = LightingEngine(device: dev)
            engine.config = .soundReactive(.custom(ZoneColors(all: RGB(0, 120, 255))), sensitivity: 1.5, split: .bassRear)
            let tap = AudioTap(); tap.onLevels = { engine.update(audio: $0) }
            try tap.start(); engine.start()
            Thread.sleep(forTimeInterval: 10)
            engine.enabled = false; Thread.sleep(forTimeInterval: 0.2); tap.stop()
        case "cycle":  // 5초 컬러 사이클 (오디오 불필요) — 엔진/전송 속도 확인용
            let engine = LightingEngine(device: dev)
            engine.config = .fixed(.rainbow(speed: 0.3)); engine.start()
            Thread.sleep(forTimeInterval: 5)
            engine.enabled = false; Thread.sleep(forTimeInterval: 0.2)
        case "restore":   // factory-defaults.json 기준 (protocol.md). LED는 휘발성이라 복원 불필요.
            try dev.setWoofer(G560.factoryWoofer); try dev.setEqualizer(G560.factoryEQ)
            print("restored: woofer", try dev.woofer(), "eq", try dev.equalizer())
        default: print(usage); exitCode = 1
        }
    } catch { print("error:", error); exitCode = 2 }
    done.signal()
}
dev.start()
if done.wait(timeout: .now() + 15) == .timedOut { print("G560 not found"); exitCode = 3 }
exit(exitCode)
