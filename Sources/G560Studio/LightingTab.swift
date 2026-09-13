import SwiftUI
import G560Core

struct LightingTab: View {
    @Environment(AppState.self) var state
    /// 마지막 비-끄기 설정. 모드를 바꿨다 돌아와도 같은 파라미터로 복원 → 불필요한 "변경 사항" 방지.
    @State private var memo: LightingConfig = .off
    @State private var lastRainbow = 0.05
    @State private var lastCustom = ZoneColors(all: RGB(255, 255, 255))

    enum Effect: String, CaseIterable { case fixed = "고정", breathing = "브리딩", sound = "사운드 반응", screen = "화면 샘플러", dynamic = "다이나믹 샘플러" }
    enum Source: String, CaseIterable { case rainbow = "레인보우", custom = "존별 색 지정" }

    var cfg: LightingConfig { state.draft.lighting }
    var isOn: Bool { cfg != .off }
    var effect: Effect {
        switch cfg { case .breathing: .breathing; case .soundReactive: .sound; case .screenSampler(let o): o.audio ? .dynamic : .screen; default: .fixed }
    }
    var screenOptions: ScreenOptions {
        if case .screenSampler(let o) = cfg { return o }
        if case .screenSampler(let o) = memo { return o }
        return ScreenOptions()
    }
    var palette: Palette {
        switch cfg {
        case .fixed(let p), .breathing(let p, _), .soundReactive(let p, _, _): return p
        case .off, .screenSampler:
            switch memo { case .fixed(let p), .breathing(let p, _), .soundReactive(let p, _, _): return p; default: return .rainbow(speed: lastRainbow) }
        }
    }
    var source: Source { if case .custom = palette { .custom } else { .rainbow } }
    var customColors: ZoneColors { if case .custom(let z) = palette { z } else { lastCustom } }

    func rebuild(on: Bool? = nil, effect e: Effect? = nil, palette p: Palette? = nil) {
        let on = on ?? isOn, e = e ?? (isOn ? effect : memoEffect), p = p ?? palette
        guard on else { state.draft.lighting = .off; return }
        switch e {
        case .fixed: state.draft.lighting = .fixed(p)
        case .breathing:
            if case .breathing(_, let per) = cfg { state.draft.lighting = .breathing(p, period: per) }
            else if case .breathing(_, let per) = memo { state.draft.lighting = .breathing(p, period: per) }
            else { state.draft.lighting = .breathing(p, period: 3) }
        case .sound:
            if case .soundReactive(_, let s, let b) = cfg { state.draft.lighting = .soundReactive(p, sensitivity: s, split: b) }
            else if case .soundReactive(_, let s, let b) = memo { state.draft.lighting = .soundReactive(p, sensitivity: s, split: b) }
            else { state.draft.lighting = .soundReactive(p, sensitivity: 1.5, split: .none) }
        case .screen, .dynamic:
            var o = screenOptions; o.audio = (e == .dynamic)
            state.draft.lighting = .screenSampler(o)
        }
        memo = state.draft.lighting
        if case .rainbow(let sp) = p { lastRainbow = sp } else if case .custom(let z) = p { lastCustom = z }
    }
    var memoEffect: Effect { switch memo { case .breathing: .breathing; case .soundReactive: .sound; case .screenSampler(let o): o.audio ? .dynamic : .screen; default: .fixed } }
    func setColor(_ zone: Int, _ c: RGB) { var z = customColors; z.zones[zone] = c; rebuild(palette: .custom(z)) }

    var body: some View {
        Form {
            Section {
                SpeakerRender()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("LightSync") {
                Toggle("조명 켜기", isOn: Binding(get: { isOn }, set: { rebuild(on: $0) }))
                if isOn {
                    SliderRow(label: "밝기", value: Binding(get: { Double(state.draft.brightness) }, set: { state.draft.brightness = Int($0.rounded()) }),
                              range: 0...100)
                    Picker("효과", selection: Binding(get: { effect }, set: { rebuild(effect: $0) })) {
                        ForEach(Effect.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    if case .breathing(let p, let per) = cfg {
                        SliderRow(label: "주기", value: Binding(get: { per }, set: { state.draft.lighting = .breathing(p, period: $0) }),
                                  range: 1...10, format: { String(format: "%.1f초", $0) })
                    }
                    if case .soundReactive(let p, let s, let b) = cfg {
                        AutoSliderRow(label: "감도", value: Binding(get: { s }, set: { state.draft.lighting = .soundReactive(p, sensitivity: $0, split: b) }),
                                      range: 0.5...4, manualDefault: 1.5, format: { String(format: "%.1f", $0) })
                        Picker("대역 분리", selection: Binding(get: { b }, set: { state.draft.lighting = .soundReactive(p, sensitivity: s, split: $0) })) {
                            Text("없음").tag(BandSplit.none)
                            Text("저음은 뒤, 고음은 앞").tag(BandSplit.bassRear)
                            Text("저음은 앞, 고음은 뒤").tag(BandSplit.bassFront)
                        }
                    }
                }
            }
            if case .screenSampler(let o) = cfg {
                Section(o.audio ? "다이나믹 샘플러 (색은 화면, 밝기는 소리)" : "화면 샘플러") {
                    LabeledContent("화면 기록 권한") {
                        if ScreenSampler.hasPermission { Text("허용됨").foregroundStyle(.secondary) }
                        else {
                            HStack {
                                Text("없음").foregroundStyle(.red)
                                Button("권한 요청…") { ScreenSampler.requestPermission() }
                            }
                        }
                    }
                    Picker("모니터", selection: Binding(get: { o.display ?? 0 }, set: { var n = o; n.display = $0 == 0 ? nil : $0; state.draft.lighting = .screenSampler(n) })) {
                        Text("메인 디스플레이").tag(UInt32(0))
                        ForEach(ScreenSampler.displays()) { disp in Text(disp.name + (disp.isMain ? " (메인)" : "")).tag(disp.id) }
                    }
                    SliderRow(label: "강도", value: Binding(get: { o.boost }, set: { var n = o; n.boost = $0; state.draft.lighting = .screenSampler(n) }),
                              range: 0.5...2, format: { String(format: "%.1f", $0) })
                    if o.audio {
                        AutoSliderRow(label: "감도", value: Binding(get: { o.sensitivity }, set: { var n = o; n.sensitivity = $0; state.draft.lighting = .screenSampler(n) }),
                                      range: 0.5...4, manualDefault: 1.5, format: { String(format: "%.1f", $0) })
                    }
                    Picker("샘플 위치", selection: Binding(get: { Int((o.inset * 10).rounded()) }, set: { var n = o; n.inset = Double($0) / 10; state.draft.lighting = .screenSampler(n) })) {
                        Text("가장자리").tag(0)
                        ForEach([1, 2, 3, 4], id: \.self) { Text("안쪽 \($0 * 10)%").tag($0) }
                    }
                    if let e = state.engine.screen.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                    LabeledContent("샘플 구역") { EdgeDiagram(inset: o.inset) }
                }
            } else if isOn {
                Section("색상") {
                    Picker("색상", selection: Binding(get: { source }, set: {
                        rebuild(palette: $0 == .rainbow ? .rainbow(speed: lastRainbow) : .custom(lastCustom))
                    })) { ForEach(Source.allCases, id: \.self) { Text($0.rawValue) } }
                    if case .rainbow(let sp) = palette {
                        AutoSliderRow(label: "색 변화 속도", value: Binding(get: { sp }, set: { rebuild(palette: .rainbow(speed: $0)) }),
                                      range: 0.02...2, manualDefault: 0.05, format: { String(format: "%.2f", $0) })
                    } else {
                        ForEach(0..<G560.zoneCount, id: \.self) { z in
                            let c = customColors.zones[z]
                            LabeledContent(G560.zoneNames[z]) {
                                HStack(spacing: 10) {
                                    Text("#\(c.hex)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255) },
                                        set: { col in
                                            let n = NSColor(col).usingColorSpace(.sRGB)!
                                            setColor(z, RGB(UInt8(n.redComponent * 255), UInt8(n.greenComponent * 255), UInt8(n.blueComponent * 255)))
                                        }), supportsOpacity: false).labelsHidden()
                                }
                            }
                        }
                        LabeledContent("") {
                            Button("모든 존을 '좌 앞' 색으로") { rebuild(palette: .custom(ZoneColors(all: customColors.zones[0]))) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if cfg != .off { memo = cfg } else if state.applied.lighting != .off { memo = state.applied.lighting }
            if case .rainbow(let sp) = palette { lastRainbow = sp } else if case .custom(let z) = palette { lastCustom = z }
        }
    }
}


/// 밝은 화면 모형 + 네 모서리 브래킷(ㄱ/ㄴ)이 샘플 구역. inset 에 따라 안쪽으로 이동.
struct EdgeDiagram: View {
    @Environment(AppState.self) var state
    var colors: ZoneColors { state.zoneColors }
    let inset: Double
    static let size = CGSize(width: 260, height: 146)

    func c(_ z: Int) -> Color { let v = colors.zones[z]; return Color(red: Double(v.r) / 255, green: Double(v.g) / 255, blue: Double(v.b) / 255) }

    /// 모서리 브래킷: corner 0=좌상 1=우상 2=좌하 3=우하
    func bracket(_ corner: Int, in r: CGRect, len: CGFloat) -> Path {
        var p = Path()
        let x = (corner % 2 == 0) ? r.minX : r.maxX, y = (corner < 2) ? r.minY : r.maxY
        let dx: CGFloat = (corner % 2 == 0) ? len : -len, dy: CGFloat = (corner < 2) ? len : -len
        p.move(to: CGPoint(x: x, y: y + dy)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx, y: y))
        return p
    }

    var body: some View {
        let S = Self.size
        let pad: CGFloat = 8
        let off = CGFloat(inset) * (S.height - pad * 2)
        let r = CGRect(x: pad + off * 0.6, y: pad + off, width: S.width - pad * 2 - off * 1.2, height: S.height - pad * 2 - off * 2)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor))
            RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1)
            if inset >= 0.4 {
                // 40%: 위/아래 띠가 겹쳐 사실상 중앙 — 좌/우 중앙 하나씩 ([ ])
                ForEach([(2, true), (3, false)], id: \.0) { z, left in
                    let x = left ? r.minX : r.maxX, dx: CGFloat = left ? 14 : -14
                    Path { p in
                        p.move(to: CGPoint(x: x + dx, y: r.midY - 22)); p.addLine(to: CGPoint(x: x, y: r.midY - 22))
                        p.addLine(to: CGPoint(x: x, y: r.midY + 22)); p.addLine(to: CGPoint(x: x + dx, y: r.midY + 22))
                    }.stroke(c(z), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    Text(left ? "좌 중앙" : "우 중앙").font(.caption2).foregroundStyle(.secondary)
                        .position(x: left ? r.minX + 30 : r.maxX - 30, y: r.midY)
                }
            } else {
            // 존: 2 좌뒤=좌상, 3 우뒤=우상, 0 좌앞=좌하, 1 우앞=우하
            ForEach([(2, 0), (3, 1), (0, 2), (1, 3)], id: \.0) { z, corner in
                let len: CGFloat = 40
                bracket(corner, in: r, len: len).stroke(c(z), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Text(G560.zoneNames[z]).font(.caption2).foregroundStyle(.secondary)
                    .position(x: corner % 2 == 0 ? r.minX + len * 0.55 : r.maxX - len * 0.55,   // 브래킷 안쪽 가운데
                              y: corner < 2 ? r.minY + len * 0.5 : r.maxY - len * 0.5)
            }
            }
        }
        .frame(width: S.width, height: S.height)
    }
}


/// 슬라이더 + "자동" 토글. 자동이면 값을 0(센티널)으로 저장하고 슬라이더를 비활성화.
struct AutoSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let manualDefault: Double
    var format: (Double) -> String
    @State private var lastManual: Double = 0

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Toggle("자동", isOn: Binding(get: { value <= 0 }, set: { auto in
                    if auto { lastManual = value; value = 0 } else { value = lastManual > 0 ? lastManual : manualDefault }
                })).toggleStyle(.checkbox)
                Slider(value: Binding(get: { value <= 0 ? (lastManual > 0 ? lastManual : manualDefault) : value }, set: { value = $0 }), in: range)
                    .frame(width: 140).disabled(value <= 0)
                Text(value <= 0 ? "자동" : format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }
}
