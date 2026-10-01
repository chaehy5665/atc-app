// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class AnnunciatorTests: XCTestCase {
    private func state(_ master: AlertLevel?, w: Int = 0, c: Int = 0, a: Int = 0) -> MasterState {
        MasterState(summary: SupervisorSummary(master: master, counts: .init(warning: w, caution: c, advisory: a)))
    }

    func testMasterOff() {
        let s = state(nil, a: 12)
        XCTAssertEqual(s, MasterState.off)
        XCTAssertEqual(s.title, "✈")
    }

    func testMasterCaution() {
        let s = state(.caution, c: 4, a: 9)
        XCTAssertEqual(s.light, .caution)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.title, "✈ 4")
    }

    func testMasterWarningCountsWarningsOnly() {
        // Count is the number lit at that level and above.
        let s = state(.warning, w: 2, c: 5)
        XCTAssertEqual(s.light, .warning)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.title, "✈ 2")
    }

    func testMasterFollowsServerNotCounts() {
        XCTAssertEqual(state(nil, w: 3, c: 3).light, .off)
        XCTAssertEqual(state(.advisory, a: 3).light, .off)
    }

    func testMasterFromFixture() throws {
        let s = MasterState(summary: try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-v1")))
        XCTAssertEqual(s, MasterState(light: .caution, count: 4))
    }

    func testLampGroups() throws {
        let g = LampGroups(try ATCDecoding.alerts(from: Fixtures.data("supervisor-alerts")))
        XCTAssertEqual(g.warning.count, 2)
        XCTAssertEqual(g.caution.count, 6)
        XCTAssertEqual(g.advisory.count, 5)
        XCTAssertEqual(g.unleveled.count, 1)
    }

    func testLampGroupsKeepServerOrder() {
        let g = LampGroups([alert("b", .caution), alert("a", .warning), alert("c", .caution)])
        XCTAssertEqual(g.caution.map(\.key), ["b", "c"])
    }

    func testSeenKeysFirstLoadIsSilent() {
        var seen = SeenKeys()
        XCTAssertEqual(seen.update(items: [alert("w", .warning), alert("c", nil, cue: .call)]), [])
    }

    func testSeenKeysNewWarningAndCall() {
        var seen = SeenKeys()
        _ = seen.update(items: [alert("old", .warning)])
        let new = seen.update(items: [
            alert("old", .warning), alert("w", .warning), alert("call", .advisory, cue: .call),
            alert("caution", .caution), alert("done", nil, cue: .done),
        ])
        XCTAssertEqual(new, ["w", "call"])
        // Nothing new the second time.
        XCTAssertEqual(seen.update(items: [alert("w", .warning), alert("call", .advisory, cue: .call)]), [])
    }

    func testSeenKeysClearedThenBack() {
        var seen = SeenKeys()
        _ = seen.update(items: [alert("w", .warning)])
        XCTAssertEqual(seen.update(items: []), [])
        XCTAssertEqual(seen.update(items: [alert("w", .warning)]), ["w"])
    }

    func testSeenKeysEmptyFirstLoadStillBaseline() {
        var seen = SeenKeys()
        XCTAssertEqual(seen.update(items: []), [])
        XCTAssertEqual(seen.update(items: [alert("w", .warning)]), ["w"])
    }

    func testZTime() {
        XCTAssertEqual(ZTime.format(Date(timeIntervalSince1970: 0)), "00:00Z")
        XCTAssertEqual(ZTime.format(Date(timeIntervalSince1970: 86_400 + 3_600 * 9 + 60 * 5 + 59)), "09:05Z")
        XCTAssertEqual(ZTime.format(Date(timeIntervalSince1970: 86_399)), "23:59Z")
        XCTAssertEqual(ZTime.format(iso: "2026-09-29T17:03:16.139Z"), "17:03Z")
        XCTAssertEqual(ZTime.format(iso: "2026-09-29T23:59:59Z"), "23:59Z")
        XCTAssertNil(ZTime.format(iso: "nope"))
        // Before the epoch still lands in 00:00...23:59.
        XCTAssertEqual(ZTime.format(Date(timeIntervalSince1970: -60)), "23:59Z")
    }
}
