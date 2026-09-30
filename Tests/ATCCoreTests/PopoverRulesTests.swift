// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import ATCCore

final class PopoverRulesTests: XCTestCase {
    private let base = URL(string: "http://localhost:7700")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func feed(warning: Int = 0, caution: Int = 0, advisory: Int = 0, since: Date? = nil) -> FeedState {
        var f = FeedState()
        f.connection = .live
        f.summary = SupervisorSummary(
            master: warning > 0 ? .warning : (caution > 0 ? .caution : nil),
            counts: .init(warning: warning, caution: caution, advisory: advisory),
            needsYou: ["TEAM_K"])
        func make(_ level: AlertLevel, _ n: Int) -> [SupervisorAlert] {
            (0..<n).map {
                var a = alert("\(level.rawValue)-\($0)", level)
                a.since = since
                return a
            }
        }
        f.alerts = make(.advisory, advisory) + make(.warning, warning) + make(.caution, caution)
        return f
    }

    // MARK: age

    func testAge() {
        func age(_ secs: Double) -> String { AgeFormat.short(since: now.addingTimeInterval(-secs), now: now) }
        XCTAssertEqual(age(0), "<1m")
        XCTAssertEqual(age(59), "<1m")
        XCTAssertEqual(age(60), "1m")
        XCTAssertEqual(age(4 * 60 + 59), "4m")
        XCTAssertEqual(age(3_599), "59m")
        XCTAssertEqual(age(3_600), "1h")
        XCTAssertEqual(age(3 * 3_600 + 1_800), "3h")
        XCTAssertEqual(age(86_400), "1d")
        XCTAssertEqual(age(2 * 86_400 + 5_000), "2d")
        // A clock a little behind the server never shows a negative age.
        XCTAssertEqual(AgeFormat.short(since: now.addingTimeInterval(30), now: now), "<1m")
    }

    func testRowChipAgeAndPlace() {
        var f = feed(warning: 1, caution: 1, advisory: 1, since: now.addingTimeInterval(-4 * 60))
        f.alerts[1].flight = "ATC-168"
        let p = PanelContent(f, base: base, now: now)
        XCTAssertEqual(p.sections.map(\.level), [.warning, .caution, .advisory])
        XCTAssertEqual(p.sections.map { $0.rows[0].chip }, ["W", "C", "A"])
        XCTAssertEqual(p.sections[0].rows[0].age, "4m")
        XCTAssertEqual(p.sections[0].rows[0].place, "FLIGHT ATC-168")
        XCTAssertNil(PanelContent(feed(warning: 1), base: base, now: now).sections[0].rows[0].age)
    }

    // MARK: fold

    func testWarningIsNeverFolded() {
        let s = PanelContent(feed(warning: 9), base: base, now: now).sections[0]
        XCTAssertEqual(s.visibleRows(expanded: false).count, 9)
        XCTAssertNil(s.toggleLabel(expanded: false))
        var e = LampExpansion()
        e.toggle(.warning)
        XCTAssertTrue(e.isExpanded(.warning))
        XCTAssertEqual(e.stored, [])
    }

    func testCautionShowsFirstFiveThenMore() {
        let s = PanelContent(feed(caution: 23), base: base, now: now).sections[0]
        XCTAssertEqual(s.visibleRows(expanded: false).map(\.id), (0..<5).map { "caution-\($0)" })
        XCTAssertEqual(s.toggleLabel(expanded: false), "CAUTION 18개 더")
        XCTAssertEqual(s.visibleRows(expanded: true).count, 23)
        XCTAssertEqual(s.toggleLabel(expanded: true), "접기")
    }

    func testCautionUpToFiveHasNoToggle() {
        for n in 1...5 {
            let s = PanelContent(feed(caution: n), base: base, now: now).sections[0]
            XCTAssertEqual(s.visibleRows(expanded: false).count, n)
            XCTAssertNil(s.toggleLabel(expanded: false))
            XCTAssertNil(s.toggleLabel(expanded: true))
        }
    }

    func testAdvisoryIsFoldedBehindItsHeader() {
        let s = PanelContent(feed(advisory: 13), base: base, now: now).sections[0]
        XCTAssertEqual(s.header, "ADVISORY 13")
        XCTAssertTrue(s.visibleRows(expanded: false).isEmpty)
        XCTAssertEqual(s.visibleRows(expanded: true).count, 13)
    }

    func testExpansionIsRememberedAndOnlyForFoldableLevels() {
        XCTAssertFalse(LampExpansion().isExpanded(.caution))
        XCTAssertFalse(LampExpansion().isExpanded(.advisory))
        var e = LampExpansion(stored: ["caution", "warning", "bogus"])
        XCTAssertTrue(e.isExpanded(.caution))
        XCTAssertEqual(e.stored, ["caution"])
        e.toggle(.advisory)
        XCTAssertEqual(LampExpansion(stored: e.stored), e)
        e.toggle(.caution)
        XCTAssertEqual(e.stored, ["advisory"])
    }

    // MARK: strip

    func testTilesFollowSummaryCounts() {
        let p = PanelContent(feed(warning: 2, caution: 23, advisory: 13), base: base, now: now)
        XCTAssertEqual(p.tiles.map(\.label), ["MASTER WARNING", "MASTER CAUTION", "ADVISORY"])
        XCTAssertEqual(p.tiles.map(\.count), [2, 23, 13])
        XCTAssertEqual(p.tiles.map(\.isLit), [true, true, true])
        let quiet = PanelContent(feed(), base: base, now: now)
        XCTAssertEqual(quiet.tiles.map(\.isLit), [false, false, false])
    }

    func testNeedsYouChipsOpenStripsAndStatusLine() throws {
        var f = feed()
        f.summary?.working = .init(aircraft: 3, control: 2)
        let p = PanelContent(f, base: base, now: now)
        XCTAssertEqual(p.needsYouChips.map(\.name), ["TEAM_K"])
        XCTAssertEqual(p.needsYouChips[0].url?.absoluteString, "http://localhost:7700/#strips")
        XCTAssertEqual(p.statusLine, "AIRCRAFT 3 · CONTROL 2")
    }

    func testFuelBarFractionAndDetail() throws {
        var f = feed()
        f.summary?.fuel = .init(label: nil, windows: [
            .init(name: "five_hour", pct: 45.4, resetsAt: nil),
            .init(name: "seven_day", pct: 140, resetsAt: nil),
            .init(name: "monthly", pct: nil, resetsAt: nil),
        ])
        let p = PanelContent(f, base: base, now: now)
        XCTAssertEqual(p.fuel[0].detail, "45%")
        XCTAssertEqual(p.fuel[0].fraction ?? -1, 0.454, accuracy: 0.0001)
        XCTAssertEqual(p.fuel[1].fraction, 1)
        XCTAssertNil(p.fuel[2].fraction)
        XCTAssertEqual(p.fuel[2].detail, "—")
    }

    // MARK: height

    func testHeightFitsContentWithinBounds() {
        let none = PanelContent(FeedState(), base: base, now: now)
        XCTAssertEqual(PanelLayout.height(for: none, expansion: LampExpansion()), PanelLayout.minHeight)

        let few = PanelContent(feed(warning: 1), base: base, now: now)
        let many = PanelContent(feed(warning: 30, caution: 40), base: base, now: now)
        let hFew = PanelLayout.height(for: few, expansion: LampExpansion())
        XCTAssertGreaterThanOrEqual(hFew, PanelLayout.minHeight)
        XCTAssertLessThan(hFew, PanelLayout.maxHeight)
        XCTAssertEqual(PanelLayout.height(for: many, expansion: LampExpansion()), PanelLayout.maxHeight)
    }

    func testHeightGrowsWhenExpanded() {
        let p = PanelContent(feed(caution: 8, advisory: 3), base: base, now: now)
        let folded = PanelLayout.height(for: p, expansion: LampExpansion())
        let open = PanelLayout.height(for: p, expansion: LampExpansion(stored: ["caution", "advisory"]))
        XCTAssertGreaterThan(open, folded)
    }
}
