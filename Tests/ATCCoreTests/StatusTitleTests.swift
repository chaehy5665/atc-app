// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import ATCCore

final class StatusTitleTests: XCTestCase {
    func testTitleWithoutCount() {
        XCTAssertEqual(StatusTitle.text(), "✈")
        XCTAssertEqual(StatusTitle.text(litCount: -1), "✈")
    }

    func testTitleWithCount() {
        XCTAssertEqual(StatusTitle.text(litCount: 3), "✈ 3")
    }
}
