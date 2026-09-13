import SwiftUI
import G560Core

struct ScheduleTab: View {
    @Environment(AppState.self) var state
    static let dayNames = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Toggle("스케줄 사용", isOn: $state.draftScheduleEnabled)
                LabeledContent("적용 중인 규칙") {
                    if state.store.scheduleEnabled, let r = Schedule.activeRule(state.store.schedule, at: Date()),
                       let p = state.store.profiles.first(where: { $0.id == r.profileID }) {
                        let from = state.store.profiles.first { $0.id == r.fromProfileID }?.name ?? "—"
                        Text("\(String(format: "%02d:%02d", r.hour, r.minute))   \(from) → \(p.name)").foregroundStyle(.secondary)
                    } else { Text("없음").foregroundStyle(.secondary) }
                }
            }
            Section("규칙") {
                ForEach(state.draftSchedule) { rule in
                    ScheduleRow(rule: binding(for: rule.id)) { } onDelete: {
                        state.draftSchedule.removeAll { $0.id == rule.id }
                    }
                }
                if state.draftSchedule.isEmpty {
                    Text("규칙이 없습니다. 예: 22:00 매일 → 야간 프로필").foregroundStyle(.secondary)
                }
                LabeledContent("") {
                    Button("규칙 추가") {
                        let pid = state.store.activeID ?? state.store.profiles[0].id
                        state.draftSchedule.append(ScheduleRule(hour: 22, minute: 0, fromProfileID: pid, profileID: pid))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    func binding(for id: UUID) -> Binding<ScheduleRule> {
        Binding(get: { state.draftSchedule.first { $0.id == id } ?? ScheduleRule(hour: 0, minute: 0, profileID: id) },
                set: { r in if let i = state.draftSchedule.firstIndex(where: { $0.id == id }) { state.draftSchedule[i] = r } })
    }
}

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
