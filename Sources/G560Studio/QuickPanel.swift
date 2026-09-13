import SwiftUI
import G560Core
import ServiceManagement

/// 메뉴바 빠른 패널 — Tailscale 스타일: 헤더(이름/상태 + 토글), 메뉴 행, 구분선, 단축키.
struct QuickPanel: View {
    @Environment(AppState.self) var state
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("G560Studio").font(.system(size: 15, weight: .semibold))
                    Text(state.connected ? "Logitech G560 연결됨" : "Logitech G560 연결 안 됨")
                        .font(.callout).foregroundStyle(state.connected ? .secondary : Color.red)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { state.engine.enabled }, set: { state.engine.enabled = $0 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)

            if let e = state.deviceError ?? state.audioError {
                Text(e).font(.caption2).foregroundStyle(.red).padding(.horizontal, 14).padding(.bottom, 6)
            }

            MenuSeparator()

            // 프로필
            Text("프로필").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 4)
            ForEach(state.store.profiles) { p in
                MenuRow(title: p.name, trailing: p.id == state.store.activeID ? "checkmark" : nil) { state.apply(p) }
            }

            MenuSeparator()

            // 출력 (슬라이더 행)
            SliderMenuRow(title: "볼륨", value: Binding(get: { state.draft.volume }, set: { state.draft.volume = $0 }),
                          range: 0...1, display: "\(Int((state.draft.volume * 100).rounded()))") { state.quickSet(volume: state.draft.volume) }
            SliderMenuRow(title: "서브우퍼", value: Binding(get: { Double(state.draft.woofer) }, set: { state.draft.woofer = Int($0.rounded()) }),
                          range: 0...100, display: "\(state.draft.woofer)") { state.quickSet(woofer: state.draft.woofer) }

            HStack(spacing: 10) {
                Text("EQ").frame(width: 56, alignment: .leading)
                Picker("", selection: Binding(get: { EQPresets.name(for: state.draft.eq) ?? "Custom" },
                                              set: { n in if let g = EQPresets.all.first(where: { $0.name == n })?.gains { state.quickSet(eq: g) } })) {
                    Text("Custom").tag("Custom")
                    Divider()
                    ForEach(EQPresets.all, id: \.name) { Text($0.name).tag($0.name) }
                }.labelsHidden()
            }
            .padding(.horizontal, 15).padding(.vertical, 4)

            MenuSeparator()

            LoginItemRow()
            MenuRow(title: "설정…", shortcut: "⌘,") {
                NSApp.keyWindow?.close()          // 메뉴바 패널 닫기
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "종료", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
        .frame(width: 300)
    }
}

struct MenuSeparator: View {
    var body: some View { Divider().padding(.horizontal, 10).padding(.vertical, 5) }
}

/// 메뉴 항목처럼 보이는 행: 호버 시 강조, 우측에 체크/단축키.
struct MenuRow: View {
    let title: String
    var trailing: String? = nil      // SF Symbol
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let t = trailing { Image(systemName: t).font(.caption.bold()) }
                if let s = shortcut { Text(s).foregroundStyle(hover ? .white.opacity(0.8) : .secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(hover ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { hover = $0 }
    }
}

/// 슬라이더가 들어간 메뉴 행. 놓을 때만 onCommit.
struct SliderMenuRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 56, alignment: .leading)
            Slider(value: $value, in: range) { if !$0 { onCommit() } }
            Text(display).monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 15).padding(.vertical, 4)
    }
}

/// 로그인 시 시작 (SMAppService). 번들이 /Applications 에 있어야 안정적.
struct LoginItemRow: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    var body: some View {
        HStack {
            Text("로그인 시 시작")
            Spacer()
            Toggle("", isOn: Binding(get: { enabled }, set: { on in
                do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); enabled = on }
                catch { enabled = SMAppService.mainApp.status == .enabled }
            })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.horizontal, 15).padding(.vertical, 4)
    }
}
