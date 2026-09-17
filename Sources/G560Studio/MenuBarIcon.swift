import AppKit
import G560Core

/// 메뉴바 아이콘 스타일. 나중에 종류가 늘면 설정에 별도 탭으로 뺀다.
enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case wave = "파형"
    case logo = "로고"
}

enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)
    nonisolated(unsafe) private static var phase: CGFloat = 0
    nonisolated(unsafe) static let glyph: NSImage? =
        Bundle.main.url(forResource: "logo-glyph", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    static func render(levels: AudioLevels, zones: ZoneColors, connected: Bool, style: MenuBarStyle) -> NSImage {
        phase += 0.18 + CGFloat(levels.rms) * 0.5
        let img = NSImage(size: size, flipped: false) { rect in
            switch style {
            case .wave: drawWave(rect, levels, zones, connected)
            case .logo: drawLogo(rect, levels, zones, connected)
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    static func color(_ v: RGB) -> NSColor { NSColor(red: CGFloat(v.r) / 255, green: CGFloat(v.g) / 255, blue: CGFloat(v.b) / 255, alpha: 1) }

    /// 위아래 대칭 파형 2겹(뒤=고음, 앞=저음) + 가운데 밝은 선.
    private static func drawWave(_ rect: NSRect, _ levels: AudioLevels, _ zones: ZoneColors, _ connected: Bool) {
        let mid = rect.midY, maxAmp = rect.height / 2 - 1
        let dark = !connected || zones.zones.allSatisfy { $0 == .off }
        let ordered = [zones.zones[2], zones.zones[0], zones.zones[1], zones.zones[3]]
        let lineColors: [NSColor] = dark ? [.gray, .gray] : ordered.map(color)
        let cg = NSGraphicsContext.current!.cgContext
        let rear = dark ? [NSColor.gray, .gray] : [color(zones.zones[2]), color(zones.zones[3])]
        let front = dark ? [NSColor.gray, .gray] : [color(zones.zones[0]), color(zones.zones[1])]
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
            cg.saveGState(); cg.addPath(path); cg.clip()
            NSGradient(colors: l.colors.map { $0.withAlphaComponent(l.alpha) })!
                .draw(from: NSPoint(x: 0, y: mid), to: NSPoint(x: rect.width, y: mid), options: [])
            cg.restoreGState()
        }
        cg.saveGState()
        cg.addRect(CGRect(x: 1, y: mid - 0.5, width: rect.width - 2, height: 1)); cg.clip()
        NSGradient(colors: lineColors)!.draw(from: NSPoint(x: 0, y: mid), to: NSPoint(x: rect.width, y: mid), options: [])
        cg.restoreGState()
    }

    /// 뒤 레이어: 존 색으로 빛나는 글로우 + 원형 파형. 앞 레이어: G 글리프에 좌→우 존 색 그라데이션.
    private static func drawLogo(_ rect: NSRect, _ levels: AudioLevels, _ zones: ZoneColors, _ connected: Bool) {
        let cg = NSGraphicsContext.current!.cgContext
        let dark = !connected || zones.zones.allSatisfy { $0 == .off }
        let ordered = [zones.zones[2], zones.zones[0], zones.zones[1], zones.zones[3]]
        let colors: [NSColor] = dark ? [.gray, .gray] : ordered.map(color)
        let avg = dark ? NSColor.gray : color(RGB(
            UInt8(zones.zones.map { Int($0.r) }.reduce(0, +) / 4),
            UInt8(zones.zones.map { Int($0.g) }.reduce(0, +) / 4),
            UInt8(zones.zones.map { Int($0.b) }.reduce(0, +) / 4)))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let level = CGFloat(min(1, levels.rms * 6.4))   // ×2 극대화
        let maxR = min(rect.width, rect.height) / 2 - 1   // 아이콘 밖으로 안 나가게

        // 뒤 레이어 — 글로우 (무음이면 거의 0, 소리 크면 크게)
        cg.saveGState()
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [avg.withAlphaComponent(0.25 + 0.65 * level).cgColor, avg.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
        cg.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: min(maxR + 2, rect.width * (0.12 + 0.5 * level)), options: [])
        cg.restoreGState()

        // 뒤 레이어 — 원형 파형. 무음: 중앙 작은 점(반경 ~1.3px). 소리: 글리프를 넘어 커짐.
        let baseR = min(maxR, rect.width * (0.055 + 0.42 * level))
        let ring = CGMutablePath()
        let n = 48
        for i in 0...n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            let wob = level * baseR * 0.55 * sin(a * 5 + phase * 1.4)   // 흔들림도 소리에 비례
            let r = min(maxR, max(0.6, baseR + wob))
            let pt = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            i == 0 ? ring.move(to: pt) : ring.addLine(to: pt)
        }
        ring.closeSubpath()
        cg.saveGState()
        cg.addPath(ring); cg.setLineWidth(1.0 + 1.6 * level); cg.replacePathWithStrokedPath(); cg.clip()
        NSGradient(colors: colors + colors.reversed())!.draw(in: rect, angle: phase * 20)
        cg.restoreGState()

        // 앞 레이어 — G 글리프에 좌→우 존 색 그라데이션
        guard let glyph = glyph else { return }
        let gh = min(rect.height - 2, rect.height * (0.55 + 0.30 * level)), gw = gh * (glyph.size.width / glyph.size.height)   // 링(maxR)보다 살짝 작게 → 링이 로고를 넘음
        let grect = CGRect(x: center.x - gw / 2, y: center.y - gh / 2, width: gw, height: gh)
        cg.saveGState()
        if let cgimg = glyph.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cg.clip(to: grect, mask: cgimg)
            if dark {
                NSColor.gray.setFill(); cg.fill(grect)
            } else {
                NSGradient(colors: colors)!.draw(from: NSPoint(x: grect.minX, y: 0), to: NSPoint(x: grect.maxX, y: 0), options: [])
            }
        }
        cg.restoreGState()
    }
}
