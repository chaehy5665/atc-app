// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class NotifyTests: XCTestCase {
    private let base = URL(string: "http://localhost:7700")!
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// 2026-09-30 at hh:mm UTC.
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_790_726_400 + Double(h * 3600 + m * 60))
    }

    private func plan(_ n: inout AlertNotifier, _ items: [SupervisorAlert], prefs: NotifyPrefs = NotifyPrefs(), now: Date? = nil) -> NotifyPlan {
        n.update(items: items, base: base, prefs: prefs, now: now ?? at(12), calendar: utc)
    }

    // MARK: which keys notify

    func testFirstLoadIsSilent() {
        var n = AlertNotifier()
        XCTAssertTrue(plan(&n, [alert("w", .warning), alert("c", nil, cue: .call)]).isEmpty)
    }

    func testNewWarningAndCallNotifyCautionAndDoneDoNot() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        let p = plan(&n, [alert("w", .warning), alert("c", nil, cue: .call), alert("k", .caution), alert("d", .advisory, cue: .done)])
        XCTAssertEqual(p.notifications.map(\.id), ["w", "c"])
        XCTAssertEqual(p.notifications.map(\.level), [.warning, .call])
    }

    func testLevelAndCueDecideNotTheKeyPrefix() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        let p = plan(&n, [alert("pending|schedule|x", .caution, cue: .call), alert("alert|orphan|y", .warning)])
        XCTAssertEqual(p.notifications.map(\.id), ["pending|schedule|x", "alert|orphan|y"])
    }

    func testWarningWithCallCueIsWarning() {
        XCTAssertEqual(NotifyLevel(alert("a", .warning, cue: .call)), .warning)
        XCTAssertNil(NotifyLevel(alert("a", .caution)))
    }

    func testAKeyNotifiesOnce() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        XCTAssertEqual(plan(&n, [alert("w", .warning)]).notifications.count, 1)
        XCTAssertTrue(plan(&n, [alert("w", .warning)]).isEmpty)
    }

    // MARK: away: reconnect compares with the last seen keys

    func testRaisedWhileAwayNotifiesOnceAndClearedWhileAwayDoesNot() {
        var n = AlertNotifier()
        _ = plan(&n, [alert("old", .warning)])
        // Away: "old" cleared, "gone" raised and cleared (never seen), "new" raised. The list after reconnect:
        let p = plan(&n, [alert("new", .warning)])
        XCTAssertEqual(p.notifications.map(\.id), ["new"])
        XCTAssertEqual(p.voiceKey, nil)
        // Same list again (a second reconnect): nothing.
        XCTAssertTrue(plan(&n, [alert("new", .warning)]).isEmpty)
    }

    func testStillRaisedAfterReconnectDoesNotNotifyAgain() {
        var n = AlertNotifier()
        _ = plan(&n, [alert("w", .warning)])
        XCTAssertTrue(plan(&n, [alert("w", .warning)]).isEmpty)
    }

    // MARK: burst

    func testBurstSoundsOnlyTheHighestLevel() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        var prefs = NotifyPrefs()
        prefs.voice = true
        let p = plan(&n, [alert("c1", nil, cue: .call), alert("w1", .warning), alert("w2", .warning)], prefs: prefs)
        XCTAssertEqual(p.notifications.count, 3)
        XCTAssertEqual(p.tone, .warning)
        XCTAssertEqual(p.voiceKey, "w1")
    }

    func testBurstOfCallsSoundsCallOnceForTheFirst() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        var prefs = NotifyPrefs()
        prefs.voice = true
        let p = plan(&n, [alert("c1", nil, cue: .call), alert("c2", nil, cue: .call)], prefs: prefs)
        XCTAssertEqual(p.tone, .call)
        XCTAssertEqual(p.voiceKey, "c1")
    }

    func testVoiceOffByDefaultAndSoundOffKeepsBanner() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        XCTAssertNil(plan(&n, [alert("a", .warning)]).voiceKey)
        var prefs = NotifyPrefs()
        prefs.sound = false
        let p = plan(&n, [alert("b", .warning)], prefs: prefs)
        XCTAssertEqual(p.notifications.count, 1)
        XCTAssertNil(p.tone)
    }

    func testNotificationsOffStillSounds() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        var prefs = NotifyPrefs()
        prefs.notifications = false
        let p = plan(&n, [alert("a", .warning)], prefs: prefs)
        XCTAssertTrue(p.notifications.isEmpty)
        XCTAssertEqual(p.tone, .warning)
    }

    // MARK: quiet hours

    func testQuietWindowSameDay() {
        let q = QuietHours(on: true, from: "09:00", to: "17:00")
        XCTAssertTrue(q.contains(at(9), calendar: utc))
        XCTAssertTrue(q.contains(at(16, 59), calendar: utc))
        XCTAssertFalse(q.contains(at(17), calendar: utc))
        XCTAssertFalse(q.contains(at(8, 59), calendar: utc))
    }

    func testQuietWindowAcrossMidnight() {
        let q = QuietHours(on: true, from: "22:00", to: "08:00")
        XCTAssertTrue(q.contains(at(23), calendar: utc))
        XCTAssertTrue(q.contains(at(0), calendar: utc))
        XCTAssertTrue(q.contains(at(7, 59), calendar: utc))
        XCTAssertFalse(q.contains(at(8), calendar: utc))
        XCTAssertFalse(q.contains(at(21, 59), calendar: utc))
    }

    func testQuietOffOrEmpty() {
        XCTAssertFalse(QuietHours(on: false, from: "00:00", to: "23:59").contains(at(12), calendar: utc))
        XCTAssertFalse(QuietHours(on: true, from: "10:00", to: "10:00").contains(at(10), calendar: utc))
    }

    func testQuietParsing() {
        XCTAssertEqual(QuietHours.minutes("22:05"), 22 * 60 + 5)
        XCTAssertEqual(QuietHours.minutes(" 7:30 "), 7 * 60 + 30)
        XCTAssertNil(QuietHours.minutes("24:00"))
        XCTAssertNil(QuietHours.minutes("12:5"))
        XCTAssertNil(QuietHours.minutes("noon"))
        // A bad field falls back to the default.
        XCTAssertEqual(QuietHours(on: true, from: "x", to: "06:00"), QuietHours(on: true, from: 22 * 60, to: 6 * 60))
    }

    func testQuietSilencesToneAndVoiceButNotBanner() {
        var n = AlertNotifier()
        _ = plan(&n, [])
        var prefs = NotifyPrefs()
        prefs.voice = true
        prefs.quiet = QuietHours(on: true, from: "22:00", to: "08:00")
        let p = plan(&n, [alert("a", .warning)], prefs: prefs, now: at(23))
        XCTAssertEqual(p.notifications.count, 1)
        XCTAssertNil(p.tone)
        XCTAssertNil(p.voiceKey)
        // Outside the window it sounds.
        XCTAssertEqual(plan(&n, [alert("a", .warning), alert("b", .warning)], prefs: prefs, now: at(12)).tone, .warning)
    }

    // MARK: notification content

    func testNotificationContent() {
        var a = SupervisorAlert(
            key: "k", group: "alert", level: .warning, aircraft: "TEAM_K", flight: "ATC-157", text: "판단 대기",
            next: "atc 탭에서 승인", link: "#dispatch")
        var note = AlertNotification(a, level: .warning, base: base)
        XCTAssertEqual(note.title, "WARNING · AIRCRAFT TEAM_K · FLIGHT ATC-157")
        XCTAssertEqual(note.body, "판단 대기\natc 탭에서 승인")
        XCTAssertEqual(note.url?.absoluteString, "http://localhost:7700/#dispatch")
        a.aircraft = nil
        a.flight = nil
        a.next = ""
        a.link = nil
        note = AlertNotification(a, level: .call, base: base)
        XCTAssertEqual(note.title, "CALL")
        XCTAssertEqual(note.body, "판단 대기")
        XCTAssertEqual(note.url?.absoluteString, "http://localhost:7700/")
    }

    // MARK: voice URL and tone

    func testVoiceURLEncodesTheKey() {
        let url = VoiceURL.url(base: URL(string: "http://localhost:7700/")!, key: "alert|health|LIMIT|?/x y")
        XCTAssertEqual(url?.absoluteString, "http://localhost:7700/api/voice/alert/alert%7Chealth%7CLIMIT%7C%3F%2Fx%20y.wav")
        XCTAssertEqual(VoiceURL.url(base: base, key: "a-b_c.d~e")?.absoluteString, "http://localhost:7700/api/voice/alert/a-b_c.d~e.wav")
    }

    func testVoiceURLKeepsAnEncodedSlashInOneSegment() throws {
        let url = try XCTUnwrap(VoiceURL.url(base: base, key: "a/b"))
        XCTAssertEqual(url.path, "/api/voice/alert/a/b.wav")  // decoded view; the wire form is %2F
        XCTAssertTrue(url.absoluteString.hasSuffix("a%2Fb.wav"))
    }

    func testToneIsAValidWAV() {
        for level in [NotifyLevel.warning, .call] {
            let d = AlertTone.wav(for: level)
            XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: d[8..<16], as: UTF8.self), "WAVEfmt ")
            XCTAssertEqual(String(decoding: d[36..<40], as: UTF8.self), "data")
            let dataBytes = d[40..<44].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            XCTAssertEqual(dataBytes, d.count - 44)
            XCTAssertLessThan(d.count, 40_000)
        }
        XCTAssertNotEqual(AlertTone.wav(for: .warning), AlertTone.wav(for: .call))
    }

    // MARK: feed flag

    func testAlertsLoadedOnlyAfterAList() {
        var r = FeedReducer()
        XCTAssertFalse(r.state.alertsLoaded)
        r.apply(.summary(SupervisorSummary()))
        XCTAssertFalse(r.state.alertsLoaded)
        r.apply(.alert(AlertEvent(items: [], initial: true)))
        XCTAssertTrue(r.state.alertsLoaded)
        r.lost(nil)
        XCTAssertTrue(r.state.alertsLoaded)
    }
}
