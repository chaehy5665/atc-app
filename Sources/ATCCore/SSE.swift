// SPDX-License-Identifier: Apache-2.0
import Foundation

public struct SSEEvent: Equatable, Sendable {
    /// The `event:` field, "message" when absent.
    public var name: String
    /// `data:` lines joined with "\n".
    public var data: String
    public var id: String?
    public var retry: Int?

    public init(name: String = "message", data: String = "", id: String? = nil, retry: Int? = nil) {
        self.name = name
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// Incremental `text/event-stream` parser. Feed bytes in any chunking; complete
/// events come back. Lines end in LF, CRLF or CR. Comment lines are dropped.
///
/// A CR at the very end of the input waits for the next byte, in case it is half of CRLF.
///
/// An event is dispatched at a blank line when it has data or a name, so a
/// `ping` with no data still counts as an event (the plain spec would skip it).
public struct SSEParser: Sendable {
    private var buffer: [UInt8] = []
    private var atStart = true
    private var name: String?
    private var dataLines: [String] = []
    private var id: String?
    private var retry: Int?
    private var lastID: String?

    public init() {}

    /// The last `id:` seen, for a `Last-Event-ID` header on reconnect.
    public var lastEventID: String? { lastID }

    public mutating func feed(_ chunk: Data) -> [SSEEvent] {
        buffer.append(contentsOf: chunk)
        var events: [SSEEvent] = []
        var start = 0
        var i = 0
        while i < buffer.count {
            let b = buffer[i]
            guard b == 0x0A || b == 0x0D else { i += 1; continue }
            if b == 0x0D {
                // A lone CR at the end may be the first half of CRLF: wait for more.
                if i + 1 == buffer.count { break }
                let end = i
                i += buffer[i + 1] == 0x0A ? 2 : 1
                if let e = handleLine(buffer[start..<end]) { events.append(e) }
            } else {
                if let e = handleLine(buffer[start..<i]) { events.append(e) }
                i += 1
            }
            start = i
        }
        buffer.removeSubrange(0..<start)
        return events
    }

    private mutating func handleLine(_ bytes: ArraySlice<UInt8>) -> SSEEvent? {
        var bytes = bytes
        if atStart {
            atStart = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        }
        if bytes.isEmpty { return dispatch() }
        if bytes.first == 0x3A { return nil }  // ":" comment

        let line = String(decoding: bytes, as: UTF8.self)
        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }
        switch field {
        case "event": name = value
        case "data": dataLines.append(value)
        case "id": if !value.contains("\0") { id = value; lastID = value }
        case "retry": if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) { retry = Int(value) }
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer { name = nil; dataLines = []; id = nil; retry = nil }
        guard name != nil || !dataLines.isEmpty else { return nil }
        return SSEEvent(name: name ?? "message", data: dataLines.joined(separator: "\n"), id: id, retry: retry)
    }
}
