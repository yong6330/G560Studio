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
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { rule.enabled }, set: { rule.enabled = $0; onChange() })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
                Spacer(minLength: 0)
                Button("매일") { rule.weekdays = Set(1...7); onChange() }.controlSize(.small)
                Button("평일") { rule.weekdays = [2, 3, 4, 5, 6]; onChange() }.controlSize(.small)
                Button { onDelete() } label: { Image(systemName: "trash") }.controlSize(.small)
            }
            HStack(spacing: 6) {   // 폭이 모자라면 피커가 줄어든다 (고정 폭 금지)
                Picker("", selection: Binding(get: { rule.fromProfileID ?? state.store.profiles[0].id }, set: { rule.fromProfileID = $0; onChange() })) {
                    ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { rule.profileID }, set: { rule.profileID = $0; onChange() })) {
                    ForEach(state.store.profiles) { p in Text(p.name).tag(p.id) }
                }.labelsHidden().frame(maxWidth: .infinity)
            }
            WeekdayChips(days: $rule.weekdays, onChange: onChange)
        }
        .padding(.vertical, 2)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

/// 일~토 토글 칩. 폭에 맞춰 균등 분할(고정 폭 없음).
struct WeekdayChips: View {
    @Binding var days: Set<Int>
    var onChange: () -> Void = {}
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { d in
                let on = days.contains(d)
                Button(ScheduleTab.dayNames[d - 1]) {
                    if on { days.remove(d) } else { days.insert(d) }
                    onChange()
                }
                .buttonStyle(.bordered).controlSize(.small)
                .tint(on ? .accentColor : nil)
                .foregroundStyle(on ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
