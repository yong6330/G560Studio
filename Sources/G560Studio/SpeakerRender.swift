import SwiftUI
import G560Core

/// 어두운 무대 위의 G560 실사(Assets/g560.png).
/// 글로우는 사진 *뒤*에 깔아 몸체에 묻지 않고 주변으로만 번지게 하고, 실제 LED 렌즈 위치에만 작은 하이라이트를 얹는다.
struct SpeakerRender: View {
    @Environment(AppState.self) var state     // 여기서 직접 읽어야 부모 Form이 매 프레임 재렌더되지 않는다
    var zones: ZoneColors { state.zoneColors }
    var connected: Bool { state.connected }

    static let photo: NSImage? = Bundle.main.url(forResource: "g560", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    static let aspect: CGFloat = 1200.0 / 851.0

    struct Spot { let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, blur: CGFloat, alpha: CGFloat }
    /// 사진 프레임 기준 정규화 좌표. 존: 0=좌앞 1=우앞 2=좌뒤 3=우뒤
    static let spill: [Spot] = [                       // 사진 뒤 — 배경/바닥으로 번지는 빛
        Spot(x: 0.10, y: 0.60, w: 0.20, h: 0.30, blur: 26, alpha: 0.55),   // 좌 앞 (가려짐, 왼쪽으로 새는 빛)
        Spot(x: 0.60, y: 0.62, w: 0.26, h: 0.16, blur: 22, alpha: 0.70),   // 우 앞 (아래로 바닥에 비침)
        Spot(x: 0.40, y: 0.72, w: 0.30, h: 0.26, blur: 26, alpha: 0.75),   // 좌 뒤 (렌즈 주변 바닥)
        Spot(x: 0.86, y: 0.44, w: 0.22, h: 0.36, blur: 26, alpha: 0.60),   // 우 뒤 (가려짐, 오른쪽 뒤로 새는 빛)
    ]
    static let lens: [Int: Spot] = [                   // 사진 위 — 실제 보이는 LED 면만
        2: Spot(x: 0.405, y: 0.655, w: 0.19, h: 0.27, blur: 6, alpha: 0.9),   // 좌 뒤 렌즈 링
        1: Spot(x: 0.615, y: 0.545, w: 0.13, h: 0.06, blur: 5, alpha: 0.9),   // 우 앞 밑면 빛
    ]

    func color(_ z: Int) -> Color {
        guard connected else { return .gray.opacity(0.15) }
        let c = zones.zones[z]
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    func glow(_ s: Spot, _ z: Int, in f: CGRect) -> some View {
        Ellipse().fill(color(z))
            .frame(width: s.w * f.width, height: s.h * f.height)
            .blur(radius: s.blur)
            .opacity(s.alpha)
            .position(x: f.minX + s.x * f.width, y: f.minY + s.y * f.height)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.07, green: 0.07, blue: 0.09))
            GeometryReader { g in
                // 사진이 실제로 그려지는 프레임 (scaledToFit, 패딩 14)
                let pad: CGFloat = 14
                let avail = CGSize(width: g.size.width - pad * 2, height: g.size.height - pad * 2)
                let w = min(avail.width, avail.height * Self.aspect), h = w / Self.aspect
                let f = CGRect(x: (g.size.width - w) / 2, y: (g.size.height - h) / 2, width: w, height: h)
                ZStack {
                    ForEach(0..<G560.zoneCount, id: \.self) { z in glow(Self.spill[z], z, in: f) }
                    if let photo = Self.photo {
                        Image(nsImage: photo).resizable().frame(width: w, height: h).position(x: f.midX, y: f.midY)
                    }
                    ForEach(Array(Self.lens.keys.sorted()), id: \.self) { z in
                        glow(Self.lens[z]!, z, in: f).blendMode(.plusLighter)
                    }
                }
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
