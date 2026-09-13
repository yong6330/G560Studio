import SwiftUI
import G560Core

enum ScheduleTab { static let dayNames = ["일", "월", "화", "수", "목", "금", "토"] }

struct ScheduleRow: View {
    @Environment(AppState.self) var state
    @Binding var rule: ScheduleRule
    let onChange: () -> Void
    let onDelete: () -> Void

    var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date() },
                set: { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                       rule.hour = c.hour ?? 0; rule.minute = c.minute ?? 0; onChange() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { rule.enabled }, set: { rule.enabled = $0; onChange() })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
                Picker("", selection: Binding(get: { rule.fromProfileID ?? state.store.profiles[0].id }, set: { rule.fromProfileID = $0; onChange() })) {
                    ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(width: 120)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { rule.profileID }, set: { rule.profileID = $0; onChange() })) {
                    ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(width: 120)
                Spacer()
                Button { onDelete() } label: { Image(systemName: "trash") }.controlSize(.small)
            }
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { d in
                    let on = rule.weekdays.contains(d)
                    Button(ScheduleTab.dayNames[d - 1]) {
                        if on { rule.weekdays.remove(d) } else { rule.weekdays.insert(d) }
                        onChange()
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : nil)
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .frame(width: 34)
                }
                Spacer()
                Button("매일") { rule.weekdays = Set(1...7); onChange() }.controlSize(.small)
                Button("평일") { rule.weekdays = [2, 3, 4, 5, 6]; onChange() }.controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}
