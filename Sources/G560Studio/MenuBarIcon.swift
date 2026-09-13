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

            // 파형 레이어 3장: 큰 것부터, 서로 위상이 달라 겹치며 출렁임
            let layers: [(amp: CGFloat, freq: CGFloat, alpha: CGFloat, ph: CGFloat)] = [
                (1.0, 7, 0.35, 0), (0.75, 10, 0.45, 2.1), (0.5, 13, 0.6, 4.0),
            ]
            for l in layers {
                let path = CGMutablePath()
                var top: [CGPoint] = [], bottom: [CGPoint] = []
                for x in stride(from: CGFloat(0), through: rect.width, by: 0.5) {
                    let p = x / rect.width
                    let env = (0.15 + 0.85 * level) * l.amp * maxAmp * sin(p * .pi)
                    let h = env * abs(sin(p * l.freq + phase + l.ph)) * (0.6 + 0.4 * sin(phase * 0.4 + p * 3 + l.ph))
                    top.append(CGPoint(x: x, y: mid + h)); bottom.append(CGPoint(x: x, y: mid - h))
                }
                path.addLines(between: top + bottom.reversed()); path.closeSubpath()
                cg.saveGState()
                cg.addPath(path); cg.clip()
                NSGradient(colors: colors.map { $0.withAlphaComponent(l.alpha) })!
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
