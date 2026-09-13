import XCTest
@testable import G560Core

final class EQPresetTests: XCTestCase {
    func testAllPresetsAreUniqueAndInRange() {
        var seen: [[Int]: String] = [:]
        for p in EQPresets.all {
            XCTAssertEqual(p.gains.count, G560.eqBands, p.name)
            XCTAssertTrue(p.gains.allSatisfy { G560.eqRange.contains($0) }, "\(p.name) out of range")
            XCTAssertNil(seen[p.gains], "\(p.name) duplicates \(seen[p.gains] ?? "")")
            seen[p.gains] = p.name
        }
    }
    func testNameLookup() {
        XCTAssertEqual(EQPresets.name(for: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "Flat")
        XCTAssertNil(EQPresets.name(for: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    }
}
