import Foundation

/// 앱 규칙: 이 앱이 앞에 오면 프로필 전환. 선택적으로 요일·시간대 안에서만.
public struct AppRule: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var profileID: UUID
    public var enabled: Bool
    public var weekdays: Set<Int> = Set(1...7)     // Calendar weekday 1=일…7=토
    public var startMinute: Int? = nil             // 자정 기준 분. nil = 시간 제한 없음
    public var endMinute: Int? = nil               // start > end 면 자정을 넘는 구간

    enum CodingKeys: String, CodingKey { case id, bundleID, appName, profileID, enabled, weekdays, startMinute, endMinute }

    public init(id: UUID = UUID(), bundleID: String, appName: String, profileID: UUID, enabled: Bool = true,
                weekdays: Set<Int> = Set(1...7), startMinute: Int? = nil, endMinute: Int? = nil) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.profileID = profileID; self.enabled = enabled
        self.weekdays = weekdays; self.startMinute = startMinute; self.endMinute = endMinute
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); bundleID = try c.decode(String.self, forKey: .bundleID)
        appName = try c.decode(String.self, forKey: .appName); profileID = try c.decode(UUID.self, forKey: .profileID)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? Set(1...7)
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute)
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute)
    }

    public var hasTimeLimit: Bool { startMinute != nil && endMinute != nil }

    /// 지금 이 규칙이 유효한가 (요일 + 시간대). 자정을 넘는 구간은 전날 요일 기준으로도 본다.
    public func isActive(at now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let wd = calendar.component(.weekday, from: now)
        let m = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard let s = startMinute, let e = endMinute else { return weekdays.contains(wd) }
        if s <= e { return weekdays.contains(wd) && m >= s && m < e }
        // 자정 넘김: 오늘 s 이후이거나, 어제 시작한 구간의 e 이전
        if m >= s { return weekdays.contains(wd) }
        let yesterday = wd == 1 ? 7 : wd - 1
        return m < e && weekdays.contains(yesterday)
    }
}
