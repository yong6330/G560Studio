import XCTest
@testable import G560Core

final class AudioLevelsTests: XCTestCase {
    func sine(_ hz: Float, n: Int = 1024, sr: Float = 48000, amp: Float = 0.5) -> [Float] {
        (0..<n).map { amp * sin(2 * .pi * hz * Float($0) / sr) }
    }
    func testSilence() {
        XCTAssertEqual(LevelMeter.measure([Float](repeating: 0, count: 1024), sampleRate: 48000), .silence)
    }
    func testRMSAndPeakOfSine() {
        let l = LevelMeter.measure(sine(1000), sampleRate: 48000)
        XCTAssertEqual(l.peak, 0.5, accuracy: 0.01); XCTAssertEqual(l.rms, 0.354, accuracy: 0.02)
    }
    func testBassGoesToLow() {
        let l = LevelMeter.measure(sine(60), sampleRate: 48000)
        XCTAssertGreaterThan(l.low, l.mid); XCTAssertGreaterThan(l.low, l.high)
    }
    func testTrebleGoesToHigh() {
        let l = LevelMeter.measure(sine(8000), sampleRate: 48000)
        XCTAssertGreaterThan(l.high, l.low); XCTAssertGreaterThan(l.high, l.mid)
    }
}
