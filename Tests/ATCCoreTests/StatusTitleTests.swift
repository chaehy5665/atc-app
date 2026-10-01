// SPDX-License-Identifier: Apache-2.0
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
