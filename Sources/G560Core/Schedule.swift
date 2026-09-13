import Foundation

public struct ScheduleRule: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    public var weekdays: Set<Int>      // Calendar weekday: 1=일 … 7=토
    public var fromProfileID: UUID?    // 이 시각 전까지의 프로필 (표시·문서용, 사용자가 지정)
    public var profileID: UUID         // 이 시각부터의 프로필
    public var enabled: Bool

    public init(id: UUID = UUID(), hour: Int, minute: Int, weekdays: Set<Int> = Set(1...7),
                fromProfileID: UUID? = nil, profileID: UUID, enabled: Bool = true) {
        self.id = id; self.hour = hour; self.minute = minute; self.weekdays = weekdays
        self.fromProfileID = fromProfileID; self.profileID = profileID; self.enabled = enabled
    }
}

public enum Schedule {
    public struct Firing: Equatable, Sendable { public let rule: ScheduleRule; public let at: Date }

    /// `now` 기준으로 가장 최근에 발동했어야 할 규칙 (지난 7일 안에서). 없으면 nil.
    public static func activeRule(_ rules: [ScheduleRule], at now: Date, calendar: Calendar = .current) -> ScheduleRule? {
        activeFiring(rules, at: now, calendar: calendar)?.rule
    }

    /// 규칙 + 그 발동 시각. 같은 규칙이라도 시각을 고치면 다른 Firing.
    public static func activeFiring(_ rules: [ScheduleRule], at now: Date, calendar: Calendar = .current) -> Firing? {
        var best: (Date, ScheduleRule)?
        for r in rules where r.enabled && !r.weekdays.isEmpty {
            for back in 0..<8 {
                guard let day = calendar.date(byAdding: .day, value: -back, to: now),
                      r.weekdays.contains(calendar.component(.weekday, from: day)),
                      let fire = calendar.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day),
                      fire <= now else { continue }
                if best == nil || fire > best!.0 { best = (fire, r) }
                break   // 이 규칙의 가장 최근 발동 시각 확보
            }
        }
        return best.map { Firing(rule: $0.1, at: $0.0) }
    }
}
