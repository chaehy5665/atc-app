// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class ModelsTests: XCTestCase {
    func testAlertsFixture() throws {
        let items = try ATCDecoding.alerts(from: Fixtures.data("supervisor-alerts"))
        XCTAssertEqual(items.count, 14)
        XCTAssertEqual(items.filter { $0.level == .warning }.count, 2)
        let pending = try XCTUnwrap(items.first { $0.group == "pending" })
        XCTAssertEqual(pending.cue, .call)
        XCTAssertEqual(pending.level, .advisory)
        let rts = try XCTUnwrap(items.first { $0.group == "rts" })
        XCTAssertNil(rts.level)
        XCTAssertEqual(rts.cue, .done)
        let following = try XCTUnwrap(items.first { $0.group == "following" })
        XCTAssertNotNil(following.since)
        XCTAssertNil(items[0].since)
    }

    func testAlertEventFixture() throws {
        let e = try ATCDecoding.makeDecoder().decode(AlertEvent.self, from: Fixtures.data("alert-event-initial"))
        XCTAssertTrue(e.initial)
        XCTAssertEqual(e.raised.count, 14)
        XCTAssertEqual(e.items.count, 14)
        XCTAssertEqual(e.cleared, [])
    }

    func testAlertEventClearedAndMissingFields() throws {
        let json = #"{"cleared":["a","b"],"raised":[],"extra":1}"#
        let e = try ATCDecoding.makeDecoder().decode(AlertEvent.self, from: Data(json.utf8))
        XCTAssertEqual(e.cleared, ["a", "b"])
        XCTAssertEqual(e.items, [])
        XCTAssertFalse(e.initial)
    }

    func testUnknownFieldsIgnoredAndOptionalsNil() throws {
        let json = #"{"items":[{"key":"k","group":"g","level":null,"text":"t","surprise":[1,2]}]}"#
        let a = try XCTUnwrap(ATCDecoding.alerts(from: Data(json.utf8)).first)
        XCTAssertNil(a.level)
        XCTAssertNil(a.cue)
        XCTAssertNil(a.aircraft)
        XCTAssertNil(a.flight)
        XCTAssertNil(a.next)
        XCTAssertNil(a.link)
        XCTAssertNil(a.since)
    }

    func testUnknownLevelBecomesNil() throws {
        let json = #"{"items":[{"key":"k","group":"g","level":"emergency","cue":"shout","text":"t"}]}"#
        let a = try XCTUnwrap(ATCDecoding.alerts(from: Data(json.utf8)).first)
        XCTAssertNil(a.level)
        XCTAssertNil(a.cue)
    }

    func testMissingRequiredFieldFails() {
        let json = #"{"items":[{"group":"g","text":"t"}]}"#
        XCTAssertThrowsError(try ATCDecoding.alerts(from: Data(json.utf8)))
    }

    func testSummaryFixture() throws {
        let s = try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-v1"))
        XCTAssertEqual(s.v, 1)
        XCTAssertEqual(s.master, .caution)
        XCTAssertEqual(s.counts, .init(warning: 0, caution: 4, advisory: 9))
        XCTAssertEqual(s.pending?.dispatch, 2)
        XCTAssertEqual(s.fuel?.windows?.first?.name, "5h")
        XCTAssertEqual(s.fuel?.windows?.first?.pct, 62.5)
        XCTAssertEqual(s.rts?.result, "done")
        XCTAssertEqual(s.working?.aircraft, 3)
        XCTAssertEqual(s.needsYou, ["TEAM_K"])
        XCTAssertEqual(ZTime.format(try XCTUnwrap(s.at)), "17:03Z")
    }

    func testSummaryMinimalBody() throws {
        let s = try ATCDecoding.summary(from: Data(#"{"v":1,"master":null}"#.utf8))
        XCTAssertNil(s.master)
        XCTAssertEqual(s.counts, .init())
        XCTAssertNil(s.fuel)
        XCTAssertEqual(s.needsYou, [])
    }

    func testUnknownSummaryVersionIsTypedError() {
        for body in [#"{"v":2,"whatever":true}"#, #"{"master":null}"#, "not json"] {
            XCTAssertThrowsError(try ATCDecoding.summary(from: Data(body.utf8))) { error in
                guard case ATCError.unsupportedVersion = error else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try ATCDecoding.summary(from: Data(#"{"v":2}"#.utf8))) {
            XCTAssertEqual($0 as? ATCError, .unsupportedVersion(2))
        }
    }

    func testTypedEvents() throws {
        let alertBody = try String(decoding: Fixtures.data("alert-event-initial"), as: UTF8.self)
        guard case .alert(let e) = try ATCEvent(SSEEvent(name: "alert", data: alertBody)) else { return XCTFail() }
        XCTAssertEqual(e.items.count, 14)
        XCTAssertEqual(try ATCEvent(SSEEvent(name: "ping", data: "")), .ping)
        XCTAssertEqual(try ATCEvent(SSEEvent(name: "snapshot", data: "{}")), .other("snapshot"))
        let v = #"{"build":"/assets/x.js","startedAt":"2026-09-29T17:03:16.139Z","head":"abc"}"#
        guard case .version(let info) = try ATCEvent(SSEEvent(name: "version", data: v)) else { return XCTFail() }
        XCTAssertEqual(info.head, "abc")
        XCTAssertThrowsError(try ATCEvent(SSEEvent(name: "summary", data: #"{"v":9}"#)))
    }

    func testDates() {
        XCTAssertNotNil(ISODate.parse("2026-09-29T17:03:16.139Z"))
        XCTAssertNotNil(ISODate.parse("2026-09-29T17:03:16Z"))
        XCTAssertNil(ISODate.parse("yesterday"))
    }

    func testLevelOrder() {
        XCTAssertTrue(AlertLevel.advisory < .caution)
        XCTAssertTrue(AlertLevel.caution < .warning)
    }
}
