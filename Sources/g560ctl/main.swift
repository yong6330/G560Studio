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
