// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ATC-247 (GL1a): the polling rules for the PR list, with the network injected so Linux tests can run them.
// The app target supplies a URLSession transport and the token source; this file never sends anything itself.
//
// Cost (design 11.5): one list request per repository per refresh (a `304` is free); a CI rollup (check runs
// and combined status, two requests) only for a PR whose `updated_at` changed, that has none yet, or whose
// last rollup was still pending; one `/user` per sign-in. Every request is a GET.

public struct GitHubResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol GitHubTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> GitHubResponse
}

public enum GitHubToken: Equatable, Sendable {
    case token(String)
    case signedOut
    /// A refresh was needed and did not work: the user has to sign in again.
    case failed
}

public protocol GitHubTokenSource: AnyObject {
    /// The access token, refreshed first when `TokenPolicy` says so or when `forceRefresh` (after a 401).
    func accessToken(forceRefresh: Bool) async -> GitHubToken
}

public enum GitHubStatus: Equatable, Sendable {
    case idle
    case ok
    /// GitHub refused (403/429) and the back-off runs until then.
    case rateLimited(until: Date)
    /// The app's own hourly cap is spent until then.
    case capReached(until: Date)
    case needsSignIn
    /// Redacted, short, no URL query.
    case error(String)
}

public struct GitHubSnapshot: Equatable, Sendable {
    public var pulls: [PullRequest] = []
    /// The signed-in user's login, for the review-requested filter; nil until `/user` answered.
    public var login: String?
    public var status: GitHubStatus = .idle
    public var fetchedAt: Date?
    /// Repositories whose list could not be read this time (shown by name in the window only).
    public var failedRepos: [String] = []

    public init() {}
}

public final class GitHubClient {
    public static let maxPagesPerRepo = 5

    private let transport: GitHubTransport
    private let tokens: GitHubTokenSource
    private let now: () -> Date
    private let random: () -> Double

    public private(set) var repos: [RepoRef] = []
    public private(set) var snapshot = GitHubSnapshot()
    public internal(set) var budget: RateBudget
    private var cache = ETagCache()
    private var authFailed = false

    public init(transport: GitHubTransport, tokens: GitHubTokenSource, cap: Int = RateBudget.defaultCap,
                now: @escaping () -> Date = Date.init, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.transport = transport
        self.tokens = tokens
        self.budget = RateBudget(cap: cap)
        self.now = now
        self.random = random
    }

    public func setRepos(_ list: [RepoRef]) {
        guard list != repos else { return }
        repos = list
        snapshot.pulls.removeAll { p in !list.contains(p.repo) }
    }

    public func setCap(_ cap: Int) { budget.setCap(cap) }

    /// Sign-in changed (in, out, or a new App): forget everything held in memory, including a failed-auth stop.
    public func reset() {
        cache.removeAll()
        authFailed = false
        snapshot = GitHubSnapshot()
    }

    // MARK: Refresh

    /// One pass over every repository. Call it serially (the app never overlaps two).
    @discardableResult
    public func refresh() async -> GitHubSnapshot {
        let started = now()
        if authFailed { return finish(.needsSignIn, at: started) }
        if repos.isEmpty {
            snapshot.pulls = []
            return finish(.idle, at: started)
        }
        var stop: GitHubStatus?
        var failed: [String] = []

        if snapshot.login == nil {
            switch await get(GitHubRequests.currentUser) {
            case .success(let r): snapshot.login = GitHubParse.login(r.body)
            case .stop(let s): stop = s
            case .failure: break  // the filter just stays empty
            }
        }

        var merged: [PullRequest] = []
        var firstError: String?
        for repo in repos where stop == nil {
            switch await readList(repo) {
            case .success(let list):
                merged += await withCI(list, repo: repo, stop: &stop)
            case .stop(let s):
                stop = s
            case .failure(let message):
                failed.append(repo.fullName)
                firstError = firstError ?? message
                merged += snapshot.pulls.filter { $0.repo == repo }  // keep what was known
            }
        }
        if stop != nil {
            // Keep the previous list for the repos not read this time; the line says why.
            let read = Set(merged.map(\.repo))
            merged += snapshot.pulls.filter { !read.contains($0.repo) }
        }
        snapshot.pulls = merged.sorted { $0.updatedAt > $1.updatedAt }
        snapshot.failedRepos = failed
        if let stop { return finish(stop, at: started) }
        if let firstError, failed.count == repos.count { return finish(.error(firstError), at: started) }
        return finish(.ok, at: started)
    }

    private func finish(_ status: GitHubStatus, at date: Date) -> GitHubSnapshot {
        snapshot.status = status
        if status == .ok || status == .idle { snapshot.fetchedAt = date }
        return snapshot
    }

    // MARK: Lists

    private enum Outcome<T> {
        case success(T)
        /// Not an error of this request: the whole pass must stop (rate limit, cap, sign-in).
        case stop(GitHubStatus)
        case failure(String)
    }

    /// All pages of one repository's open PRs.
    private func readList(_ repo: RepoRef) async -> Outcome<[PullRequest]> {
        var request: GitHubRequest? = GitHubRequests.pulls(repo)
        var all: [PullRequest] = []
        var pages = 0
        while let next = request, pages < Self.maxPagesPerRepo {
            pages += 1
            switch await get(next) {
            case .stop(let s): return .stop(s)
            case .failure(let m): return .failure(m)
            case .success(let r):
                guard let page = GitHubParse.pulls(r.body, repo: repo) else { return .failure("unreadable list") }
                all += page
                request = GitHubParse.nextLink(r.headers["link"]).flatMap(GitHubRequests.page(url:))
            }
        }
        return .success(all)
    }

    /// Attaches a CI rollup to each PR: carried over when the PR did not change, fetched when it did.
    private func withCI(_ list: [PullRequest], repo: RepoRef, stop: inout GitHubStatus?) async -> [PullRequest] {
        let known = Dictionary(snapshot.pulls.filter { $0.repo == repo }.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [PullRequest] = []
        for var pr in list {
            if let old = known[pr.number], old.updatedAtRaw == pr.updatedAtRaw, old.headSHA == pr.headSHA, let ci = old.ci, !ci.isPending {
                pr.ci = ci
            } else if stop == nil {
                switch await readCI(pr) {
                case .success(let ci): pr.ci = ci
                case .stop(let s): stop = s; pr.ci = known[pr.number]?.ci
                case .failure: pr.ci = known[pr.number]?.ci
                }
            } else {
                pr.ci = known[pr.number]?.ci
            }
            out.append(pr)
        }
        return out
    }

    private func readCI(_ pr: PullRequest) async -> Outcome<CheckRollup> {
        guard let runsRequest = GitHubRequests.checkRuns(pr.repo, sha: pr.headSHA),
              let statusRequest = GitHubRequests.combinedStatus(pr.repo, sha: pr.headSHA)
        else { return .failure("bad head") }
        var runs: [CheckRun] = []
        switch await get(runsRequest) {
        case .stop(let s): return .stop(s)
        case .failure(let m): return .failure(m)
        case .success(let r): runs = GitHubParse.checkRuns(r.body) ?? []
        }
        var state: String?
        switch await get(statusRequest) {
        case .stop(let s): return .stop(s)
        case .failure(let m): return .failure(m)
        case .success(let r): state = GitHubParse.combinedState(r.body)
        }
        return .success(CheckRollup(checkRuns: runs, combinedState: state))
    }

    // MARK: One request

    /// A GET with budget, token, `If-None-Match`, one refresh-and-retry on 401, and back-off on 403/429.
    /// A `304` answers with the cached body, so callers see the same shape either way.
    private func get(_ request: GitHubRequest) async -> Outcome<GitHubResponse> {
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
            let cached = cache.entry(for: request.url)
            let response: GitHubResponse
            do {
                response = try await transport.send(request.urlRequest(token: token, etag: cached?.etag))
            } catch {
                budget.record(at: at, notModified: false)
                return .failure(Redact.error(error, extra: [token]))
            }
            let info = GitHubParse.rateLimit(response.headers)
            budget.record(at: at, notModified: response.status == 304)

            switch response.status {
            case 200..<300:
                budget.succeeded()
                if let etag = response.headers["etag"] {
                    cache.store(.init(etag: etag, body: response.body, link: response.headers["link"]), for: request.url)
                }
                return .success(response)
            case 304:
                budget.succeeded()
                guard let cached else { return .failure("unexpected 304") }
                var headers = response.headers
                if let link = cached.link { headers["link"] = link }
                return .success(GitHubResponse(status: 200, headers: headers, body: cached.body))
            case 401:
                if refreshed {
                    authFailed = true
                    return .stop(.needsSignIn)
                }
                refreshed = true
                continue
            case 403, 429:
                if GitHubParse.isRateLimited(status: response.status, info: info, body: response.body) {
                    let until = budget.limited(info: info, at: at, unit: random())
                    return .stop(.rateLimited(until: until))
                }
                return .failure("HTTP \(response.status)")
            default:
                return .failure("HTTP \(response.status)")
            }
        }
    }
}
