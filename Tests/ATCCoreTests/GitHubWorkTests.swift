// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ATCCore

// ATC-247 (GL1a). Fixtures are scrubbed: `octo`, `repo-a`, `user-n`, made-up SHAs, no token or Authorization.

private let repoA = RepoRef("octo/repo-a")!
private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

final class RepoRefTests: XCTestCase {
    func testAcceptsOwnerSlashName() {
        XCTAssertEqual(RepoRef("octo/repo-a")?.fullName, "octo/repo-a")
        XCTAssertEqual(RepoRef(" octo/repo.a_1 ")?.name, "repo.a_1")
    }

    func testRejectsAnythingThatCouldChangeThePath() {
        for bad in ["", "octo", "octo/", "/repo", "a/b/c", "octo/..", "../x", "octo/re po", "octo/repo?x=1", "octo/repo#f", "oc.to/repo", "octo/répo", "octo/%2e%2e"] {
            XCTAssertNil(RepoRef(bad), bad)
        }
    }

    func testListParsingDropsDuplicatesAndReportsRejects() {
        let r = RepoRef.parseList("octo/repo-a, octo/repo-b\nocto/repo-a bad//x")
        XCTAssertEqual(r.repos.map(\.fullName), ["octo/repo-a", "octo/repo-b"])
        XCTAssertEqual(r.rejected, ["bad//x"])
    }
}

final class GitHubRequestsTests: XCTestCase {
    func testPullListIsAnHttpsGetOnTheApiHost() {
        let req = GitHubRequests.pulls(repoA).urlRequest(token: "tok-1234", etag: nil)
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.scheme, "https")
        XCTAssertEqual(req.url?.host, "api.github.com")
        XCTAssertEqual(req.url?.path, "/repos/octo/repo-a/pulls")
        let query = req.url?.query ?? ""
        XCTAssertTrue(query.contains("state=open") && query.contains("per_page=50"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1234")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertNil(req.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(req.httpBody, "a GET carries no body")
        XCTAssertFalse(req.url!.absoluteString.contains("tok-1234"), "the token is never in the URL")
    }

    func testEtagBecomesIfNoneMatch() {
        let req = GitHubRequests.pulls(repoA).urlRequest(token: "t", etag: "W/\"abc\"")
        XCTAssertEqual(req.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
    }

    func testCommitRequestsNeedAHexSha() {
        let sha = "1111111111111111111111111111111111111111"
        XCTAssertEqual(GitHubRequests.checkRuns(repoA, sha: sha)?.url.path, "/repos/octo/repo-a/commits/\(sha)/check-runs")
        XCTAssertEqual(GitHubRequests.combinedStatus(repoA, sha: sha)?.url.path, "/repos/octo/repo-a/commits/\(sha)/status")
        XCTAssertNil(GitHubRequests.checkRuns(repoA, sha: "../../user"))
        XCTAssertNil(GitHubRequests.combinedStatus(repoA, sha: "xyz"))
    }

    func testPagesStayOnTheApiHost() {
        XCTAssertNotNil(GitHubRequests.page(url: URL(string: "https://api.github.com/repos/octo/repo-a/pulls?page=2")!))
        XCTAssertNil(GitHubRequests.page(url: URL(string: "http://api.github.com/x")!))
        XCTAssertNil(GitHubRequests.page(url: URL(string: "https://evil.example/x")!))
        XCTAssertNil(GitHubRequests.page(url: URL(string: "https://user:pw@api.github.com/x")!))
        XCTAssertNil(GitHubRequests.page(url: URL(string: "https://api.github.com:8443/x")!))
    }
}

final class GitHubParseTests: XCTestCase {
    func testPullsFixture() throws {
        let pulls = try XCTUnwrap(GitHubParse.pulls(Fixtures.data("github-pulls"), repo: repoA))
        XCTAssertEqual(pulls.map(\.number), [12, 9], "a PR with a foreign page URL or no number is skipped")
        let p = pulls[0]
        XCTAssertEqual(p.title, "Add a retry to the sync step")
        XCTAssertEqual(p.author, "user-1")
        XCTAssertFalse(p.isDraft)
        XCTAssertEqual(p.headSHA, "1111111111111111111111111111111111111111")
        XCTAssertEqual(p.updatedAtRaw, "2026-10-01T09:30:00Z")
        XCTAssertEqual(p.url.absoluteString, "https://github.com/octo/repo-a/pull/12")
        XCTAssertEqual(p.review.requestedReviewers, ["user-2", "User-9"])
        XCTAssertEqual(p.review.requestedTeams, ["team-a"])
        XCTAssertTrue(pulls[1].isDraft)
        XCTAssertEqual(p.id, "octo/repo-a#12")
    }

    func testReviewRequestMatchesLoginIgnoringCase() throws {
        let p = try XCTUnwrap(GitHubParse.pulls(Fixtures.data("github-pulls"), repo: repoA)).first!
        XCTAssertTrue(p.review.requests(login: "user-9"))
        XCTAssertFalse(p.review.requests(login: "user-1"))
        XCTAssertFalse(p.review.requests(login: nil))
    }

    func testNotAnArrayIsNil() {
        XCTAssertNil(GitHubParse.pulls(Data("{\"message\":\"Not Found\"}".utf8), repo: repoA))
        XCTAssertNil(GitHubParse.pulls(Data("nope".utf8), repo: repoA))
    }

    func testChecksStatusAndLogin() throws {
        let runs = try XCTUnwrap(GitHubParse.checkRuns(Fixtures.data("github-check-runs")))
        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(runs[3], CheckRun(status: "in_progress", conclusion: nil))
        XCTAssertEqual(GitHubParse.combinedState(try Fixtures.data("github-status")), "pending")
        XCTAssertEqual(GitHubParse.login(try Fixtures.data("github-user")), "user-9")
        XCTAssertNil(GitHubParse.checkRuns(Data("[]".utf8)))
    }

    func testRollupWordsAreGitHubsOwn() {
        func rollup(_ conclusions: [String?], state: String? = nil) -> CheckRollup {
            CheckRollup(checkRuns: conclusions.map { CheckRun(status: $0 == nil ? "queued" : "completed", conclusion: $0) }, combinedState: state)
        }
        XCTAssertTrue(rollup(["success", "failure"]).isFailing)
        XCTAssertTrue(rollup(["timed_out"]).isFailing)
        XCTAssertTrue(rollup(["success"], state: "error").isFailing)
        XCTAssertFalse(rollup(["success", "skipped", "neutral", "cancelled"], state: "success").isFailing)
        XCTAssertTrue(rollup(["success", nil]).isPending)
        XCTAssertTrue(rollup(["success"], state: "pending").isPending)
        XCTAssertFalse(rollup(["success"], state: "success").isPending)
        XCTAssertTrue(rollup([], state: "pending").isEmpty)
    }

    func testLinkHeaderNext() {
        let h = "<https://api.github.com/repos/octo/repo-a/pulls?page=2>; rel=\"next\", <https://api.github.com/repos/octo/repo-a/pulls?page=5>; rel=\"last\""
        XCTAssertEqual(GitHubParse.nextLink(h)?.absoluteString, "https://api.github.com/repos/octo/repo-a/pulls?page=2")
        XCTAssertNil(GitHubParse.nextLink("<https://api.github.com/x?page=1>; rel=\"prev\""))
        XCTAssertNil(GitHubParse.nextLink(nil))
        XCTAssertNil(GitHubParse.nextLink("garbage"))
    }

    func testRateLimitHeaders() {
        let info = GitHubParse.rateLimit(["X-RateLimit-Limit": "5000", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1790000600", "Retry-After": "30"])
        XCTAssertEqual(info.limit, 5000)
        XCTAssertEqual(info.remaining, 0)
        XCTAssertEqual(info.reset, Date(timeIntervalSince1970: 1_790_000_600))
        XCTAssertEqual(info.retryAfter, 30)
        XCTAssertEqual(GitHubParse.rateLimit([:]), RateLimitInfo())
        XCTAssertNil(GitHubParse.rateLimit(["retry-after": "Wed, 21 Oct 2026 07:28:00 GMT"]).retryAfter)
    }

    func testWhichForbiddenIsARateLimit() {
        let none = RateLimitInfo()
        XCTAssertTrue(GitHubParse.isRateLimited(status: 429, info: none, body: Data()))
        XCTAssertTrue(GitHubParse.isRateLimited(status: 403, info: RateLimitInfo(remaining: 0), body: Data()))
        XCTAssertTrue(GitHubParse.isRateLimited(status: 403, info: RateLimitInfo(retryAfter: 60), body: Data()))
        XCTAssertTrue(GitHubParse.isRateLimited(status: 403, info: none, body: Data("{\"message\":\"You have exceeded a secondary rate limit.\"}".utf8)))
        XCTAssertFalse(GitHubParse.isRateLimited(status: 403, info: RateLimitInfo(remaining: 4000), body: Data("{\"message\":\"Resource not accessible by integration\"}".utf8)))
        XCTAssertFalse(GitHubParse.isRateLimited(status: 500, info: none, body: Data()))
    }

    func testHeadersAreLowercased() {
        XCTAssertEqual(GitHubParse.lowercased(["ETag": "\"x\"", "Link": "l"] as [AnyHashable: Any]), ["etag": "\"x\"", "link": "l"])
    }
}

final class RateBudgetTests: XCTestCase {
    func testDefaultCapIsOneThousandAnHour() {
        XCTAssertEqual(RateBudget().cap, 1_000)
        XCTAssertEqual(RateBudget(cap: 5).cap, 100, "clamped to the lowest allowed cap")
        XCTAssertEqual(RateBudget(cap: 99_999).cap, 4_000)
    }

    func testCapBlocksUntilTheOldestRequestLeavesTheWindow() {
        var b = RateBudget(cap: 100)
        for i in 0..<100 { b.record(at: t0.addingTimeInterval(Double(i)), notModified: false) }
        let now = t0.addingTimeInterval(100)
        XCTAssertEqual(b.used(at: now), 100)
        XCTAssertEqual(b.verdict(at: now), .capReached(until: t0.addingTimeInterval(3_600)))
        XCTAssertEqual(b.verdict(at: t0.addingTimeInterval(3_601)), .allowed)
    }

    func testNotModifiedIsFree() {
        var b = RateBudget(cap: 100)
        for _ in 0..<500 { b.record(at: t0, notModified: true) }
        XCTAssertEqual(b.used(at: t0), 0)
        XCTAssertEqual(b.verdict(at: t0), .allowed)
    }

    func testRetryAfterWins() {
        var b = RateBudget()
        let until = b.limited(info: RateLimitInfo(remaining: 0, reset: t0.addingTimeInterval(500), retryAfter: 42), at: t0, unit: 0.5)
        XCTAssertEqual(until, t0.addingTimeInterval(42))
        XCTAssertEqual(b.verdict(at: t0.addingTimeInterval(10)), .backingOff(until: until))
        XCTAssertEqual(b.verdict(at: t0.addingTimeInterval(43)), .allowed)
    }

    func testResetIsUsedWhenNothingIsLeft() {
        var b = RateBudget()
        let until = b.limited(info: RateLimitInfo(remaining: 0, reset: t0.addingTimeInterval(300)), at: t0, unit: 0.5)
        XCTAssertEqual(until, t0.addingTimeInterval(301))
    }

    func testNoHeaderDoublesFromSixtySecondsToFifteenMinutesWithJitter() {
        var b = RateBudget()
        var delays: [TimeInterval] = []
        for _ in 0..<7 { delays.append(b.limited(info: RateLimitInfo(), at: t0, unit: 0.5).timeIntervalSince(t0)) }
        XCTAssertEqual(delays, [60, 120, 240, 480, 900, 900, 900])
        var low = RateBudget(), high = RateBudget()
        XCTAssertEqual(low.limited(info: RateLimitInfo(), at: t0, unit: 0).timeIntervalSince(t0), 48, accuracy: 0.001)
        XCTAssertEqual(high.limited(info: RateLimitInfo(), at: t0, unit: 1).timeIntervalSince(t0), 72, accuracy: 0.001)
    }

    func testSuccessResetsTheBackoff() {
        var b = RateBudget()
        _ = b.limited(info: RateLimitInfo(), at: t0, unit: 0.5)
        _ = b.limited(info: RateLimitInfo(), at: t0, unit: 0.5)
        b.succeeded()
        XCTAssertEqual(b.verdict(at: t0), .allowed)
        XCTAssertEqual(b.limited(info: RateLimitInfo(), at: t0, unit: 0.5).timeIntervalSince(t0), 60)
    }

    func testAHugeRetryAfterIsCappedAtAnHour() {
        var b = RateBudget()
        XCTAssertEqual(b.limited(info: RateLimitInfo(retryAfter: 999_999), at: t0, unit: 0).timeIntervalSince(t0), 3_600)
    }
}

final class ETagCacheTests: XCTestCase {
    func testStoreLookupAndClear() {
        var c = ETagCache()
        let url = URL(string: "https://api.github.com/a")!
        XCTAssertNil(c.entry(for: url))
        c.store(.init(etag: "e1", body: Data([1]), link: nil), for: url)
        c.store(.init(etag: "e2", body: Data([2]), link: "l"), for: url)
        XCTAssertEqual(c.entry(for: url)?.etag, "e2")
        XCTAssertEqual(c.count, 1)
        c.removeAll()
        XCTAssertNil(c.entry(for: url))
    }

    func testOldestEntriesAreDroppedAtTheLimit() {
        var c = ETagCache()
        for i in 0..<(ETagCache.maxEntries + 10) {
            c.store(.init(etag: "e", body: Data(), link: nil), for: URL(string: "https://api.github.com/\(i)")!)
        }
        XCTAssertEqual(c.count, ETagCache.maxEntries)
        XCTAssertNil(c.entry(for: URL(string: "https://api.github.com/0")!))
        XCTAssertNotNil(c.entry(for: URL(string: "https://api.github.com/\(ETagCache.maxEntries + 9)")!))
    }
}

final class TokenPolicyTests: XCTestCase {
    func testExpiryAndRefreshWindow() {
        let expiry = TokenPolicy.expiry(expiresIn: 28_800, now: t0)
        XCTAssertEqual(expiry, t0.addingTimeInterval(28_800))
        XCTAssertNil(TokenPolicy.expiry(expiresIn: nil, now: t0))
        XCTAssertFalse(TokenPolicy.needsRefresh(expiry: expiry, now: t0))
        XCTAssertFalse(TokenPolicy.needsRefresh(expiry: expiry, now: t0.addingTimeInterval(28_800 - 301)))
        XCTAssertTrue(TokenPolicy.needsRefresh(expiry: expiry, now: t0.addingTimeInterval(28_800 - 300)))
        XCTAssertTrue(TokenPolicy.needsRefresh(expiry: expiry, now: t0.addingTimeInterval(40_000)))
    }

    func testUnknownExpiryIsLeftToTheFirst401() {
        XCTAssertFalse(TokenPolicy.needsRefresh(expiry: nil, now: t0))
    }

    func testExpiryTextRoundTrips() {
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(TokenPolicy.decode(TokenPolicy.encode(d)), d)
        XCTAssertNil(TokenPolicy.decode("soon"))
        XCTAssertNil(TokenPolicy.decode(nil))
    }

    func testSignOutDeletesTheExpiryToo() throws {
        let store = InMemorySecretStore()
        for kind in SecretKey.Kind.allCases { try store.write("x", for: SecretKey(.github, kind)) }
        try store.deleteAll(.github)
        XCTAssertEqual(store.count, 0)
    }
}

final class LinkRouteWorkTests: XCTestCase {
    func testOnlyHttpsGitHubAndLinearOpen() {
        for ok in ["https://github.com/octo/repo-a/pull/12", "https://linear.app/team/issue/ISS-1", "HTTPS://GitHub.com/x", "https://github.com:443/x"] {
            XCTAssertNotNil(LinkRoute.workLink(URL(string: ok)!), ok)
        }
        for bad in ["http://github.com/x", "https://github.com.evil.example/x", "https://evil.example/github.com", "https://user@github.com/x", "https://github.com:8443/x", "javascript:alert(1)", "file:///etc/passwd", "https://api.github.com/x", "dev.atc.annunciator://linear-callback"] {
            XCTAssertNil(LinkRoute.workLink(URL(string: bad)!), bad)
        }
    }
}

// MARK: - The client, with a scripted network

private final class FakeTransport: GitHubTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> GitHubResponse

    init(_ handler: @escaping (URLRequest) throws -> GitHubResponse) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> GitHubResponse {
        requests.append(request)
        return try handler(request)
    }

    var paths: [String] { requests.map { $0.url?.path ?? "" } }
    func count(_ part: String) -> Int { paths.filter { $0.contains(part) }.count }
}

private final class FakeTokens: GitHubTokenSource {
    var result: GitHubToken = .token("tok-abcdef")
    var refreshedResult: GitHubToken = .token("tok-fresh1")
    var calls: [Bool] = []

    func accessToken(forceRefresh: Bool) async -> GitHubToken {
        calls.append(forceRefresh)
        return forceRefresh ? refreshedResult : result
    }
}

private struct Boom: Error, CustomStringConvertible { var description: String }

final class GitHubClientTests: XCTestCase {
    private var clock = t0
    private var pullsBody = Data()
    private var runsBody = Data()
    private var statusBody = Data("{\"state\":\"success\"}".utf8)
    private var listETag = "\"list-1\""

    override func setUpWithError() throws {
        clock = t0
        pullsBody = try Fixtures.data("github-pulls")
        runsBody = try Fixtures.data("github-check-runs-green")
    }

    /// The server as GitHub would answer: honours If-None-Match on the list.
    private func server(_ r: URLRequest) -> GitHubResponse {
        let path = r.url?.path ?? ""
        if path == "/user" { return .init(status: 200, body: (try? Fixtures.data("github-user")) ?? Data()) }
        if path.hasSuffix("/pulls") {
            if r.value(forHTTPHeaderField: "If-None-Match") == listETag { return .init(status: 304, headers: ["etag": listETag]) }
            return .init(status: 200, headers: ["etag": listETag], body: pullsBody)
        }
        if path.hasSuffix("/check-runs") { return .init(status: 200, body: runsBody) }
        if path.hasSuffix("/status") { return .init(status: 200, body: statusBody) }
        return .init(status: 404)
    }

    private func make(tokens: FakeTokens = FakeTokens(), cap: Int = 1_000) -> (GitHubClient, FakeTransport, FakeTokens) {
        makeWith(tokens: tokens, cap: cap) { [unowned self] r in self.server(r) }
    }

    private func makeWith(tokens: FakeTokens = FakeTokens(), cap: Int = 1_000, _ handler: @escaping (URLRequest) throws -> GitHubResponse) -> (GitHubClient, FakeTransport, FakeTokens) {
        let transport = FakeTransport(handler)
        let client = GitHubClient(transport: transport, tokens: tokens, cap: cap, now: { [unowned self] in self.clock }, random: { 0.5 })
        client.setRepos([repoA])
        return (client, transport, tokens)
    }

    func testFirstPassReadsUserListAndOneRollupPerPR() async {
        let (client, net, _) = make()
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(s.login, "user-9")
        XCTAssertEqual(s.pulls.map(\.number), [12, 9])
        XCTAssertEqual(s.pulls.map { $0.ci?.isFailing }, [false, false])
        XCTAssertEqual(net.count("/user"), 1)
        XCTAssertEqual(net.count("/pulls"), 1)
        XCTAssertEqual(net.count("/check-runs"), 2)
        XCTAssertEqual(net.count("/status"), 2)
        XCTAssertEqual(net.requests.count, 6)
        XCTAssertEqual(s.fetchedAt, t0)
    }

    func testEveryRequestIsAGetToTheApiHostWithTheToken() async {
        let (client, net, _) = make()
        await client.refresh()
        for r in net.requests {
            XCTAssertEqual(r.httpMethod, "GET")
            XCTAssertEqual(r.url?.host, "api.github.com")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abcdef")
            XCTAssertNil(r.httpBody)
        }
    }

    func testUnchangedListIsAFreeNotModifiedAndNoRollupIsFetched() async {
        let (client, net, _) = make()
        await client.refresh()
        let usedBefore = client.budget.used(at: clock)
        net.requests.removeAll()
        clock = clock.addingTimeInterval(60)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(net.paths, ["/repos/octo/repo-a/pulls"], "no /user again, no rollups")
        XCTAssertEqual(net.requests[0].value(forHTTPHeaderField: "If-None-Match"), listETag)
        XCTAssertEqual(s.pulls.map(\.number), [12, 9], "the cached body is parsed again")
        XCTAssertEqual(client.budget.used(at: clock), usedBefore, "a 304 does not count")
    }

    func testRollupIsFetchedAgainOnlyForAPRWhoseUpdatedAtChanged() async throws {
        let (client, net, _) = make()
        await client.refresh()
        net.requests.removeAll()
        // PR 12 moves; PR 9 does not. The list has a new ETag, so GitHub answers 200.
        let text = String(decoding: pullsBody, as: UTF8.self).replacingOccurrences(of: "2026-10-01T09:30:00Z", with: "2026-10-01T10:00:00Z")
        pullsBody = Data(text.utf8)
        listETag = "\"list-2\""
        clock = clock.addingTimeInterval(60)
        let s = await client.refresh()
        XCTAssertEqual(net.count("/check-runs"), 1)
        XCTAssertTrue(net.paths.contains { $0.contains("/commits/1111111111111111111111111111111111111111/") })
        XCTAssertEqual(s.pulls.first?.updatedAtRaw, "2026-10-01T10:00:00Z")
        XCTAssertNotNil(s.pulls.last?.ci, "the unchanged PR keeps its rollup")
    }

    func testAPendingRollupIsAskedAgainEvenWhenNothingElseChanged() async {
        runsBody = (try? Fixtures.data("github-check-runs")) ?? Data()  // has an in_progress run and a failure
        let (client, net, _) = make()
        let first = await client.refresh()
        XCTAssertEqual(first.pulls.first?.ci?.isFailing, true)
        XCTAssertEqual(first.pulls.first?.ci?.isPending, true)
        net.requests.removeAll()
        clock = clock.addingTimeInterval(60)
        await client.refresh()
        XCTAssertEqual(net.count("/check-runs"), 2, "both rollups are still pending")
        runsBody = (try? Fixtures.data("github-check-runs-green")) ?? Data()
        net.requests.removeAll()
        await client.refresh()
        XCTAssertEqual(net.count("/check-runs"), 2)
        net.requests.removeAll()
        let last = await client.refresh()
        XCTAssertEqual(net.count("/check-runs"), 0, "settled: no more rollup requests")
        XCTAssertEqual(last.pulls.first?.ci?.isPending, false)
    }

    func testLinkPagingIsFollowedUpToTheLimit() async throws {
        var listCalls = 0
        let (client, net, _) = makeWith { [unowned self] r in
            if (r.url?.path ?? "").hasSuffix("/pulls") {
                listCalls += 1
                return .init(status: 200, headers: ["link": "<https://api.github.com/repos/octo/repo-a/pulls?page=\(listCalls + 1)>; rel=\"next\""], body: self.pullsBody)
            }
            return self.server(r)
        }
        await client.refresh()
        XCTAssertEqual(net.count("/pulls"), GitHubClient.maxPagesPerRepo)
    }

    func testRateLimitStopsThePassAndTheNextOnesWaitForRetryAfter() async {
        var limited = true
        let (client, net, _) = makeWith { [unowned self] r in
            if limited, (r.url?.path ?? "").hasSuffix("/pulls") { return .init(status: 429, headers: ["retry-after": "90"]) }
            return self.server(r)
        }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .rateLimited(until: t0.addingTimeInterval(90)))
        let sent = net.requests.count
        clock = t0.addingTimeInterval(30)
        let again = await client.refresh()
        XCTAssertEqual(net.requests.count, sent, "nothing is sent while backing off")
        XCTAssertEqual(again.status, .rateLimited(until: t0.addingTimeInterval(90)))
        limited = false
        clock = t0.addingTimeInterval(91)
        let ok = await client.refresh()
        XCTAssertEqual(ok.status, .ok)
        XCTAssertEqual(ok.pulls.count, 2)
    }

    func testAPlainForbiddenIsAnErrorNotABackoff() async {
        let (client, _, _) = makeWith { _ in .init(status: 403, headers: ["x-ratelimit-remaining": "4000"], body: Data("{\"message\":\"Resource not accessible by integration\"}".utf8)) }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .error("HTTP 403"))
        XCTAssertEqual(client.budget.verdict(at: t0), .allowed)
    }

    func testCapStopsTheApp() async {
        let (client, net, _) = make(cap: 100)
        for i in 0..<100 { client.budget.record(at: t0.addingTimeInterval(Double(i)), notModified: false) }
        clock = t0.addingTimeInterval(200)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .capReached(until: t0.addingTimeInterval(3_600)))
        XCTAssertTrue(net.requests.isEmpty)
    }

    func test401RefreshesOnceAndRetries() async {
        var first = true
        let tokens = FakeTokens()
        let (client, net, _) = makeWith(tokens: tokens) { [unowned self] r in
            if first, (r.url?.path ?? "") == "/user" { first = false; return .init(status: 401) }
            return self.server(r)
        }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(s.login, "user-9")
        XCTAssertEqual(tokens.calls.filter { $0 }.count, 1, "one forced refresh")
        let retried = net.requests.filter { $0.url?.path == "/user" }
        XCTAssertEqual(retried.count, 2)
        XCTAssertEqual(retried[1].value(forHTTPHeaderField: "Authorization"), "Bearer tok-fresh1")
    }

    func testASecond401MeansSignInAgainAndNothingIsSentUntilReset() async {
        let (client, net, _) = makeWith { _ in .init(status: 401) }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .needsSignIn)
        let sent = net.requests.count
        let again = await client.refresh()
        XCTAssertEqual(again.status, .needsSignIn)
        XCTAssertEqual(net.requests.count, sent)
        client.reset()
        net.handler = { [unowned self] r in self.server(r) }
        let ok = await client.refresh()
        XCTAssertEqual(ok.status, .ok)
    }

    func testAFailedRefreshOrSignedOutTokenSendsNothing() async {
        let tokens = FakeTokens()
        tokens.result = .failed
        let (client, net, _) = make(tokens: tokens)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .needsSignIn)
        XCTAssertTrue(net.requests.isEmpty)
    }

    func testReviewRequestedFilterUsesTheSignedInLogin() async {
        let (client, _, _) = make()
        let s = await client.refresh()
        let rows = WorkPanel.rows(s, filter: .reviewRequested, now: t0)
        XCTAssertEqual(rows.map(\.id), ["octo/repo-a#12"])
        XCTAssertEqual(WorkPanel.rows(s, filter: .all, now: t0).count, 2)
    }

    func testTransportErrorsAreRedacted() async {
        let (client, _, _) = makeWith { _ in throw Boom(description: "failed with Authorization: Bearer tok-abcdef for tok-abcdef") }
        let s = await client.refresh()
        guard case .error(let message) = s.status else { return XCTFail("\(s.status)") }
        XCTAssertFalse(message.contains("tok-abcdef"))
    }

    func testOneRepoFailingKeepsTheOthers() async throws {
        let repoB = RepoRef("octo/repo-b")!
        let (client, _, _) = makeWith { [unowned self] r in
            if (r.url?.path ?? "").contains("repo-b") { return .init(status: 404) }
            return self.server(r)
        }
        client.setRepos([repoA, repoB])
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(s.failedRepos, ["octo/repo-b"])
        XCTAssertEqual(s.pulls.count, 2)
    }

    func testResetForgetsEverythingHeldInMemory() async {
        let (client, net, _) = make()
        await client.refresh()
        client.reset()
        XCTAssertTrue(client.snapshot.pulls.isEmpty)
        XCTAssertNil(client.snapshot.login)
        net.requests.removeAll()
        await client.refresh()
        XCTAssertNil(net.requests.first { $0.url?.path.hasSuffix("/pulls") == true }?.value(forHTTPHeaderField: "If-None-Match"), "the ETag cache is empty after reset")
    }

    func testNoReposMeansNoRequests() async {
        let (client, net, _) = make()
        client.setRepos([])
        let s = await client.refresh()
        XCTAssertEqual(s.status, .idle)
        XCTAssertTrue(net.requests.isEmpty)
    }
}

// MARK: - Popover line and rows

final class WorkPanelTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func snapshot(status: GitHubStatus = .ok, failing: Int = 0, review: Bool = false, count: Int = 3) -> GitHubSnapshot {
        var s = GitHubSnapshot()
        s.status = status
        s.login = "user-9"
        s.fetchedAt = t0
        for i in 0..<count {
            var pr = PullRequest(
                repo: repoA, number: i + 1, title: "t\(i)", author: "user-1", isDraft: false, headSHA: "1111111", updatedAtRaw: "x",
                updatedAt: t0.addingTimeInterval(-3_600 * Double(i + 1)), url: URL(string: "https://github.com/octo/repo-a/pull/\(i + 1)")!,
                review: ReviewState(requestedReviewers: review && i == 0 ? ["user-9"] : []))
            pr.ci = CheckRollup(checkRuns: [CheckRun(status: "completed", conclusion: i < failing ? "failure" : "success")], combinedState: nil)
            s.pulls.append(pr)
        }
        return s
    }

    func testCountsLine() {
        XCTAssertEqual(WorkPanel.line(snapshot(failing: 1), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 3 open · 1 CI failing")
        XCTAssertEqual(WorkPanel.line(snapshot(), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 3 open")
        XCTAssertEqual(WorkPanel.line(snapshot(failing: 2, review: true), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 3 open · 2 CI failing · 1 review requested")
        XCTAssertEqual(WorkPanel.line(snapshot(count: 0), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 0 open")
        XCTAssertEqual(WorkPanel.line(snapshot(), signedIn: true, repos: 1, now: t0)?.isNotice, false)
    }

    func testLineHiddenWhenSignedOut() {
        XCTAssertNil(WorkPanel.line(snapshot(), signedIn: false, repos: 1, now: t0))
    }

    func testRateLimitedLineNamesTheTime() {
        let s = snapshot(status: .rateLimited(until: Date(timeIntervalSince1970: 1_790_000_000 + 3_000)))
        let line = WorkPanel.line(s, signedIn: true, repos: 1, now: t0, timeZone: utc)
        XCTAssertEqual(line?.text, "GitHub rate limited, retrying at \(hhmm(t0.addingTimeInterval(3_000)))")
        XCTAssertEqual(line?.isNotice, true)
    }

    private func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    func testOtherNotices() {
        XCTAssertEqual(WorkPanel.line(snapshot(), signedIn: true, repos: 0, now: t0)?.isNotice, true)
        XCTAssertEqual(WorkPanel.line(snapshot(status: .needsSignIn), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 다시 로그인이 필요합니다")
        XCTAssertEqual(WorkPanel.line(snapshot(status: .capReached(until: t0)), signedIn: true, repos: 1, now: t0, timeZone: utc)?.isNotice, true)
        var fresh = GitHubSnapshot()
        fresh.status = .idle
        XCTAssertEqual(WorkPanel.line(fresh, signedIn: true, repos: 1, now: t0)?.text, "GitHub: 읽는 중…")
        fresh.status = .error("HTTP 404")
        XCTAssertEqual(WorkPanel.line(fresh, signedIn: true, repos: 1, now: t0)?.text, "GitHub: 읽지 못함 (HTTP 404)")
    }

    func testAnErrorAfterAGoodReadKeepsShowingTheLastCounts() {
        XCTAssertEqual(WorkPanel.line(snapshot(status: .error("HTTP 502")), signedIn: true, repos: 1, now: t0)?.text, "GitHub: 3 open")
    }

    func testRows() {
        let rows = WorkPanel.rows(snapshot(failing: 1, review: true), filter: .all, now: t0)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].detail, "repo-a #1 · user-1 · 1h")
        XCTAssertEqual(rows[0].ci, .failing)
        XCTAssertEqual(rows[0].ciLabel, "CI failing")
        XCTAssertEqual(rows[0].reviewLabel, "review requested")
        XCTAssertNil(rows[1].reviewLabel)
        XCTAssertEqual(rows[1].ci, .passing)
        XCTAssertEqual(rows[0].url?.absoluteString, "https://github.com/octo/repo-a/pull/1")
        XCTAssertEqual(WorkPanel.rows(snapshot(failing: 1, review: true), filter: .reviewRequested, now: t0).map(\.id), ["octo/repo-a#1"])
    }

    func testRowWithoutCIFactsSaysSo() {
        var s = snapshot(count: 1)
        s.pulls[0].ci = nil
        XCTAssertEqual(WorkPanel.rows(s, filter: .all, now: t0)[0].ciLabel, "CI —")
        s.pulls[0].ci = CheckRollup(checkRuns: [CheckRun(status: "queued", conclusion: nil)], combinedState: nil)
        XCTAssertEqual(WorkPanel.rows(s, filter: .all, now: t0)[0].ci, .pending)
    }

    func testTheDecisionLinkIsAnAtcTab() {
        let url = ATCLink.url(base: URL(string: "http://localhost:7700")!, link: "#" + WorkPanel.atcFragment)
        XCTAssertEqual(url?.absoluteString, "http://localhost:7700/#strips")
    }

    func testPanelNeverHasAnAtcVerdictWord() {
        let text = (WorkPanel.rows(snapshot(failing: 1, review: true), filter: .all, now: t0).flatMap { [$0.title, $0.detail, $0.ciLabel, $0.reviewLabel ?? ""] }
            + [WorkPanel.line(snapshot(failing: 1), signedIn: true, repos: 1, now: t0)?.text ?? "", WorkPanel.header(snapshot(), now: t0)]).joined(separator: " ")
        for word in ["CLEARED", "STRANDED", "LANDING", "TIER", "tier"] { XCTAssertFalse(text.contains(word), word) }
    }

    func testPopoverLayoutGrowsByOneLine() {
        let panel = PanelContent(FeedState(), base: URL(string: "http://localhost:7700")!, now: t0)
        XCTAssertGreaterThanOrEqual(PanelLayout.height(for: panel, expansion: LampExpansion(), workLine: true), PanelLayout.height(for: panel, expansion: LampExpansion()))
    }
}

// MARK: - Fixtures

final class FixtureScanTests: XCTestCase {
    func testNoFixtureHoldsAnAddressOrACredential() throws {
        let dir = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertGreaterThan(files.count, 5)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in ["@", "ghp_", "github_pat_", "lin_", "Bearer"] {
                XCTAssertFalse(text.contains(needle), "\(file.lastPathComponent) contains \(needle)")
            }
        }
    }
}
