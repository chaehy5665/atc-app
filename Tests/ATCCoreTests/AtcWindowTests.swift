// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class AtcWindowTests: XCTestCase {
    private let base = URL(string: "http://localhost:7700")!

    private func route(_ s: String, base: URL? = nil, pref: LinkPreference = .window, modifier: Bool = false) -> LinkRoute {
        LinkRoute.decide(url: URL(string: s)!, base: base ?? self.base, preference: pref, modifier: modifier)
    }

    func testSameOriginOpensInTheWindow() {
        XCTAssertEqual(route("http://localhost:7700/#strips"), .window(fragment: "strips"))
    }

    func testNoFragment() {
        XCTAssertEqual(route("http://localhost:7700/"), .window(fragment: nil))
        XCTAssertEqual(route("http://localhost:7700"), .window(fragment: nil))
    }

    func testFragmentStaysPercentEncoded() {
        XCTAssertEqual(route("http://localhost:7700/#a%20b"), .window(fragment: "a%20b"))
    }

    func testOtherPortOrHostOrSchemeGoesToTheBrowser() {
        let other = "http://localhost:7701/#strips"
        XCTAssertEqual(route(other), .browser(URL(string: other)!))
        let host = "http://example.com:7700/#strips"
        XCTAssertEqual(route(host), .browser(URL(string: host)!))
        let scheme = "https://localhost:7700/#strips"
        XCTAssertEqual(route(scheme), .browser(URL(string: scheme)!))
        let gh = "https://github.com/x/y/pull/1"
        XCTAssertEqual(route(gh), .browser(URL(string: gh)!))
    }

    func testHostCaseAndDefaultPorts() {
        XCTAssertEqual(route("http://LOCALHOST:7700/#a"), .window(fragment: "a"))
        XCTAssertEqual(route("http://atc.test/#a", base: URL(string: "http://atc.test:80")!), .window(fragment: "a"))
        XCTAssertEqual(route("https://atc.test:443/#a", base: URL(string: "https://atc.test")!), .window(fragment: "a"))
    }

    func testBrowserPreferenceSendsEverythingToTheBrowser() {
        let u = "http://localhost:7700/#strips"
        XCTAssertEqual(route(u, pref: .browser), .browser(URL(string: u)!))
    }

    func testModifierSendsToTheBrowser() {
        let u = "http://localhost:7700/#strips"
        XCTAssertEqual(route(u, modifier: true), .browser(URL(string: u)!))
        XCTAssertEqual(route(u, modifier: false), .window(fragment: "strips"))
    }

    func testNavigationLock() {
        XCTAssertTrue(WindowNavigation.allows(URL(string: "http://localhost:7700/api/x")!, base: base))
        XCTAssertTrue(WindowNavigation.allows(URL(string: "about:blank")!, base: base))
        XCTAssertFalse(WindowNavigation.allows(URL(string: "https://github.com")!, base: base))
        XCTAssertFalse(WindowNavigation.allows(URL(string: "mailto:a@b.c")!, base: base))
    }

    func testHashScriptQuotesTheFragment() {
        XCTAssertEqual(LinkRoute.hashScript(fragment: "strips"), "location.hash = \"strips\";")
        XCTAssertEqual(LinkRoute.hashScript(fragment: nil), "location.hash = \"\";")
        XCTAssertEqual(LinkRoute.hashScript(fragment: "a\"b\\c\n"), "location.hash = \"a\\\"b\\\\c\\n\";")
    }

    func testPageURL() {
        XCTAssertEqual(LinkRoute.pageURL(base: base, fragment: "dispatch")?.absoluteString, "http://localhost:7700/#dispatch")
        XCTAssertEqual(LinkRoute.pageURL(base: URL(string: "http://localhost:7700/")!, fragment: nil)?.absoluteString, "http://localhost:7700/")
    }

    func testUserAgentAndBadge() {
        XCTAssertEqual(AppIdentity.userAgentName(version: "0.2.0"), "ANNUNCIATOR/0.2.0")
        var feed = FeedState()
        XCTAssertNil(DockBadge.label(feed))
        var r = FeedReducer()
        r.apply(.summary(SupervisorSummary(master: .warning, counts: .init(warning: 2, caution: 3, advisory: 9))))
        feed = r.state
        XCTAssertEqual(DockBadge.label(feed), "5")
        r.lost(nil)
        XCTAssertNil(DockBadge.label(r.state))
        r.apply(.summary(SupervisorSummary(counts: .init(advisory: 4))))
        XCTAssertNil(DockBadge.label(r.state))
    }

    func testOverlayFollowsTheFeedAndReloadsOnceOnReturn() {
        var o = WindowOverlay()
        XCTAssertNil(o.text)
        XCTAssertFalse(o.feedChanged(.connecting))
        XCTAssertNil(o.text)
        XCTAssertFalse(o.feedChanged(.unreachable))
        XCTAssertEqual(o.text, PanelContent.unreachableNotice)
        XCTAssertFalse(o.feedChanged(.connecting))
        XCTAssertNotNil(o.text)  // still covered while reconnecting
        XCTAssertTrue(o.feedChanged(.live))
        XCTAssertNil(o.text)
        XCTAssertFalse(o.feedChanged(.live))  // no second reload
    }

    func testOverlayUnsupportedUsesItsOwnText() {
        var o = WindowOverlay()
        _ = o.feedChanged(.unsupported)
        XCTAssertEqual(o.text, PanelContent.unsupportedNotice)
    }

    func testOverlayOnFailedNavigation() {
        var o = WindowOverlay()
        o.pageFailed()
        XCTAssertEqual(o.text, PanelContent.unreachableNotice)
        o.pageLoaded()
        XCTAssertNil(o.text)
        o.pageFailed()
        // A feed that comes back after a failed first load clears the overlay; the page reload is up to the caller
        // (feed was never down, so no reload is asked for here).
        XCTAssertFalse(o.feedChanged(.live))
        XCTAssertNotNil(o.text)
    }

    func testFailedNavigationWhileFeedDownClearsWhenFeedReturns() {
        var o = WindowOverlay()
        _ = o.feedChanged(.unreachable)
        o.pageFailed()
        XCTAssertTrue(o.feedChanged(.live))
        XCTAssertNil(o.text)
    }
}
