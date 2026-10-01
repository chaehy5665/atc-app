// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class PanelTests: XCTestCase {
    private let base = URL(string: "http://localhost:7700")!

    private func live(_ fixture: String = "supervisor-summary-live", alerts: [SupervisorAlert] = []) throws -> FeedState {
        var feed = FeedState()
        feed.connection = .live
        feed.summary = try ATCDecoding.summary(from: Fixtures.data(fixture))
        feed.alerts = alerts
        return feed
    }

    // MARK: summary model against atc's real body

    func testLiveSummaryDecodes() throws {
        let s = try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-live"))
        XCTAssertEqual(s.master, .caution)
        XCTAssertEqual(s.pending?.schedule, 0)
        XCTAssertEqual(s.pending?.dispatch, 2)
        XCTAssertEqual(s.fuel?.windows?.map(\.name), ["five_hour", "seven_day"])
        XCTAssertEqual(s.rts?.result, "ok")
        XCTAssertEqual(s.working?.control, 2)
    }

    // MARK: title

    func testFuelNames() {
        XCTAssertEqual(FuelFormat.shortName("five_hour"), "5h")
        XCTAssertEqual(FuelFormat.shortName("seven_day"), "7d")
        XCTAssertEqual(FuelFormat.shortName("seven_day_opus"), "7d opus")
        XCTAssertEqual(FuelFormat.shortName("monthly"), "monthly")
        XCTAssertEqual(FuelFormat.percent(44.6), "45%")
        XCTAssertEqual(FuelFormat.percent(-3), "0%")
    }

    private func feed(_ counts: SupervisorSummary.Counts, master: AlertLevel?, fuel: Bool = true) throws -> FeedState {
        var f = try live()
        f.summary?.counts = counts
        f.summary?.master = master
        if !fuel { f.summary?.fuel = nil }
        return f
    }

    func testTitleLive() throws {
        let t = StatusBarTitle(try live())
        XCTAssertEqual(t.symbol, .light(.caution))
        XCTAssertEqual(t.text, "21 +9 5h 6% · 7d 65%")
        XCTAssertEqual(t.plain, "✈ 21 +9 5h 6% · 7d 65%")
        XCTAssertEqual(t.accessibility, "CAUTION 21, advisory 9, 5h 6% · 7d 65%")
    }

    func testTitleWarningOnly() throws {
        let t = StatusBarTitle(try feed(.init(warning: 2), master: .warning))
        XCTAssertEqual(t.symbol, .light(.warning))
        XCTAssertEqual(t.text, "2 5h 6% · 7d 65%")
        XCTAssertEqual(t.accessibility, "WARNING 2, 5h 6% · 7d 65%")
    }

    func testTitleCountIsWarningPlusCautionAndAdvisoryIsSeparate() throws {
        let t = StatusBarTitle(try feed(.init(warning: 2, caution: 23, advisory: 13), master: .warning))
        XCTAssertEqual(t.symbol, .light(.warning))
        XCTAssertEqual(t.text, "25 +13 5h 6% · 7d 65%")
        XCTAssertEqual(t.accessibility, "WARNING 2, CAUTION 23, advisory 13, 5h 6% · 7d 65%")
    }

    func testTitleCautionOnly() throws {
        let t = StatusBarTitle(try feed(.init(caution: 4), master: .caution, fuel: false))
        XCTAssertEqual(t.symbol, .light(.caution))
        XCTAssertEqual(t.text, "4")
        XCTAssertEqual(t.plain, "✈ 4")
    }

    func testTitleAdvisoryOnlyKeepsLightOff() throws {
        let t = StatusBarTitle(try feed(.init(advisory: 13), master: .advisory))
        XCTAssertEqual(t.symbol, .light(.off))
        XCTAssertEqual(t.text, "0 +13 5h 6% · 7d 65%")
        XCTAssertEqual(t.accessibility, "advisory 13, 5h 6% · 7d 65%")
    }

    func testTitleAllZero() throws {
        let t = StatusBarTitle(try feed(.init(), master: nil))
        XCTAssertEqual(t.symbol, .light(.off))
        XCTAssertEqual(t.text, "0 5h 6% · 7d 65%")
        XCTAssertEqual(t.accessibility, "no alerts, 5h 6% · 7d 65%")
        XCTAssertEqual(StatusBarTitle(try feed(.init(), master: nil, fuel: false)).text, "0")
    }

    func testTitleColourFollowsMasterNotCounts() throws {
        // The server decides the light; the counts only decide the number.
        XCTAssertEqual(StatusBarTitle(try feed(.init(caution: 3), master: nil)).symbol, .light(.off))
    }

    func testTitleUnreachableIsGreyDash() throws {
        for c in [Connection.connecting, .unreachable, .unsupported] {
            var feed = try live()
            feed.connection = c
            let t = StatusBarTitle(feed)
            XCTAssertEqual(t.symbol, .unreachable)
            XCTAssertEqual(t.plain, "✈ —")
            XCTAssertEqual(t.accessibility, "atc unreachable")
        }
        XCTAssertEqual(StatusBarTitle(FeedState()).plain, "✈ —")
    }

    // MARK: links

    func testLinks() {
        XCTAssertEqual(ATCLink.url(base: base, link: "#strips")?.absoluteString, "http://localhost:7700/#strips")
        XCTAssertEqual(ATCLink.url(base: base, link: "/#radar")?.absoluteString, "http://localhost:7700/#radar")
        XCTAssertEqual(ATCLink.url(base: base, link: nil)?.absoluteString, "http://localhost:7700/")
        let slash = URL(string: "http://localhost:7700/")!
        XCTAssertEqual(ATCLink.url(base: slash, link: "#dispatch")?.absoluteString, "http://localhost:7700/#dispatch")
    }

    // MARK: popover

    func testLampsHighestFirstWithPlaceAndLink() throws {
        let alerts = [
            SupervisorAlert(key: "a", group: "alert", level: .advisory, text: "adv", link: "#strips"),
            SupervisorAlert(key: "b", group: "following", level: .caution, aircraft: "TEAM_K", flight: "ATC-90", text: "cau", next: "do it", link: "#strips"),
            SupervisorAlert(key: "c", group: "alert", level: .warning, text: "warn", next: "", link: "#radar"),
            SupervisorAlert(key: "d", group: "rts", level: nil, cue: .done, text: "rts done"),
        ]
        let p = PanelContent(try live(alerts: alerts), base: base)
        XCTAssertEqual(p.sections.map(\.title), ["WARNING", "CAUTION", "ADVISORY"])
        let w = p.sections[0].rows[0]
        XCTAssertNil(w.place)
        XCTAssertNil(w.next)
        XCTAssertEqual(w.url?.absoluteString, "http://localhost:7700/#radar")
        let c = p.sections[1].rows[0]
        XCTAssertEqual(c.place, "AIRCRAFT TEAM_K · FLIGHT ATC-90")
        XCTAssertEqual(c.next, "do it")
    }

    func testPendingRowsSkipZeroAndUseAlertLink() throws {
        let alerts = [SupervisorAlert(key: "pending|humancheck|x/y#4", group: "pending", level: .caution, text: "hc", link: "#humancheck")]
        let p = PanelContent(try live(alerts: alerts), base: base)
        XCTAssertEqual(p.pending.map(\.kind), [.dispatch, .humanCheck])
        XCTAssertEqual(p.pending[0].url?.absoluteString, "http://localhost:7700/#dispatch")
        XCTAssertEqual(p.pending[1].url?.absoluteString, "http://localhost:7700/#humancheck")
        XCTAssertEqual(p.pending[1].title, "HUMAN CHECK")
    }

    func testRtsFuelWorking() throws {
        let p = PanelContent(try live(), base: base)
        XCTAssertEqual(p.rts, "RTS OK 0e28276 → d5c6346 · 03:22Z")
        XCTAssertEqual(p.fuelLabel, "account-a")
        XCTAssertEqual(p.fuel, [
            FuelRow(name: "5h", used: "6%", resets: "07:50Z", fraction: 0.06),
            FuelRow(name: "7d", used: "65%", resets: "10:00Z", fraction: 0.65),
        ])
        XCTAssertEqual(p.workingAircraft, 3)
        XCTAssertEqual(p.workingControl, 2)
        XCTAssertEqual(p.needsYou, ["TEAM_K"])
    }

    func testOlderSummaryWithoutSchedule() throws {
        let p = PanelContent(try live("supervisor-summary-v1"), base: base)
        XCTAssertEqual(p.pending.map(\.kind), [.dispatch, .humanCheck])
        XCTAssertEqual(p.fuel.map(\.name), ["5h", "7d"])
    }

    func testNullFuelAndRts() throws {
        var feed = try live()
        feed.summary?.fuel = nil
        feed.summary?.rts = nil
        let p = PanelContent(feed, base: base)
        XCTAssertNil(p.rts)
        XCTAssertTrue(p.fuel.isEmpty)
        XCTAssertEqual(StatusBarTitle(feed).text, "21 +9")
    }

    func testNoticesHideStaleData() throws {
        var feed = try live(alerts: [alert("a", .warning)])
        feed.connection = .unreachable
        let p = PanelContent(feed, base: base)
        XCTAssertEqual(p.notice, PanelContent.unreachableNotice)
        XCTAssertTrue(p.sections.isEmpty)
        XCTAssertFalse(p.hasSummary)
        feed.connection = .unsupported
        XCTAssertEqual(PanelContent(feed, base: base).notice, PanelContent.unsupportedNotice)
        XCTAssertEqual(PanelContent(FeedState(), base: base).notice, PanelContent.connectingNotice)
    }

    // MARK: settings

    func testNormalizeURL() {
        XCTAssertEqual(ATCSettings.normalizeURL("http://localhost:7700")?.absoluteString, "http://localhost:7700")
        XCTAssertEqual(ATCSettings.normalizeURL(" localhost:7701/ ")?.absoluteString, "http://localhost:7701")
        XCTAssertEqual(ATCSettings.normalizeURL("HTTPS://atc.example:8443/x?y=1#z")?.absoluteString, "https://atc.example:8443")
        XCTAssertNil(ATCSettings.normalizeURL(""))
        XCTAssertNil(ATCSettings.normalizeURL("ftp://localhost"))
        XCTAssertNil(ATCSettings.normalizeURL("http://"))
        XCTAssertNotNil(ATCSettings.normalizeURL(ATCSettings.defaultURLString))
    }

    // MARK: feed reducer

    func testReducerConnectionFlow() throws {
        var r = FeedReducer()
        XCTAssertEqual(r.state.connection, .connecting)
        r.apply(.ping)
        XCTAssertEqual(r.state.connection, .live)
        let s = try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-live"))
        r.apply(.summary(s))
        r.apply(.alert(AlertEvent(items: [alert("a", .warning)])))
        XCTAssertEqual(r.state.summary, s)
        XCTAssertEqual(r.state.alerts.count, 1)
        r.lost(URLError(.timedOut))
        XCTAssertEqual(r.state.connection, .unreachable)
        XCTAssertNotNil(r.state.summary, "last data is kept, the UI hides it")
        r.connecting()
        r.lost(ATCError.unsupportedVersion(2))
        XCTAssertEqual(r.state.connection, .unsupported)
    }

    func testRefreshKeepsConnection() throws {
        var r = FeedReducer()
        r.lost(nil)
        r.apply(summary: try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-live")), alerts: [])
        XCTAssertEqual(r.state.connection, .unreachable)
        XCTAssertNotNil(r.state.summary)
    }
}
