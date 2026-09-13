import Foundation
import G560Core

let usage = "g560ctl status | led <zone|all> <RRGGBB> | woofer <0-100> | eq <g0> ... <g9> | restore | levels"
let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(1) }

if cmd == "levels" {   // 5초간 오디오 레벨 출력 (장치 불필요)
    let tap = AudioTap()
    tap.onLevels = { l in print(String(format: "rms %.2f peak %.2f low %.2f mid %.2f high %.2f", l.rms, l.peak, l.low, l.mid, l.high)) }
    do { try tap.start() } catch { print("tap error:", error); exit(2) }
    Thread.sleep(forTimeInterval: 5); tap.stop(); exit(0)
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
        case "restore":   // factory-defaults.json 기준 (protocol.md). LED는 휘발성이라 복원 불필요.
            try dev.setWoofer(G560.factoryWoofer); try dev.setEqualizer(G560.factoryEQ)
            print("restored: woofer", try dev.woofer(), "eq", try dev.equalizer())
        default: print(usage); exitCode = 1
        }
    } catch { print("error:", error); exitCode = 2 }
    done.signal()
}
dev.start()
if done.wait(timeout: .now() + 3) == .timedOut { print("G560 not found"); exitCode = 3 }
exit(exitCode)
