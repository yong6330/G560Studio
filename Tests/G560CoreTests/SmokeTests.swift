import XCTest
@testable import G560Core
final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(G560Core.version, "0.1.0") }
}
