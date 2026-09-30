// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin, read-only client: GET and the SSE stream. Logic lives in the pure files.
public struct ATCClient {
    public static let defaultBaseURL = URL(string: "http://localhost:7700")!
    public static let eventTopics = "alert,summary,version"

    public var baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = ATCClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// GET request for a path such as "/api/supervisor-alerts".
    public func request(_ path: String, query: [URLQueryItem] = [], accept: String = "application/json") -> URLRequest {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        var req = URLRequest(url: parts.url!)
        req.httpMethod = "GET"
        req.setValue(accept, forHTTPHeaderField: "Accept")
        return req
    }

    public func alerts() async throws -> [SupervisorAlert] {
        try ATCDecoding.alerts(from: try await get(request("/api/supervisor-alerts")))
    }

    public func summary() async throws -> SupervisorSummary {
        try ATCDecoding.summary(from: try await get(request("/api/supervisor-summary")))
    }

    /// DUTY's state for the popover row (D6). GET only; the `duty` SSE topic is never read.
    public func dutyStatus() async throws -> DutyStatus {
        try ATCDecoding.duty(from: try await get(request("/api/duty/status")))
    }

    /// The newest transmissions on one frequency, oldest first. Only the hint uses it; nothing from it is played.
    public func radio(freq: RadioFreq, limit: Int = 1) async throws -> [RadioTransmission] {
        let query = [URLQueryItem(name: "freq", value: freq.rawValue), URLQueryItem(name: "limit", value: String(limit))]
        return try ATCDecoding.radio(from: try await get(request("/api/radio", query: query)))
    }

    /// The event stream. It ends with an error when the connection drops;
    /// the caller decides when to reconnect (see `Backoff`, `Watchdog`).
    public func events(topics: String = ATCClient.eventTopics, lastEventID: String? = nil) -> AsyncThrowingStream<ATCEvent, Error> {
        var req = request("/api/events", query: [URLQueryItem(name: "topics", value: topics)], accept: "text/event-stream")
        req.timeoutInterval = SSEConnection.idleTimeout
        if let lastEventID { req.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
        return SSEConnection.stream(request: req)
    }

    private func get(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ATCError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw ATCError.badStatus(http.statusCode) }
        return data
    }
}

/// Delegate-based streaming, since `URLSession.bytes` isn't on Linux.
/// The delegate queue is serial, so `parser` is only touched from one thread.
private final class SSEConnection: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    // Finite on purpose: an infinite timeout traps in swift-corelibs-foundation.
    // Dead connections are caught by `Watchdog` (60 s), well before this.
    static let idleTimeout: TimeInterval = 3_600

    private var parser = SSEParser()
    private let continuation: AsyncThrowingStream<ATCEvent, Error>.Continuation

    private init(_ continuation: AsyncThrowingStream<ATCEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    static func stream(request: URLRequest) -> AsyncThrowingStream<ATCEvent, Error> {
        AsyncThrowingStream { continuation in
            let connection = SSEConnection(continuation)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = idleTimeout
            let session = URLSession(configuration: config, delegate: connection, delegateQueue: nil)
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation.finish(throwing: ATCError.badStatus(http.statusCode))
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for raw in parser.feed(data) {
            do {
                continuation.yield(try ATCEvent(raw))
            } catch {
                // One bad event body doesn't end the stream; unsupported summary versions do.
                if case ATCError.unsupportedVersion = error { continuation.finish(throwing: error); return }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.finish(throwing: error ?? URLError(.networkConnectionLost))
    }
}
