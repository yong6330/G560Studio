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

    static let presets: [(String, [Int])] = [
        ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Bass Boost", [5, 4, 3, 1, 0, 0, 0, 0, 0, 0]),
        ("Night", [-8, -6, -4, -2, 0, 0, 0, 0, 0, 0]),
        ("Vocal", [-2, -1, 0, 1, 3, 3, 2, 1, 0, 0]),
        ("Treble", [0, 0, 0, 0, 0, 1, 2, 3, 4, 4]),
        ("Loudness", [4, 3, 1, 0, -1, -1, 0, 1, 3, 4]),
    ]
    let eqHeight: CGFloat = 120

    var body: some View {
        @Bindable var state = state
        Form {
            Section("출력") {
                SliderRow(label: "볼륨", value: $state.draft.volume, range: 0...1, format: { "\(Int(($0 * 100).rounded()))" })
                SliderRow(label: "서브우퍼", value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0.rounded()) }),
                          range: 0...100)
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

                LabeledContent("Preset") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 6), count: 3), spacing: 6) {
                        ForEach(Self.presets, id: \.0) { name, g in
                            if state.draft.eq == g {
                                Button { } label: { Text(name).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                            } else {
                                Button { state.draft.eq = g } label: { Text(name).frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    func gridLine(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }
}
