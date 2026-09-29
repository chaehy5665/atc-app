// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import ATCCore

/// Only request building is tested; nothing here talks to a server.
final class ClientTests: XCTestCase {
    func testGetRequest() {
        let c = ATCClient(baseURL: URL(string: "http://localhost:7700")!)
        let r = c.request("/api/supervisor-alerts")
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(r.url?.absoluteString, "http://localhost:7700/api/supervisor-alerts")
        XCTAssertNil(r.httpBody)
    }

    func testEventsQuery() {
        let c = ATCClient()
        let r = c.request("/api/events", query: [URLQueryItem(name: "topics", value: ATCClient.eventTopics)], accept: "text/event-stream")
        XCTAssertEqual(r.url?.absoluteString, "http://localhost:7700/api/events?topics=alert,summary,version")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }
}
