// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class RadioTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func tx(
        _ id: String, _ offset: Double = 10, freq: String = "TOWER", replyTo: String? = nil, open: Bool = false
    ) -> RadioTransmission {
        RadioTransmission(id: id, at: t0.addingTimeInterval(offset), freq: freq, head: "head \(id)", replyTo: replyTo, open: open)
    }

    /// On, connected at t0, TOWER, calls only.
    private func live(_ prefs: RadioPrefs = RadioPrefs(on: true, freq: nil, noise: nil)) -> RadioMonitor {
        var m = RadioMonitor()
        m.configure(prefs, now: t0)
        m.connect(now: t0)
        return m
    }

    private func drain(_ m: inout RadioMonitor) -> [String] {
        var ids: [String] = []
        while let t = m.next(alertBusy: false, quiet: false) { ids.append(t.id) }
        return ids
    }

    // MARK: prefs

    func testDefaultsAreOffTowerCalls() {
        let p = RadioPrefs()
        XCTAssertFalse(p.on)
        XCTAssertEqual(p.freq, .tower)
        XCTAssertEqual(p.noise, .calls)
        XCTAssertEqual(RadioPrefs(on: true, freq: "BOGUS", noise: nil).freq, .tower)
        XCTAssertEqual(RadioPrefs(on: true, freq: "GROUND", noise: "all").noise, .all)
        XCTAssertEqual(RadioFreq.allCases.map(\.rawValue), ["DELIVERY", "TOWER", "GROUND", "COMPANY"])
    }

    // MARK: frequency filter and noise

    func testOnlyTheChosenFrequencyIsQueued() {
        var m = live()
        m.ingest([tx("C-1"), tx("D-1", freq: "DELIVERY"), tx("C-2", freq: "tower")], quiet: false)
        XCTAssertEqual(drain(&m), ["C-1", "C-2"])
        var g = live(RadioPrefs(on: true, freq: "GROUND", noise: nil))
        g.ingest([tx("C-1"), tx("mcc:1", freq: "GROUND")], quiet: false)
        XCTAssertEqual(drain(&g), ["mcc:1"])
    }

    func testNoiseChoices() {
        let items = [
            tx("C-1", open: true), tx("C-2", open: false),
            tx("C-1#readback", replyTo: "C-1"),
        ]
        var calls = live()
        calls.ingest(items, quiet: false)
        XCTAssertEqual(drain(&calls), ["C-1", "C-2"])
        var open = live(RadioPrefs(on: true, freq: nil, noise: "unanswered"))
        open.ingest(items, quiet: false)
        XCTAssertEqual(drain(&open), ["C-1"])
        var all = live(RadioPrefs(on: true, freq: nil, noise: "all"))
        all.ingest(items, quiet: false)
        XCTAssertEqual(drain(&all), ["C-1", "C-2", "C-1#readback"])
    }

    func testChangingNoiseDropsWhatNoLongerFits() {
        var m = live(RadioPrefs(on: true, freq: nil, noise: "all"))
        m.ingest([tx("C-1", open: true), tx("C-1#readback", 11, replyTo: "C-1")], quiet: false)
        m.configure(RadioPrefs(on: true, freq: nil, noise: "calls"), now: t0)
        XCTAssertEqual(drain(&m), ["C-1"])
    }

    // MARK: queue and cap

    func testQueueKeepsTheNewestFiveAndCountsDropped() {
        var m = live()
        m.ingest((1...8).map { tx("C-\($0)", Double($0)) }, quiet: false)
        XCTAssertEqual(m.queue.count, RadioMonitor.queueCap)
        XCTAssertEqual(m.dropped, 3)
        XCTAssertEqual(drain(&m), ["C-4", "C-5", "C-6", "C-7", "C-8"])
    }

    func testPlaysOldestFirstEvenIfSentOutOfOrder() {
        var m = live()
        m.ingest([tx("C-2", 20), tx("C-1", 10)], quiet: false)
        XCTAssertEqual(drain(&m), ["C-1", "C-2"])
    }

    func testAlertBusyHoldsTheQueueUntilItIsFree() {
        var m = live()
        m.ingest([tx("C-1"), tx("C-2", 11)], quiet: false)
        XCTAssertNil(m.next(alertBusy: true, quiet: false))
        XCTAssertEqual(m.queue.count, 2)
        XCTAssertEqual(m.next(alertBusy: false, quiet: false)?.id, "C-1")
    }

    // MARK: once only, and no replay

    func testAChangedCallIsNotPlayedAgain() {
        var m = live()
        m.ingest([tx("C-1", open: true)], quiet: false)
        XCTAssertEqual(drain(&m), ["C-1"])
        m.ingest([tx("C-1", open: false)], quiet: false)
        XCTAssertEqual(drain(&m), [])
    }

    func testNothingRecordedBeforeTurningOnOrConnectingIsHeard() {
        var m = live()
        m.ingest([tx("old", -5), tx("new", 5)], quiet: false)
        XCTAssertEqual(drain(&m), ["new"])
    }

    func testReconnectDoesNotReplayWhatWasMissedOrAlreadyHeard() {
        var m = live()
        m.ingest([tx("C-1", 5)], quiet: false)
        m.disconnect()
        // The stream is down: nothing queued or played.
        XCTAssertEqual(m.ingest([tx("C-2", 20)], quiet: false), 0)
        XCTAssertNil(m.next(alertBusy: false, quiet: false))
        m.connect(now: t0.addingTimeInterval(60))
        // A burst on reconnect: C-1 again (changed), C-2 recorded while away, C-3 after the reconnect.
        m.ingest([tx("C-1", 5), tx("C-2", 20), tx("C-3", 61)], quiet: false)
        XCTAssertEqual(drain(&m), ["C-3"])
    }

    func testDisconnectDropsTheWaitingQueue() {
        var m = live()
        m.ingest([tx("C-1"), tx("C-2", 11)], quiet: false)
        m.disconnect()
        XCTAssertTrue(m.queue.isEmpty)
        XCTAssertNil(m.next(alertBusy: false, quiet: false))
    }

    func testSeedNeverPlaysAndSetsTheHint() {
        var m = live()
        m.seed([tx("C-1", 5), tx("C-2", 9), tx("D-1", 12, freq: "DELIVERY")])
        XCTAssertEqual(m.last?.id, "C-2")
        m.ingest([tx("C-2", 9)], quiet: false)
        XCTAssertEqual(drain(&m), [])
    }

    func testTurningOnOrChangingFrequencyStartsFresh() {
        var m = RadioMonitor()
        m.configure(RadioPrefs(on: true, freq: nil, noise: nil), now: t0.addingTimeInterval(100))
        m.connect(now: t0.addingTimeInterval(100))
        m.ingest([tx("before", 50), tx("after", 110)], quiet: false)
        XCTAssertEqual(drain(&m), ["after"])
        m.ingest([tx("g-1", 120, freq: "GROUND")], quiet: false)
        XCTAssertEqual(m.last?.id, "after")
        m.configure(RadioPrefs(on: true, freq: "GROUND", noise: nil), now: t0.addingTimeInterval(200))
        XCTAssertNil(m.last)
        m.ingest([tx("g-1", 120, freq: "GROUND"), tx("g-2", 210, freq: "GROUND")], quiet: false)
        XCTAssertEqual(drain(&m), ["g-2"])
    }

    func testOffStopsEverything() {
        var m = live()
        m.ingest([tx("C-1")], quiet: false)
        m.configure(RadioPrefs(), now: t0)
        XCTAssertNil(m.next(alertBusy: false, quiet: false))
        XCTAssertEqual(m.ingest([tx("C-2", 20)], quiet: false), 0)
        XCTAssertNil(RadioHint(m))
    }

    // MARK: quiet hours

    func testQuietHoursQueueNothingAndDropWhatWaits() {
        var m = live()
        XCTAssertEqual(m.ingest([tx("C-1")], quiet: true), 0)
        m.ingest([tx("C-2", 11)], quiet: false)
        XCTAssertNil(m.next(alertBusy: false, quiet: true))
        XCTAssertTrue(m.queue.isEmpty)
        // A call that arrived in quiet hours is not played after them either.
        m.ingest([tx("C-1")], quiet: false)
        XCTAssertEqual(drain(&m), [])
    }

    // MARK: hint

    func testHint() {
        var m = live()
        XCTAssertEqual(RadioHint(m)?.title, "RADIO ● TOWER")
        XCTAssertEqual(RadioHint(m)?.detail, "대기 중")
        m.ingest([tx("C-1")], quiet: false)
        XCTAssertEqual(RadioHint(m)?.detail, "head C-1")
        m.disconnect()
        XCTAssertEqual(RadioHint(m)?.title, "RADIO ● TOWER (연결 안 됨)")
    }

    // MARK: decoding and URLs

    func testDecodesTheRadioEvent() throws {
        let body = """
        {"transmissions":[{"id":"C-0192","at":"2026-09-30T08:12:17.304Z","freq":"TOWER","from":"TOWER","to":"GOLF (TEAM_G)","aircraft":"TEAM_G","kind":"INFO","flight":"ATC-184","head":"TOWER → GOLF · INFO · ATC-184","body":"free text","open":true,"overdueAt":"2026-09-30T08:22:17.304Z","airport":"ATCC"},
        {"id":"C-0192#readback","at":"2026-09-30T08:13:00Z","freq":"TOWER","kind":"READBACK","head":"GOLF → TOWER · READBACK · ATC-184","replyTo":"C-0192"}]}
        """
        guard case .radio(let items) = try ATCEvent(SSEEvent(name: "radio", data: body)) else { return XCTFail() }
        XCTAssertEqual(items.map(\.id), ["C-0192", "C-0192#readback"])
        XCTAssertTrue(items[0].open && items[0].isCall)
        XCTAssertEqual(items[1].replyTo, "C-0192")
        XCTAssertFalse(items[1].open)
        XCTAssertEqual(items[0].head, "TOWER → GOLF · INFO · ATC-184")
    }

    func testWavURLEscapesTheId() {
        let base = URL(string: "http://localhost:7700/")!
        XCTAssertEqual(RadioURL.wav(base: base, id: "C-0007#readback")?.absoluteString, "http://localhost:7700/api/radio/C-0007%23readback.wav")
        XCTAssertEqual(RadioURL.wav(base: base, id: "report:ATC-1:2026")?.absoluteString, "http://localhost:7700/api/radio/report%3AATC-1%3A2026.wav")
    }

    func testRadioLineAddsHeight() {
        let p = PanelContent(FeedState(), base: URL(string: "http://localhost:7700")!)
        let status = StatusRows(duty: nil, work: nil, radio: RadioHint(live()))
        XCTAssertGreaterThanOrEqual(PanelLayout.height(for: p, expansion: LampExpansion(), status: status), PanelLayout.height(for: p, expansion: LampExpansion()))
    }
}
