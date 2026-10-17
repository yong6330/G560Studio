import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var state
    @State private var tab = 0
    @State private var pendingTab: Int?     // 변경 사항 있을 때 이동하려던 탭

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: Binding(get: { tab }, set: { new in
                if new != tab && state.hasChanges { pendingTab = new } else { tab = new }
            })) {
                LightingTab().tabItem { Label("조명", systemImage: "lightbulb") }.tag(0)
                OutputTab().tabItem { Label("출력", systemImage: "speaker.wave.2") }.tag(1)
                ProfilesTab().tabItem { Label("프로필", systemImage: "person.crop.rectangle.stack") }.tag(2)
            }
            .alert("적용되지 않은 변경 사항이 있습니다", isPresented: Binding(get: { pendingTab != nil }, set: { if !$0 { pendingTab = nil } })) {
                Button("동기화") { state.sync(); if let t = pendingTab { tab = t }; pendingTab = nil }
                Button("버리기", role: .destructive) { state.discardChanges(); if let t = pendingTab { tab = t }; pendingTab = nil }
                Button("취소", role: .cancel) { pendingTab = nil }
            } message: { Text("동기화하면 장치에 적용하고 저장합니다.") }
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
        .frame(minWidth: 440, minHeight: 520)
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
