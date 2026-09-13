import XCTest
@testable import G560Core

final class ProfileTests: XCTestCase {
    func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }

    func testFreshStoreHasDefaultProfileActive() {
        let s = ProfileStore(url: tmp())
        XCTAssertEqual(s.profiles.count, 1); XCTAssertEqual(s.activeID, s.profiles[0].id)
        XCTAssertEqual(s.active?.woofer, 20); XCTAssertEqual(s.active?.eq, [Int](repeating: 0, count: 10))
    }
    func testRoundTrip() throws {
        let url = tmp()
        var s = ProfileStore(url: url)
        var p = Profile.makeDefault(name: "밤")
        p.woofer = 10; p.lighting = .breathing(.custom(ZoneColors(zones: [RGB(1, 2, 3), .off, .off, RGB(9, 9, 9)])), period: 4)
        s.profiles.append(p); s.activeID = p.id
        try s.save()
        let t = ProfileStore(url: url)
        XCTAssertEqual(t.profiles, s.profiles); XCTAssertEqual(t.active, p)
    }
    func testCorruptFileFallsBackToDefault() throws {
        let url = tmp(); try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProfileStore(url: url).profiles.count, 1)
    }
}
