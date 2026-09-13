import SwiftUI
import G560Core

struct QuickPanel: View {
    @Environment(AppState.self) var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(state.connected ? .green : .red).frame(width: 8, height: 8)
                Text(state.connected ? "Logitech G560 연결됨" : "Logitech G560 연결 안 됨").font(.caption)
                Spacer()
                Toggle("조명", isOn: Binding(get: { state.engine.enabled }, set: { state.engine.enabled = $0 }))
                    .toggleStyle(.switch).controlSize(.mini)
            }
            if let e = state.deviceError ?? state.audioError {
                Text(e).font(.caption2).foregroundStyle(.red)
            }
            Divider()
            Text("프로필").font(.caption).foregroundStyle(.secondary)
            ForEach(state.store.profiles) { p in
                Button { state.apply(p) } label: {
                    HStack {
                        Text(p.name)
                        Spacer()
                        if p.id == state.store.activeID { Image(systemName: "checkmark") }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider()
            LabeledContent("볼륨 \(Int(state.draft.volume * 100))") {
                Slider(value: $state.draft.volume, in: 0...1) { if !$0 { state.applyDraft() } }
            }
            LabeledContent("우퍼 \(state.draft.woofer)") {
                Slider(value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0) }),
                       in: 0...100, step: 1) { if !$0 { state.applyDraft() } }
            }
            Divider()
            HStack {
                SettingsLink { Text("설정 열기…") }
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
