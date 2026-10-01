// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Everything the UI shows comes from this value.
public struct FeedState: Equatable, Sendable {
    public var connection: Connection = .connecting
    public var summary: SupervisorSummary?
    public var alerts: [SupervisorAlert] = []
    /// True once an alert list has really arrived (an `alert` event or a GET). Before that `alerts`
    /// is only the empty default and must not be taken as a baseline for new-key detection.
    public var alertsLoaded = false

    public init() {}
}

/// Pure state changes for `LiveFeed`.
public struct FeedReducer: Sendable {
    public private(set) var state = FeedState()

    public init() {}

    public mutating func connecting() { state.connection = .connecting }

    /// Any event proves the connection is up.
    public mutating func apply(_ event: ATCEvent) {
        state.connection = .live
        switch event {
        case .alert(let e):
            state.alerts = e.items
            state.alertsLoaded = true
        case .summary(let s): state.summary = s
        case .version, .radio, .ping, .other: break
        }
    }

    /// Data from a plain GET (Refresh). Doesn't change the connection state.
    public mutating func apply(summary: SupervisorSummary, alerts: [SupervisorAlert]) {
        state.summary = summary
        state.alerts = alerts
        state.alertsLoaded = true
    }

    /// The stream ended. The last data stays, but the UI hides it while not live.
    public mutating func lost(_ error: Error?) {
        if case .unsupportedVersion? = error as? ATCError { state.connection = .unsupported } else { state.connection = .unreachable }
    }
}

/// Keeps the SSE stream open: reconnects with `Backoff`, treats 60 s of silence as a drop.
/// Read only. `onChange` may be called from any thread.
public final class LiveFeed: @unchecked Sendable {
    private let client: ATCClient
    private let onChange: @Sendable (FeedState) -> Void
    private let lock = NSLock()
    private var reducer = FeedReducer()
    private var current: Task<Void, Error>?

    public init(client: ATCClient, onChange: @escaping @Sendable (FeedState) -> Void) {
        self.client = client
        self.onChange = onChange
    }

    public var state: FeedState { lock.withLock { reducer.state } }

    private func update(_ change: (inout FeedReducer) -> Void) {
        let (old, new): (FeedState, FeedState) = lock.withLock {
            let old = reducer.state
            change(&reducer)
            return (old, reducer.state)
        }
        if old != new { onChange(new) }
    }

    /// Runs until the task is cancelled.
    public func run() async {
        var backoff = Backoff()
        while !Task.isCancelled {
            update { $0.connecting() }
            let session = Session()
            let child = Task { try await self.stream(session) }
            lock.withLock { current = child }
            do {
                try await withTaskCancellationHandler { try await child.value } onCancel: { child.cancel() }
            } catch {
                if Task.isCancelled { return }
                update { $0.lost(error) }
            }
            if session.gotEvent { backoff.reset() }
            let delay = backoff.nextDelay()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    /// Ends the open connection so `run` reconnects (with its backoff). For wake and network changes,
    /// when the old connection is dead but the watchdog has not noticed yet. Keeps the last alerts.
    public func dropConnection() {
        lock.withLock { current }?.cancel()
    }

    /// One-off GET of both bodies for the Refresh button.
    public func refresh() async {
        do {
            async let summary = client.summary()
            async let alerts = client.alerts()
            let (s, a) = try await (summary, alerts)
            update { $0.apply(summary: s, alerts: a) }
        } catch {
            // A failed GET says nothing the stream doesn't already; leave the connection state alone.
        }
    }

    private final class Session: @unchecked Sendable {
        private let lock = NSLock()
        private var watchdog = Watchdog(startedAt: Date())
        private var got = false

        var gotEvent: Bool { lock.withLock { got } }
        var isDead: Bool { lock.withLock { watchdog.isDead(at: Date()) } }
        func saw() { lock.withLock { watchdog.sawEvent(at: Date()); got = true } }
    }

    private func stream(_ session: Session) async throws {
        let events = client.events()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                for try await event in events {
                    session.saw()
                    update { $0.apply(event) }
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
