// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import ATCCore

final class DutyTests: XCTestCase {
    private func lamp(_ state: String?, blocked: Bool? = false, enabled: Bool = true) -> DutyLamp? {
        DutyLamp.of(DutyStatus(enabled: enabled, state: state, blocked: blocked, account: "acct-2", context: 22695, cap: 250_000))
    }

    func testRealBodyDecodesToGreenWithTooltip() throws {
        let status = try ATCDecoding.duty(from: Fixtures.data("duty-status"))
        XCTAssertEqual(DutyLamp.of(status), DutyLamp(dot: .green, tooltip: "DUTY · acct-2 · context 23/250k"))
    }

    func testStateToDot() {
        XCTAssertEqual(lamp("idle")?.dot, .green)
        XCTAssertEqual(lamp("answering")?.dot, .amber)
        XCTAssertEqual(lamp("down")?.dot, .red)
        XCTAssertEqual(lamp("blocked")?.dot, .red)
        XCTAssertEqual(lamp("something-new")?.dot, .grey)
        XCTAssertEqual(lamp(nil)?.dot, .grey)
    }

    func testBlockedFlagWins() {
        XCTAssertEqual(lamp("idle", blocked: true)?.dot, .red)
        XCTAssertEqual(lamp("answering", blocked: true)?.dot, .red)
    }

    func testHiddenWhenDisabledOrUnknown() {
        XCTAssertNil(lamp("idle", enabled: false))
        XCTAssertNil(DutyLamp.of(nil))
    }

    func testTooltipLeavesOutMissingParts() {
        XCTAssertEqual(DutyLamp.of(DutyStatus(enabled: true, state: "idle"))?.tooltip, "DUTY")
        XCTAssertEqual(DutyLamp.of(DutyStatus(enabled: true, state: "idle", account: "a"))?.tooltip, "DUTY · a")
        XCTAssertEqual(DutyLamp.of(DutyStatus(enabled: true, state: "idle", context: 1499))?.tooltip, "DUTY · context 1k")
        XCTAssertEqual(DutyLamp.of(DutyStatus(enabled: true, state: "idle", account: "", context: 0, cap: 0))?.tooltip, "DUTY · context 0k")
    }

    func testDisabledBodyWithOnlyEnabled() throws {
        let status = try ATCDecoding.duty(from: Data(#"{"enabled":false}"#.utf8))
        XCTAssertNil(DutyLamp.of(status))
    }

    func testRequestIsAGet() {
        let req = ATCClient().request("/api/duty/status")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:7700/api/duty/status")
    }

    func testDutyFragmentRoutesToTheWindow() {
        let base = URL(string: "http://localhost:7700")!
        let url = ATCLink.url(base: base, link: "#\(DutyLamp.fragment)")!
        XCTAssertEqual(url.absoluteString, "http://localhost:7700/#duty")
        XCTAssertEqual(LinkRoute.decide(url: url, base: base, preference: .window, modifier: false), .window(fragment: "duty"))
        XCTAssertEqual(LinkRoute.decide(url: url, base: base, preference: .browser, modifier: false), .browser(url))
        XCTAssertEqual(LinkRoute.decide(url: url, base: base, preference: .window, modifier: true), .browser(url))
        XCTAssertEqual(LinkRoute.hashScript(fragment: "duty"), #"location.hash = "duty";"#)
        XCTAssertEqual(LinkRoute.pageURL(base: base, fragment: "duty")?.absoluteString, "http://localhost:7700/#duty")
    }

    func testDutyRowAddsHeight() throws {
        var feed = FeedState()
        feed.connection = .live
        feed.summary = try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-live"))
        let p = PanelContent(feed, base: URL(string: "http://localhost:7700")!)
        XCTAssertNil(p.notice)
        let without = PanelLayout.height(for: p, expansion: LampExpansion())
        let with = PanelLayout.height(for: p, expansion: LampExpansion(), dutyLine: true)
        XCTAssertEqual(with, min(PanelLayout.maxHeight, without + PanelLayout.dutyLine))
    }
}
