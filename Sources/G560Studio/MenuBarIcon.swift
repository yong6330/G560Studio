import AppKit
import G560Core

/// 매 프레임 그리는 메뉴바 아이콘: 위아래 대칭으로 채워진 반투명 파형 레이어 + 가운데 밝은 선.
/// 색은 좌→우 4존 그라데이션. 템플릿 아님.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)
    nonisolated(unsafe) private static var phase: CGFloat = 0

    static func render(levels: AudioLevels, zones: ZoneColors, connected: Bool) -> NSImage {
        phase += 0.18 + CGFloat(levels.rms) * 0.5
        let img = NSImage(size: size, flipped: false) { rect in
            let mid = rect.midY
            let maxAmp = rect.height / 2 - 1
            let level = CGFloat(min(1, levels.rms * 3.6))   // 1.5배 민감
            // 존 순서 0=좌앞,1=우앞,2=좌뒤,3=우뒤 → 아이콘 왼쪽부터 좌뒤, 좌앞, 우앞, 우뒤
            let ordered = [zones.zones[2], zones.zones[0], zones.zones[1], zones.zones[3]]
            let dark = !connected || zones.zones.allSatisfy { $0 == .off }
            let colors: [NSColor] = dark ? [.gray, .gray] : ordered.map {
                NSColor(red: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1)
            }
            let cg = NSGraphicsContext.current!.cgContext

            // 레이어: 뒤 = 고음(뒤쪽 존 색), 앞 = 저음(앞쪽 존 색). 각각 해당 대역 레벨로 출렁인다.
            func c(_ z: Int) -> NSColor {
                let v = zones.zones[z]
                return NSColor(red: CGFloat(v.r) / 255, green: CGFloat(v.g) / 255, blue: CGFloat(v.b) / 255, alpha: 1)
            }
            let rear = dark ? [NSColor.gray, .gray] : [c(2), c(3)]
            let front = dark ? [NSColor.gray, .gray] : [c(0), c(1)]
            let layers: [(colors: [NSColor], lvl: CGFloat, amp: CGFloat, freq: CGFloat, alpha: CGFloat, ph: CGFloat)] = [
                (rear, CGFloat(min(1, levels.high * 3.0)), 1.0, 9, 0.45, 0),
                (front, CGFloat(min(1, levels.low * 2.5)), 0.7, 6, 0.6, 2.4),
            ]
            for l in layers {
                let path = CGMutablePath()
                var top: [CGPoint] = [], bottom: [CGPoint] = []
                for x in stride(from: CGFloat(0), through: rect.width, by: 0.5) {
                    let p = x / rect.width
                    let env = (0.12 + 0.88 * l.lvl) * l.amp * maxAmp * sin(p * .pi)
                    let h = env * abs(sin(p * l.freq + phase + l.ph)) * (0.6 + 0.4 * sin(phase * 0.4 + p * 3 + l.ph))
                    top.append(CGPoint(x: x, y: mid + h)); bottom.append(CGPoint(x: x, y: mid - h))
                }
                path.addLines(between: top + bottom.reversed()); path.closeSubpath()
                cg.saveGState()
                cg.addPath(path); cg.clip()
                NSGradient(colors: l.colors.map { $0.withAlphaComponent(l.alpha) })!
                    .draw(from: NSPoint(x: 0, y: mid), to: NSPoint(x: rect.width, y: mid), options: [])
                cg.restoreGState()
            }
            // 가운데 밝은 선
            cg.saveGState()
            cg.addRect(CGRect(x: 1, y: mid - 0.5, width: rect.width - 2, height: 1)); cg.clip()
            NSGradient(colors: colors)!.draw(from: NSPoint(x: 0, y: mid), to: NSPoint(x: rect.width, y: mid), options: [])
            cg.restoreGState()
            return true
        }
        img.isTemplate = false
        return img
    }
}
