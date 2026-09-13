import SwiftUI
import G560Core

/// 세로 EQ 슬라이더 (드래그, 정수 스냅)
struct VerticalSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let height: CGFloat

    func y(_ v: Int) -> CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        return height - CGFloat(v - range.lowerBound) / span * height
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.quaternary).frame(width: 2, height: height)
            Circle().fill(Color.accentColor).frame(width: 12, height: 12).offset(y: y(value) - 6)
        }
        .frame(width: 24, height: height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let span = CGFloat(range.upperBound - range.lowerBound)
            let v = range.upperBound - Int(((g.location.y / height) * span).rounded())
            value = min(max(v, range.lowerBound), range.upperBound)
        })
    }
}

struct OutputTab: View {
    @Environment(AppState.self) var state
    @State private var formats = OutputFormat.available()
    @State private var format = OutputFormat.current()
    @State private var formatError = false

    let eqHeight: CGFloat = 120

    var body: some View {
        @Bindable var state = state
        Form {
            Section("출력") {
                SliderRow(label: "볼륨", value: $state.draft.volume, range: 0...1, format: { "\(Int(($0 * 100).rounded()))" })
                SliderRow(label: "서브우퍼", value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0.rounded()) }),
                          range: 0...100)
            }
            Section("오디오 포맷") {
                Picker("포맷", selection: Binding(get: { format?.id ?? "" }, set: { id in
                    if let f = formats.first(where: { $0.id == id }) {
                        formatError = !OutputFormat.set(f); format = OutputFormat.current()
                    }
                })) {
                    ForEach(formats) { Text($0.label).tag($0.id) }
                }
                .disabled(formats.isEmpty)
                Text(formatError ? "장치가 이 포맷을 거부했습니다." : "오디오 MIDI 설정과 같은 장치 설정입니다. 즉시 적용되며 프로필에 저장되지 않습니다.")
                    .font(.caption).foregroundStyle(formatError ? .red : .secondary)
            }
            Section("Equalizer") {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        gridLine("+\(G560.eqRange.upperBound)")
                        Spacer()
                        gridLine("0")
                        Spacer()
                        gridLine("\(G560.eqRange.lowerBound)")
                    }
                    .frame(height: eqHeight).padding(.top, 16)
                    HStack(alignment: .top, spacing: 0) {
                        Spacer().frame(width: 30)
                        ForEach(0..<G560.eqBands, id: \.self) { i in
                            VStack(spacing: 3) {
                                Text("\(state.draft.eq[i] > 0 ? "+" : "")\(state.draft.eq[i])")
                                    .font(.caption2).monospacedDigit().frame(height: 12)
                                VerticalSlider(value: $state.draft.eq[i], range: G560.eqRange, height: eqHeight)
                                Text(G560.eqFrequencies[i] >= 1000 ? "\(G560.eqFrequencies[i] / 1000)k" : "\(G560.eqFrequencies[i])")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: eqHeight + 40)
                .padding(.vertical, 4)

                Picker("Preset", selection: Binding(get: { EQPresets.name(for: state.draft.eq) ?? "Custom" },
                                                    set: { n in if let g = EQPresets.all.first(where: { $0.name == n })?.gains { state.draft.eq = g } })) {
                    Text("Custom").tag("Custom")
                    Divider()
                    ForEach(EQPresets.all, id: \.name) { Text($0.name).tag($0.name) }
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
        .onAppear { formats = OutputFormat.available(); format = OutputFormat.current() }
    }

    func gridLine(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }
}
