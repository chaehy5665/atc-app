// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

/// ATC-222: the calm popover rules.
final class PanelRowsTests: XCTestCase {
    private let base = URL(string: "http://localhost:7700")!

    private func panel(_ edit: (inout SupervisorSummary) -> Void = { _ in }) throws -> PanelContent {
        var feed = FeedState()
        feed.connection = .live
        var s = try ATCDecoding.summary(from: Fixtures.data("supervisor-summary-live"))
        edit(&s)
        feed.summary = s
        return PanelContent(feed, base: base)
    }

    // MARK: all normal

    func testAllNormalWithoutWarningOrCaution() throws {
        XCTAssertTrue(try panel { $0.counts = .init(advisory: 9); $0.master = nil }.allNormal)
        XCTAssertFalse(try panel().allNormal)
        XCTAssertFalse(try panel { $0.counts = .init(warning: 1) }.allNormal)
    }

    func testAllNormalShrinksThePopover() throws {
        let calm = try panel { $0.counts = .init(); $0.master = nil }
        let busy = try panel()
        XCTAssertLessThan(
            PanelLayout.height(for: calm, expansion: LampExpansion()), PanelLayout.height(for: busy, expansion: LampExpansion()))
    }

    // MARK: header groups

    func testGroupsOrderAndHeaders() throws {
        let p = try panel()
        XCTAssertEqual(p.groups.map(\.id), ["pending", "needsYou", "rts", "working"])
        XCTAssertEqual(p.groups[0].header, "PENDING 3")
        XCTAssertEqual(p.groups[0].items.map(\.text), ["DISPATCH 2", "HUMAN CHECK 1"])
        XCTAssertEqual(p.groups[1].header, "NEEDS YOU 1")
        XCTAssertEqual(p.groups[1].items.map(\.text), ["TEAM_K"])
        XCTAssertTrue(p.groups[1].isNeedsYou)
        XCTAssertEqual(p.groups[3].header, "AIRCRAFT 3 · CONTROL 2")
    }

    func testGroupsOnlyWhenTheyHaveSomething() throws {
        let p = try panel { $0.pending = nil; $0.needsYou = []; $0.rts = nil; $0.working = nil }
        XCTAssertTrue(p.groups.isEmpty)
    }

    func testOnlyGroupsWithItemsOpen() throws {
        let p = try panel()
        XCTAssertTrue(p.groups[0].isExpandable)
        XCTAssertFalse(p.groups[2].isExpandable)
        XCTAssertEqual(p.groups[0].visibleItems(expanded: false), [])
        XCTAssertEqual(p.groups[0].visibleItems(expanded: true).count, 2)
        XCTAssertEqual(p.groups[2].visibleItems(expanded: true), [])
    }

    func testOpeningAGroupAddsItsRowsToTheHeight() throws {
        let p = try panel()
        let closed = PanelLayout.height(for: p, expansion: LampExpansion())
        let open = PanelLayout.height(for: p, expansion: LampExpansion(), openGroups: ["pending"])
        XCTAssertGreaterThanOrEqual(open, closed)
    }

    // MARK: FUEL

    func testFuelIsOneBarWithTheWindowClosestToItsLimit() throws {
        let p = try panel()
        XCTAssertEqual(p.fuelBar?.name, "7d")
        XCTAssertEqual(p.fuelBar?.detail, "65% · 10:00Z")
        XCTAssertNil(try panel { $0.fuel = nil }.fuelBar)
        XCTAssertNil(try panel { $0.fuel = .init(label: nil, windows: [.init(name: "five_hour", pct: nil, resetsAt: nil)]) }.fuelBar)
    }

    // MARK: status rows

    private func radio(connected: Bool) -> RadioHint? {
        var m = RadioMonitor()
        m.configure(RadioPrefs(on: true, freq: nil, noise: nil), now: Date())
        if connected { m.connect(now: Date()) }
        return RadioHint(m)
    }

    func testCalmRowsFoldIntoOneLine() {
        let rows = StatusRows(
            duty: DutyLamp(dot: .green, tooltip: "DUTY · account-a"),
            work: WorkLine(text: "GitHub: 3 open", isNotice: false, openCount: 3, ciFailing: false),
            radio: radio(connected: true))
        XCTAssertFalse(rows.needsAttention)
        XCTAssertTrue(rows.isFolded)
        XCTAssertEqual(rows.summary, "DUTY · GitHub 3 · RADIO TOWER")
        XCTAssertEqual(rows.lineCount(opened: false), 1)
        XCTAssertEqual(rows.lineCount(opened: true), 4)
    }

    func testFailingCiOpensTheGroup() {
        let rows = StatusRows(
            duty: DutyLamp(dot: .green, tooltip: "DUTY"),
            work: WorkLine(text: "GitHub: 3 open · 1 CI failing", isNotice: false, openCount: 3, ciFailing: true), radio: nil)
        XCTAssertTrue(rows.needsAttention)
        XCTAssertFalse(rows.isFolded)
        XCTAssertEqual(rows.lineCount(opened: false), 2)
        XCTAssertEqual(rows.rows.filter(\.attention).map(\.kind), [.work])
    }

    func testDutyOtherThanIdleNeedsAttention() {
        for (dot, attention) in [(DutyDot.green, false), (.amber, true), (.red, true), (.grey, true)] {
            XCTAssertEqual(StatusRows(duty: DutyLamp(dot: dot, tooltip: "DUTY"), work: nil, radio: nil).needsAttention, attention, "\(dot)")
        }
    }

    func testRadioUnreachableNeedsAttention() {
        XCTAssertTrue(StatusRows(duty: nil, work: nil, radio: radio(connected: false)).needsAttention)
        XCTAssertFalse(StatusRows(duty: nil, work: nil, radio: radio(connected: true)).needsAttention)
    }

    func testMissingRowsAreLeftOut() {
        XCTAssertEqual(StatusRows.none.lineCount(opened: true), 0)
        XCTAssertEqual(StatusRows.none.summary, "")
        let notice = StatusRows(duty: nil, work: WorkLine(text: "GitHub: 읽는 중…", isNotice: true), radio: nil)
        XCTAssertEqual(notice.summary, "GitHub")
        XCTAssertFalse(notice.needsAttention)
    }
}
