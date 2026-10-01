// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The `radio` SSE stream, on its own connection so RADIO never disturbs the alert feed.
/// Same rules as `LiveFeed`: reconnect with `Backoff`, 60 s without an event is a drop. Read only.
/// The callbacks may be called from any thread.
public final class RadioStream: @unchecked Sendable {
    public static let topics = "radio"

    private let client: ATCClient
    private let onUp: @Sendable () -> Void
    private let onDown: @Sendable () -> Void
    private let onItems: @Sendable ([RadioTransmission]) -> Void
    private let lock = NSLock()
    private var current: Task<Void, Error>?

    /// `onUp` fires on the first event of each connection (atc sends a `ping` at once), `onDown` when it ends.
    public init(
        client: ATCClient,
        onUp: @escaping @Sendable () -> Void,
        onDown: @escaping @Sendable () -> Void,
        onItems: @escaping @Sendable ([RadioTransmission]) -> Void
    ) {
        self.client = client
        self.onUp = onUp
        self.onDown = onDown
        self.onItems = onItems
    }

    /// Runs until the task is cancelled.
    public func run() async {
        var backoff = Backoff()
        while !Task.isCancelled {
            let session = Session()
            let child = Task { try await self.stream(session) }
            lock.withLock { current = child }
            do {
                try await withTaskCancellationHandler { try await child.value } onCancel: { child.cancel() }
            } catch {
                if Task.isCancelled { return }
            }
            if session.wasUp { onDown() }
            if session.gotEvent { backoff.reset() }
            let delay = backoff.nextDelay()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// Ends the open connection so `run` reconnects; for wake and network changes.
    public func dropConnection() {
        lock.withLock { current }?.cancel()
    }

    private final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var watchdog = Watchdog(startedAt: Date())
        private var got = false

        var gotEvent: Bool { lock.withLock { got } }
        var wasUp: Bool { lock.withLock { got } }
        var isDead: Bool { lock.withLock { watchdog.isDead(at: Date()) } }
        /// True for the first event of the connection.
        func saw() -> Bool {
            lock.withLock {
                watchdog.sawEvent(at: Date())
                defer { got = true }
                return !got
            }
        }
    }

    private func stream(_ session: Session) async throws {
        let events = client.events(topics: Self.topics)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                for try await event in events {
                    if session.saw() { onUp() }
                    if case .radio(let items) = event, !items.isEmpty { onItems(items) }
                }
                throw URLError(.networkConnectionLost)
            }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    if session.isDead { throw URLError(.timedOut) }
                }
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
