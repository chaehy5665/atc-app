// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import ATCCore

final class SSETests: XCTestCase {
    private func parse(_ chunks: [Data]) -> [SSEEvent] {
        var p = SSEParser()
        return chunks.flatMap { p.feed($0) }
    }

    private func parse(_ s: String) -> [SSEEvent] { parse([Data(s.utf8)]) }

    func testSimpleEvent() {
        XCTAssertEqual(parse("event: alert\ndata: {\"a\":1}\n\n"), [SSEEvent(name: "alert", data: "{\"a\":1}")])
    }

    func testDefaultNameIsMessage() {
        XCTAssertEqual(parse("data: hi\n\n"), [SSEEvent(name: "message", data: "hi")])
    }

    func testMultiLineData() {
        XCTAssertEqual(parse("data: a\ndata: b\ndata:\ndata: c\n\n").first?.data, "a\nb\n\nc")
    }

    func testIdAndRetry() {
        var p = SSEParser()
        let e = p.feed(Data("id: 7\nretry: 3000\ndata: x\n\n".utf8))
        XCTAssertEqual(e, [SSEEvent(name: "message", data: "x", id: "7", retry: 3000)])
        XCTAssertEqual(p.lastEventID, "7")
        // id and retry apply to one event only, lastEventID persists.
        XCTAssertEqual(p.feed(Data("data: y\n\n".utf8)), [SSEEvent(name: "message", data: "y")])
        XCTAssertEqual(p.lastEventID, "7")
    }

    func testBadRetryIgnored() {
        XCTAssertNil(parse("retry: soon\ndata: x\n\n").first?.retry)
    }

    func testCommentsIgnored() {
        XCTAssertEqual(parse(": keepalive\n\n"), [])
        XCTAssertEqual(parse(": c\nevent: ping\ndata: {}\n\n"), [SSEEvent(name: "ping", data: "{}")])
    }

    func testPingWithoutDataStillDispatches() {
        XCTAssertEqual(parse("event: ping\n\n"), [SSEEvent(name: "ping", data: "")])
    }

    func testBlankLinesWithNothingPendingDispatchNothing() {
        XCTAssertEqual(parse("\n\n\n"), [])
    }

    func testCRLFAndCR() {
        XCTAssertEqual(parse("event: a\r\ndata: 1\r\n\r\n").count, 1)
        // A CR at the very end waits for a possible LF, so bytes follow here.
        XCTAssertEqual(parse("event: a\rdata: 1\r\rx").first, SSEEvent(name: "a", data: "1"))
        XCTAssertEqual(parse("event: a\rdata: 1\r\r"), [])
        XCTAssertEqual(parse("data: 1\r\n\r\ndata: 2\n\n").map(\.data), ["1", "2"])
    }

    func testFieldWithoutColonAndSpaceStripping() {
        XCTAssertEqual(parse("data\n\n"), [SSEEvent(name: "message", data: "")])
        XCTAssertEqual(parse("data:  two spaces\n\n").first?.data, " two spaces")
        XCTAssertEqual(parse("data:nospace\n\n").first?.data, "nospace")
        XCTAssertEqual(parse("unknown: x\ndata: y\n\n").first?.data, "y")
    }

    func testColonInValue() {
        XCTAssertEqual(parse("data: a:b:c\n\n").first?.data, "a:b:c")
    }

    func testBOMAtStart() {
        var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
        bytes += Array("event: a\ndata: 1\n\n".utf8)
        XCTAssertEqual(parse([Data(bytes)]), [SSEEvent(name: "a", data: "1")])
    }

    func testEveryChunkSplit() {
        let stream = "event: version\ndata: {\"v\":1}\r\n\r\n: c\r\nevent: alert\ndata: a\ndata: b\nid: 9\n\nevent: ping\ndata: {}\r\rx"
        let bytes = Array(stream.utf8)
        let whole = parse([Data(bytes)])
        XCTAssertEqual(whole.count, 3)
        for cut in 0...bytes.count {
            XCTAssertEqual(parse([Data(bytes[..<cut]), Data(bytes[cut...])]), whole, "cut at \(cut)")
        }
        // One byte at a time.
        XCTAssertEqual(parse(bytes.map { Data([$0]) }), whole)
    }

    func testMultibyteCharacterSplitAcrossChunks() {
        let bytes = Array("data: 종료된 세션\n\n".utf8)
        for cut in 0...bytes.count {
            XCTAssertEqual(parse([Data(bytes[..<cut]), Data(bytes[cut...])]).first?.data, "종료된 세션", "cut at \(cut)")
        }
    }

    func testIncompleteEventWaits() {
        var p = SSEParser()
        XCTAssertEqual(p.feed(Data("event: a\ndata: 1\n".utf8)), [])
        XCTAssertEqual(p.feed(Data("\n".utf8)), [SSEEvent(name: "a", data: "1")])
    }

    func testRealisticStreamWithTypedEvents() throws {
        let alerts = String(decoding: try Fixtures.data("alert-event-initial"), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "")
        let wire = "event: version\ndata: {\"head\":\"abc\"}\n\nevent: alert\ndata: \(alerts)\n\nevent: ping\ndata: {}\n\n"
        let events = try parse(wire).map(ATCEvent.init)
        XCTAssertEqual(events.count, 3)
        guard case .alert(let e) = events[1] else { return XCTFail() }
        XCTAssertEqual(e.items.count, 14)
        XCTAssertEqual(events[2], .ping)
    }
}
