import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var state

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                LightingTab().tabItem { Label("조명", systemImage: "lightbulb") }
                OutputTab().tabItem { Label("출력", systemImage: "speaker.wave.2") }
                ProfilesTab().tabItem { Label("프로필", systemImage: "person.crop.rectangle.stack") }
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(state.connected ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(state.connected ? "Logitech G560 연결됨" : "Logitech G560 연결 안 됨")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(state.hasChanges ? "저장되지 않은 변경 사항" : "장치와 동기화됨")
                    .font(.callout).foregroundStyle(.tertiary)
                Button("동기화") { state.sync() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.hasChanges)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 560, height: 660)
    }
}

/// 라벨 좌측 · 값 · 슬라이더 우측 (grouped Form 행용)
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String = { "\(Int($0))" }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                if let step { Slider(value: $value, in: range, step: step).frame(width: 200) }
                else { Slider(value: $value, in: range).frame(width: 200) }
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }
}
