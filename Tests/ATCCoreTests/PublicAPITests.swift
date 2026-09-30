// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
// Plain import, as the app target sees ATCCore: an internal init used by the app fails to compile here, not only on the Mac.
import ATCCore

final class PublicAPITests: XCTestCase {
    // Mirrors AlertOutput.test(base:) in the app target.
    func testSettingsTestAlertBuildsFromPublicAPI() {
        let base = URL(string: "http://localhost:7700")!
        let alert = SupervisorAlert(key: "test|annunciator", group: "alert", level: .warning, text: "테스트 알림", next: "이 알림은 시험용입니다", link: nil)
        let plan = NotifyPlan(notifications: [AlertNotification(alert, level: .warning, base: base)], tone: .warning, voiceKey: nil)
        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.tone, .warning)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(NotifyPlan().isEmpty)
    }
}
