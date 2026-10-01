// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ATC-248 (GL1b): the polling rules for the Linear issue list, with the network injected like `GitHubClient`.
// The app target supplies the URLSession transport and the token source. Linear has no ETag, so every page is a
// counted request; one refresh is one query (up to five pages), and the app polls only while it is looked at.
// Read only: the one request kind is a GraphQL `query` (`LinearRequests`), and anything else is refused here.

/// The same shapes as GitHub's, named for the call site.
public typealias LinearTransport = GitHubTransport
public typealias LinearTokenSource = GitHubTokenSource

public enum LinearStatus: Equatable, Sendable {
    case idle
    case ok
    /// Linear said `RATELIMITED` and the back-off runs until then.
    case rateLimited(until: Date)
    /// The app's own hourly cap is spent until then.
    case capReached(until: Date)
    case needsSignIn
    /// Redacted, short.
    case error(String)
}

public struct LinearSnapshot: Equatable, Sendable {
    public var issues: [LinearIssue] = []
    public var status: LinearStatus = .idle
    public var fetchedAt: Date?
    /// More issues exist than the pages read (`LinearRequests.maxPages`).
    public var truncated = false

    public init() {}
}

public final class LinearClient {
    /// 20 percent of Linear's 5,000 requests an hour for an OAuth app (design 11.5).
    public static let hourlyCap = 1_000

    private let transport: LinearTransport
    private let tokens: LinearTokenSource
    private let now: () -> Date
    private let random: () -> Double

    public private(set) var teams: [TeamKey] = []
    public private(set) var snapshot = LinearSnapshot()
    public internal(set) var budget = RateBudget(cap: LinearClient.hourlyCap)
    private var authFailed = false

    public init(transport: LinearTransport, tokens: LinearTokenSource,
                now: @escaping () -> Date = Date.init, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.transport = transport
        self.tokens = tokens
        self.now = now
        self.random = random
    }

    public func setTeams(_ list: [TeamKey]) {
        guard list != teams else { return }
        teams = list
        snapshot.issues = []
        snapshot.fetchedAt = nil
    }

    /// Sign-in changed (in or out): forget everything held in memory, including a failed-auth stop.
    public func reset() {
        authFailed = false
        snapshot = LinearSnapshot()
    }

    // MARK: Refresh

    private enum Outcome<T> {
        case success(T)
        case stop(LinearStatus)
        case failure(String)
    }

    /// One pass: every page of the open issues of the configured teams. Call it serially.
    @discardableResult
    public func refresh() async -> LinearSnapshot {
        let started = now()
        if authFailed { return finish(.needsSignIn, at: started) }
        if teams.isEmpty {
            snapshot.issues = []
            return finish(.idle, at: started)
        }
        var all: [LinearIssue] = []
        var cursor: String?
        var pages = 0
        var more = false
        while pages < LinearRequests.maxPages {
            pages += 1
            switch await get(LinearRequests.openIssues(teams: teams, after: cursor)) {
            case .stop(let s):
                return finish(s, at: started)  // keep the previous list; the line says why
            case .failure(let message):
                return finish(.error(message), at: started)
            case .success(let page):
                all += page.issues
                more = page.hasNext
                guard page.hasNext, let next = page.endCursor else { more = false; pages = LinearRequests.maxPages; continue }
                cursor = next
            }
        }
        snapshot.issues = all.sorted { $0.updatedAt > $1.updatedAt }
        snapshot.truncated = more
        return finish(.ok, at: started)
    }

    private func finish(_ status: LinearStatus, at date: Date) -> LinearSnapshot {
        snapshot.status = status
        if status == .ok || status == .idle { snapshot.fetchedAt = date }
        return snapshot
    }

    // MARK: One request

    /// A budgeted query with the token, one refresh-and-retry on an auth failure, and back-off on `RATELIMITED`.
    private func get(_ request: LinearRequest) async -> Outcome<LinearPage> {
        guard request.isQuery else { return .failure("not a query") }
        var refreshed = false
        while true {
            let at = now()
            switch budget.verdict(at: at) {
            case .allowed: break
            case .backingOff(let until): return .stop(.rateLimited(until: until))
            case .capReached(let until): return .stop(.capReached(until: until))
            }
            let token: String
            switch await tokens.accessToken(forceRefresh: refreshed) {
            case .token(let t): token = t
            case .signedOut, .failed:
                authFailed = true
                return .stop(.needsSignIn)
            }
            let response: GitHubResponse
            do {
                response = try await transport.send(request.urlRequest(token: token))
            } catch {
                budget.record(at: at, notModified: false)
                return .failure(Redact.error(error, extra: [token]))
            }
            budget.record(at: at, notModified: false)

            switch LinearParse.failure(status: response.status, body: response.body) {
            case .none:
                budget.succeeded()
                guard let page = LinearParse.issues(response.body) else { return .failure("unreadable list") }
                return .success(page)
            case .auth:
                if refreshed {
                    authFailed = true
                    return .stop(.needsSignIn)
                }
                refreshed = true
            case .rateLimited:
                let until = budget.limited(info: LinearParse.rateLimit(response.headers), at: at, unit: random())
                return .stop(.rateLimited(until: until))
            case .other(let message):
                return .failure(message)
            }
        }
    }
}
