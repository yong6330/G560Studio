import XCTest
@testable import G560Core

final class ScheduleTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    let night = UUID(), day = UUID()
    // 2026-09-16 수요일
    func date(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))! }

    var rules: [ScheduleRule] {
        [ScheduleRule(hour: 22, minute: 0, profileID: night),
         ScheduleRule(hour: 8, minute: 0, weekdays: [2, 3, 4, 5, 6], profileID: day)]   // 평일 아침
    }

    func testEveningPicksNight() { XCTAssertEqual(Schedule.activeRule(rules, at: date(16, 23, 30), calendar: cal)?.profileID, night) }
    func testWeekdayMorningPicksDay() { XCTAssertEqual(Schedule.activeRule(rules, at: date(16, 9, 0), calendar: cal)?.profileID, day) }
    func testAfterMidnightStillNight() { XCTAssertEqual(Schedule.activeRule(rules, at: date(17, 1, 0), calendar: cal)?.profileID, night) }
    func testWeekendMorningKeepsNightFromLastNight() {   // 9/19 토 09:00 — 아침 규칙은 평일만
        XCTAssertEqual(Schedule.activeRule(rules, at: date(19, 9, 0), calendar: cal)?.profileID, night)
    }
    func testExactFireTimeCounts() { XCTAssertEqual(Schedule.activeRule(rules, at: date(16, 22, 0), calendar: cal)?.profileID, night) }
    func testDisabledIgnored() {
        var r = rules; r[0].enabled = false
        XCTAssertEqual(Schedule.activeRule(r, at: date(16, 23, 30), calendar: cal)?.profileID, day)
    }
    func testEmptyReturnsNil() { XCTAssertNil(Schedule.activeRule([], at: date(16, 12, 0), calendar: cal)) }
}
