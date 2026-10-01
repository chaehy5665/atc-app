// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

/// Returns fixed units in turn.
struct FixedRandom: RandomSource {
    var values: [Double]
    var i = 0
    init(_ values: [Double]) { self.values = values }
    mutating func nextUnit() -> Double {
        defer { i += 1 }
        return values[i % values.count]
    }
}

final class ReconnectTests: XCTestCase {
    func testSequenceWithoutJitter() {
        var b = Backoff(random: FixedRandom([0.5]))  // 0.5 means factor 1.0
        let delays = (0..<8).map { _ in b.nextDelay() }
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30])
    }

    func testJitterBounds() {
        var low = Backoff(random: FixedRandom([0]))
        var high = Backoff(random: FixedRandom([0.999999]))
        XCTAssertEqual(low.nextDelay(), 0.8, accuracy: 1e-9)
        XCTAssertEqual(high.nextDelay(), 1.2, accuracy: 1e-3)
        for _ in 0..<10 { _ = low.nextDelay(); _ = high.nextDelay() }
        XCTAssertEqual(low.nextDelay(), 24, accuracy: 1e-9)
        XCTAssertEqual(high.nextDelay(), 36, accuracy: 1e-3)
    }

    func testResetStartsOver() {
        var b = Backoff(random: FixedRandom([0.5]))
        _ = b.nextDelay(); _ = b.nextDelay(); _ = b.nextDelay()
        b.reset()
        XCTAssertEqual(b.nextDelay(), 1)
        XCTAssertEqual(b.nextDelay(), 2)
    }

    func testSystemRandomStaysInRange() {
        var b = Backoff()
        for _ in 0..<50 {
            let d = b.nextDelay()
            XCTAssertTrue((0.8...36.0).contains(d))
        }
    }

    func testWatchdog() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var w = Watchdog(startedAt: t0)
        XCTAssertFalse(w.isDead(at: t0.addingTimeInterval(59.9)))
        XCTAssertTrue(w.isDead(at: t0.addingTimeInterval(60)))
        w.sawEvent(at: t0.addingTimeInterval(50))  // a ping
        XCTAssertFalse(w.isDead(at: t0.addingTimeInterval(100)))
        XCTAssertTrue(w.isDead(at: t0.addingTimeInterval(110)))
    }
}
