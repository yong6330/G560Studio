import SwiftUI
import G560Core

struct AppRuleRow: View {
    @Environment(AppState.self) var state
    @Binding var rule: AppRule
    let onDelete: () -> Void

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            Text(rule.appName).lineLimit(1)
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("", selection: $rule.profileID) {
                ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
            }.labelsHidden().frame(width: 140)
            Button { onDelete() } label: { Image(systemName: "trash") }.controlSize(.small)
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}
