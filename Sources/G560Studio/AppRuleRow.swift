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

    func time(_ keyPath: WritableKeyPath<AppRule, Int?>, default def: Int) -> Binding<Date> {
        Binding(get: { let m = rule[keyPath: keyPath] ?? def
                       return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date() },
                set: { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                       rule[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: $rule.enabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                Text(rule.appName).lineLimit(1)
                Spacer()
                Toggle("시간 제한", isOn: Binding(get: { rule.hasTimeLimit }, set: { on in
                    rule.startMinute = on ? 22 * 60 : nil; rule.endMinute = on ? 8 * 60 : nil
                })).toggleStyle(.checkbox)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: $rule.profileID) {
                    ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(width: 120)
                Button { onDelete() } label: { Image(systemName: "trash") }.controlSize(.small)
            }
            if rule.hasTimeLimit {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { d in
                        let on = rule.weekdays.contains(d)
                        Button(ScheduleTab.dayNames[d - 1]) { if on { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) } }
                            .buttonStyle(.bordered).tint(on ? .accentColor : nil)
                            .foregroundStyle(on ? Color.accentColor : .secondary).frame(width: 34)
                    }
                    Spacer()
                    DatePicker("", selection: time(\.startMinute, default: 22 * 60), displayedComponents: .hourAndMinute).labelsHidden()
                    Text("~").foregroundStyle(.secondary)
                    DatePicker("", selection: time(\.endMinute, default: 8 * 60), displayedComponents: .hourAndMinute).labelsHidden()
                }
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 2)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}
