import XCTest
@testable import G560Core

final class AppRuleTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    func date(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))! }  // 9/16 = 수
    let pid = UUID()

    func testNoLimitAlwaysActive() {
        XCTAssertTrue(AppRule(bundleID: "a", appName: "A", profileID: pid).isActive(at: date(16, 3, 0), calendar: cal))
    }
    func testWeekdayOnly() {
        let r = AppRule(bundleID: "a", appName: "A", profileID: pid, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(r.isActive(at: date(16, 12, 0), calendar: cal)); XCTAssertFalse(r.isActive(at: date(19, 12, 0), calendar: cal))
    }
    func testWindowSameDay() {
        let r = AppRule(bundleID: "a", appName: "A", profileID: pid, startMinute: 9 * 60, endMinute: 18 * 60)
        XCTAssertTrue(r.isActive(at: date(16, 10, 0), calendar: cal)); XCTAssertFalse(r.isActive(at: date(16, 20, 0), calendar: cal))
    }
    func testWindowAcrossMidnight() {
        let r = AppRule(bundleID: "a", appName: "A", profileID: pid, weekdays: [4], startMinute: 22 * 60, endMinute: 8 * 60)   // 수요일 밤
        XCTAssertTrue(r.isActive(at: date(16, 23, 0), calendar: cal))    // 수 23:00
        XCTAssertTrue(r.isActive(at: date(17, 2, 0), calendar: cal))     // 목 02:00 (수요일 밤 연장)
        XCTAssertFalse(r.isActive(at: date(17, 23, 0), calendar: cal))   // 목 23:00 아님
        XCTAssertFalse(r.isActive(at: date(16, 12, 0), calendar: cal))
    }
    func testDisabled() {
        var r = AppRule(bundleID: "a", appName: "A", profileID: pid); r.enabled = false
        XCTAssertFalse(r.isActive(at: date(16, 12, 0), calendar: cal))
    }
}
