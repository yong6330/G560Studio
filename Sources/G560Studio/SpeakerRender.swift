import SwiftUI
import G560Core

/// 어두운 무대 위의 G560 실사(Assets/g560.png) + 존 위치별 글로우.
struct SpeakerRender: View {
    let zones: ZoneColors
    let levels: AudioLevels
    let connected: Bool

    static let photo: NSImage? = Bundle.main.url(forResource: "g560", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    /// 사진(뒤쪽 3/4 각도) 기준 존 위치 (정규화 좌표, 크기). 0=좌앞 1=우앞 2=좌뒤 3=우뒤
    static let spots: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
        (0.13, 0.58, 0.16, 0.22), (0.56, 0.28, 0.18, 0.22), (0.42, 0.66, 0.24, 0.26), (0.62, 0.57, 0.18, 0.16),
    ]

    func color(_ z: Int) -> Color {
        guard connected else { return .gray.opacity(0.2) }
        let c = zones.zones[z]
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.07, green: 0.07, blue: 0.09))
                GeometryReader { g in
                    let W = g.size.width, H = g.size.height
                    ZStack {
                        if let photo = Self.photo {
                            Image(nsImage: photo).resizable().scaledToFit().frame(width: W, height: H).padding(14)
                        }
                        ForEach([1, 2, 3], id: \.self) { z in   // 존 0(좌 앞)은 이 각도에서 안 보임
                            let s = Self.spots[z]
                            Ellipse().fill(color(z))
                                .frame(width: s.w * W, height: s.h * H)
                                .blur(radius: 22)
                                .blendMode(.plusLighter)
                                .opacity(0.85)
                                .position(x: s.x * W, y: s.y * H)
                        }
                    }
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 10))

        }
    }
}
