// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ATCCore

// ATC-248 (GL1b). Fixtures are scrubbed: team key `ISS`, workspace `ws`, no token, no Authorization.

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let iss = TeamKey("ISS")!

final class TeamKeyTests: XCTestCase {
    func testShape() {
        XCTAssertEqual(TeamKey(" iss ")?.value, "ISS")
        XCTAssertEqual(TeamKey("AB2")?.value, "AB2")
        for bad in ["", "1AB", "A-B", "A B", "ÄB", String(repeating: "A", count: 11), "A\"}", "A\\"] {
            XCTAssertNil(TeamKey(bad), bad)
        }
    }

    func testList() {
        let r = TeamKey.parseList("iss, abc\nISS; x-y")
        XCTAssertEqual(r.keys.map(\.value), ["ISS", "ABC"])
        XCTAssertEqual(r.rejected, ["x-y"])
    }

    func testIdentifierShape() {
        XCTAssertTrue(LinearIssue.validIdentifier("ISS-12"))
        for bad in ["", "ISS", "ISS-", "-12", "ISS-1x", "ISS-12/../x", "iss 12", "ISS-12#x", "ISS-1234567890"] {
            XCTAssertFalse(LinearIssue.validIdentifier(bad), bad)
        }
    }
}

final class LinearRequestTests: XCTestCase {
    private func variables(_ r: LinearRequest) throws -> [String: Any] {
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: r.body) as? [String: Any])
        return try XCTUnwrap(o["variables"] as? [String: Any])
    }

    func testIsAReadOnlyQueryWithTheTeamsAsVariables() throws {
        let r = LinearRequests.openIssues(teams: [iss, TeamKey("ABC")!])
        XCTAssertTrue(r.isQuery)
        XCTAssertFalse(r.query.lowercased().contains("mutation"))
        XCTAssertFalse(r.query.contains("ISS"), "keys are variables, never part of the query text")
        let v = try variables(r)
        XCTAssertEqual(v["first"] as? Int, 50)
        XCTAssertNil(v["after"])
        let filter = try XCTUnwrap(v["filter"] as? [String: Any])
        XCTAssertEqual(((filter["team"] as? [String: Any])?["key"] as? [String: Any])?["in"] as? [String], ["ISS", "ABC"])
        XCTAssertEqual(((filter["state"] as? [String: Any])?["type"] as? [String: Any])?["in"] as? [String], ["unstarted", "started"])
    }

    func testAskForOnlyTheFieldsShown() {
        let q = LinearRequests.openIssuesQuery
        for field in ["identifier", "title", "url", "updatedAt", "state { name type }", "team { key }", "pageInfo { hasNextPage endCursor }"] {
            XCTAssertTrue(q.contains(field), field)
        }
        for other in ["assignee", "description", "comments", "email", "creator", "labels"] { XCTAssertFalse(q.contains(other), other) }
    }

    func testCursorTravelsAsAVariable() throws {
        let r = LinearRequests.openIssues(teams: [iss], after: "abc\"def")
        XCTAssertEqual(try variables(r)["after"] as? String, "abc\"def")
        XCTAssertFalse(r.query.contains("abc"))
        XCTAssertNil(try variables(LinearRequests.openIssues(teams: [iss], after: String(repeating: "x", count: 600)))["after"])
    }

    func testRequestShapeAndTokenPlace() {
        let r = LinearRequests.openIssues(teams: [iss]).urlRequest(token: "tok-abcdef")
        XCTAssertEqual(r.url?.absoluteString, "https://api.linear.app/graphql")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abcdef")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(String(decoding: r.httpBody ?? Data(), as: UTF8.self).contains("tok-abcdef"))
        XCTAssertFalse(r.url?.absoluteString.contains("tok-abcdef") ?? true)
    }

    func testAWriteIsNotAQuery() {
        for text in ["mutation { issueDelete(id: \"x\") { success } }",
                     "query Q { x } mutation M { y }",
                     "subscription S { x }", "{ viewer { id } }"] {
            XCTAssertFalse(LinearRequest(query: text, body: Data()).isQuery, text)
        }
    }

    func testScopeIsReadOnly() {
        XCTAssertEqual(LinearAuth.scope, "read")
    }
}

final class LinearParseTests: XCTestCase {
    func testIssuesFixture() throws {
        let page = try XCTUnwrap(LinearParse.issues(Fixtures.data("linear-issues")))
        XCTAssertEqual(page.issues.map(\.identifier), ["ISS-12", "ISS-9", "ISS-7", "ISS-5"], "bad host, bad key and missing key are dropped")
        XCTAssertTrue(page.hasNext)
        XCTAssertEqual(page.endCursor, "cursor-1")
        let first = page.issues[0]
        XCTAssertEqual(first.state, LinearWorkflowState(name: "In Progress", type: .started))
        XCTAssertEqual(first.team.key, "ISS")
        XCTAssertEqual(first.updatedAt, LinearParse.date("2026-10-01T05:12:33.123Z"))
        XCTAssertEqual(page.issues[2].updatedAt, LinearParse.date("2026-09-30T23:30:00Z"), "no fractional seconds also parses")
        XCTAssertNil(page.issues[3].state.type, "an unknown type is kept, not guessed")
    }

    func testNotAListIsNil() {
        XCTAssertNil(LinearParse.issues(Data("<html>".utf8)))
        XCTAssertNil(LinearParse.issues(Data(#"{"data":null}"#.utf8)))
    }

    func testFailures() throws {
        XCTAssertNil(LinearParse.failure(status: 200, body: try Fixtures.data("linear-issues")))
        XCTAssertEqual(LinearParse.failure(status: 400, body: try Fixtures.data("linear-ratelimited")), .rateLimited)
        XCTAssertEqual(LinearParse.failure(status: 200, body: try Fixtures.data("linear-ratelimited")), .rateLimited)
        XCTAssertEqual(LinearParse.failure(status: 429, body: Data()), .rateLimited)
        XCTAssertEqual(LinearParse.failure(status: 401, body: Data()), .auth)
        let authBody = Data(#"{"errors":[{"message":"x","extensions":{"type":"authentication error","code":"AUTHENTICATION_ERROR"}}]}"#.utf8)
        XCTAssertEqual(LinearParse.failure(status: 400, body: authBody), .auth)
        XCTAssertEqual(LinearParse.failure(status: 500, body: Data()), .other("HTTP 500"))
        XCTAssertEqual(LinearParse.failure(status: 200, body: Data(#"{"errors":[{"message":"secret detail"}]}"#.utf8)), .other("GraphQL error"))
    }

    func testRateLimitHeaders() {
        let info = LinearParse.rateLimit(["X-RateLimit-Requests-Limit": "5000", "x-ratelimit-requests-remaining": "0",
                                          "x-ratelimit-requests-reset": "1790000100", "Retry-After": "30"])
        XCTAssertEqual(info.limit, 5000)
        XCTAssertEqual(info.remaining, 0)
        XCTAssertEqual(info.reset, Date(timeIntervalSince1970: 1_790_000_100))
        XCTAssertEqual(info.retryAfter, 30)
        let ms = LinearParse.rateLimit(["x-ratelimit-requests-reset": "1790000100000"])
        XCTAssertEqual(ms.reset, Date(timeIntervalSince1970: 1_790_000_100))
    }
}

// MARK: - The client, with a scripted network

private final class FakeTransport: LinearTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> GitHubResponse

    init(_ handler: @escaping (URLRequest) throws -> GitHubResponse) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> GitHubResponse {
        requests.append(request)
        return try handler(request)
    }

    func variables(_ i: Int) -> [String: Any] {
        let o = (try? JSONSerialization.jsonObject(with: requests[i].httpBody ?? Data())) as? [String: Any]
        return (o?["variables"] as? [String: Any]) ?? [:]
    }
}

private final class FakeTokens: LinearTokenSource {
    var result: GitHubToken = .token("tok-abcdef")
    var refreshedResult: GitHubToken = .token("tok-fresh1")
    var calls: [Bool] = []

    func accessToken(forceRefresh: Bool) async -> GitHubToken {
        calls.append(forceRefresh)
        return forceRefresh ? refreshedResult : result
    }
}

private struct Boom: Error, CustomStringConvertible { var description: String }

final class LinearClientTests: XCTestCase {
    private var clock = t0
    private var page1 = Data()

    override func setUpWithError() throws {
        clock = t0
        page1 = try Fixtures.data("linear-issues")
    }

    private func lastPage(_ nodes: String = "") -> GitHubResponse {
        .init(status: 200, body: Data(#"{"data":{"issues":{"nodes":[\#(nodes)],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#.utf8))
    }

    private func make(tokens: FakeTokens = FakeTokens(), _ handler: @escaping (URLRequest, FakeTransport) throws -> GitHubResponse) -> (LinearClient, FakeTransport, FakeTokens) {
        var transport: FakeTransport!
        transport = FakeTransport { r in try handler(r, transport) }
        let client = LinearClient(transport: transport, tokens: tokens, now: { [unowned self] in self.clock }, random: { 0.5 })
        client.setTeams([iss])
        return (client, transport, tokens)
    }

    /// Page one is the fixture (with a cursor), page two ends the list.
    private func twoPages(_ r: URLRequest, _ net: FakeTransport) -> GitHubResponse {
        let after = net.variables(net.requests.count - 1)["after"] as? String
        return after == nil ? .init(status: 200, body: page1) : lastPage(#"{"identifier":"ISS-1","title":"Oldest","url":"https://linear.app/ws/issue/ISS-1/o","updatedAt":"2026-09-01T00:00:00Z","state":{"name":"Todo","type":"unstarted"},"team":{"key":"ISS"}}"#)
    }

    func testPagesFollowTheCursorAndSortNewestFirst() async {
        let (client, net, _) = make(twoPages)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(net.requests.count, 2)
        XCTAssertEqual(net.variables(1)["after"] as? String, "cursor-1")
        XCTAssertEqual(s.issues.map(\.identifier), ["ISS-12", "ISS-9", "ISS-7", "ISS-5", "ISS-1"])
        XCTAssertFalse(s.truncated)
        XCTAssertEqual(s.fetchedAt, t0)
    }

    func testEveryRequestIsAQueryPostToTheGraphQLEndpoint() async {
        let (client, net, _) = make(twoPages)
        await client.refresh()
        for r in net.requests {
            XCTAssertEqual(r.httpMethod, "POST")
            XCTAssertEqual(r.url?.absoluteString, "https://api.linear.app/graphql")
            let body = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
            XCTAssertFalse(body.lowercased().contains("mutation"))
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok-abcdef")
        }
    }

    func testStopsAtTheLastPageAndSaysSoWhenThereIsMore() async {
        let (client, net, _) = make { _, _ in .init(status: 200, body: self.page1) }
        let s = await client.refresh()
        XCTAssertEqual(net.requests.count, LinearRequests.maxPages)
        XCTAssertTrue(s.truncated)
        XCTAssertEqual(s.status, .ok)
    }

    func testNoTeamsSendsNothing() async {
        let (client, net, _) = make(twoPages)
        client.setTeams([])
        let s = await client.refresh()
        XCTAssertEqual(s.status, .idle)
        XCTAssertTrue(net.requests.isEmpty)
    }

    func testRateLimitedStopsAndBacksOffLikeGitHub() async throws {
        let limited = GitHubResponse(status: 400, headers: ["retry-after": "120"], body: try Fixtures.data("linear-ratelimited"))
        let (client, net, _) = make { _, _ in limited }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .rateLimited(until: t0.addingTimeInterval(120)))
        XCTAssertEqual(net.requests.count, 1)
        clock = t0.addingTimeInterval(60)
        let again = await client.refresh()
        XCTAssertEqual(again.status, .rateLimited(until: t0.addingTimeInterval(120)))
        XCTAssertEqual(net.requests.count, 1, "nothing is sent while backing off")
        clock = t0.addingTimeInterval(121)
        net.handler = { _ in self.lastPage() }
        let back = await client.refresh()
        XCTAssertEqual(back.status, .ok)
    }

    func testBackoffWithoutHeadersDoublesFromSixtySeconds() async throws {
        let limited = GitHubResponse(status: 400, body: try Fixtures.data("linear-ratelimited"))
        let (client, _, _) = make { _, _ in limited }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .rateLimited(until: t0.addingTimeInterval(60)))  // random 0.5 = no jitter
    }

    func testAnAuthFailureRefreshesOnceThenNeedsSignInAndStaysQuiet() async {
        let tokens = FakeTokens()
        let (client, net, _) = make(tokens: tokens) { _, _ in .init(status: 401) }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .needsSignIn)
        XCTAssertEqual(tokens.calls, [false, true])
        XCTAssertEqual(net.requests.count, 2)
        _ = await client.refresh()
        XCTAssertEqual(net.requests.count, 2, "no request until the sign-in changes")
        client.reset()
        net.handler = { _ in self.lastPage() }
        let ok = await client.refresh()
        XCTAssertEqual(ok.status, .ok)
    }

    func testARefreshedTokenIsUsedForTheRetry() async {
        let (client, net, _) = make { r, _ in
            r.value(forHTTPHeaderField: "Authorization") == "Bearer tok-fresh1" ? self.lastPage() : .init(status: 401)
        }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .ok)
        XCTAssertEqual(net.requests.count, 2)
    }

    func testSignedOutTokenStopsWithoutARequest() async {
        let tokens = FakeTokens()
        tokens.result = .signedOut
        let (client, net, _) = make(tokens: tokens, twoPages)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .needsSignIn)
        XCTAssertTrue(net.requests.isEmpty)
    }

    func testAFailureKeepsTheLastListAndRedactsTheError() async {
        var fail = false
        let (client, _, _) = make { r, net in
            if fail { throw Boom(description: "connection to https://api.linear.app/graphql failed, Bearer tok-abcdef") }
            return self.twoPages(r, net)
        }
        _ = await client.refresh()
        fail = true
        let s = await client.refresh()
        guard case .error(let message) = s.status else { return XCTFail("\(s.status)") }
        XCTAssertFalse(message.contains("tok-abcdef"))
        XCTAssertEqual(s.issues.count, 5, "the list stays")
    }

    func testAnHTTPErrorShowsOnlyTheStatus() async {
        let (client, _, _) = make { _, _ in .init(status: 502, body: Data("<html>secret</html>".utf8)) }
        let s = await client.refresh()
        XCTAssertEqual(s.status, .error("HTTP 502"))
    }

    func testTheHourlyCapStopsTheApp() async {
        let (client, net, _) = make { _, _ in self.lastPage() }
        for _ in 0..<LinearClient.hourlyCap { await client.refresh() }
        XCTAssertEqual(net.requests.count, LinearClient.hourlyCap)
        let s = await client.refresh()
        XCTAssertEqual(s.status, .capReached(until: t0.addingTimeInterval(3_600)))
        XCTAssertEqual(net.requests.count, LinearClient.hourlyCap)
    }

    func testChangingTeamsClearsTheList() async {
        let (client, _, _) = make(twoPages)
        _ = await client.refresh()
        client.setTeams([TeamKey("ABC")!])
        XCTAssertTrue(client.snapshot.issues.isEmpty)
        XCTAssertNil(client.snapshot.fetchedAt)
    }
}

// MARK: - The panel

final class LinearPanelTests: XCTestCase {
    private func issue(_ id: String, _ type: LinearStateType?, name: String = "x", age: TimeInterval = 3_600) -> LinearIssue {
        LinearIssue(identifier: id, title: "t " + id, state: LinearWorkflowState(name: name, type: type), team: LinearTeam(key: "ISS"),
                    updatedAt: t0.addingTimeInterval(-age), url: URL(string: "https://linear.app/ws/issue/\(id)/s")!)
    }

    private func snap(_ issues: [LinearIssue], status: LinearStatus = .ok, truncated: Bool = false) -> LinearSnapshot {
        var s = LinearSnapshot()
        s.issues = issues
        s.status = status
        s.fetchedAt = t0
        s.truncated = truncated
        return s
    }

    private func line(_ s: LinearSnapshot, signedIn: Bool = true, teams: Int = 1) -> WorkLine? {
        WorkPanel.linearLine(s, signedIn: signedIn, teams: teams, now: t0, timeZone: TimeZone(identifier: "UTC")!)
    }

    func testLineCountsByStateType() {
        let s = snap([issue("ISS-1", .unstarted), issue("ISS-2", .unstarted), issue("ISS-3", .started), issue("ISS-4", nil)])
        XCTAssertEqual(line(s)?.text, "Linear: 2 Todo · 1 Started")
        XCTAssertEqual(line(s)?.openCount, 4)
        XCTAssertEqual(line(s)?.isNotice, false)
        XCTAssertEqual(line(snap([issue("ISS-3", .started)]))?.text, "Linear: 1 Started")
        XCTAssertEqual(line(snap([]))?.text, "Linear: 0 open")
        XCTAssertEqual(line(snap([issue("ISS-1", .unstarted)], truncated: true))?.text, "Linear: 1 Todo+")
    }

    func testLineIsHiddenSignedOutAndAsksForTeams() {
        XCTAssertNil(line(snap([]), signedIn: false))
        XCTAssertEqual(line(snap([]), teams: 0)?.text, "Linear: 팀 키를 Settings에 추가하세요")
        XCTAssertEqual(line(snap([]), teams: 0)?.isNotice, true)
    }

    func testNotices() {
        XCTAssertEqual(line(snap([], status: .rateLimited(until: t0.addingTimeInterval(120))))?.isNotice, true)
        XCTAssertTrue(line(snap([], status: .rateLimited(until: Date(timeIntervalSince1970: 1_790_003_600))))?.text.hasPrefix("Linear rate limited, retrying at ") ?? false)
        XCTAssertEqual(line(snap([], status: .needsSignIn))?.text, "Linear: 다시 로그인이 필요합니다")
        XCTAssertEqual(line(LinearSnapshot())?.text, "Linear: 읽는 중…")
        var failed = LinearSnapshot()
        failed.status = .error("HTTP 502")
        XCTAssertEqual(line(failed)?.text, "Linear: 읽지 못함 (HTTP 502)")
        // an error after a good read keeps the counts
        XCTAssertEqual(line(snap([issue("ISS-1", .unstarted)], status: .error("HTTP 502")))?.text, "Linear: 1 Todo")
    }

    func testRowsShowLinearsRawStateAndTheFlightDrawerKey() {
        let rows = WorkPanel.linearRows(snap([issue("ISS-12", .started, name: "In Review", age: 3 * 3_600)]), now: t0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].stateName, "In Review")
        XCTAssertEqual(rows[0].stateType, .started)
        XCTAssertEqual(rows[0].detail, "ISS-12 · 3h")
        XCTAssertEqual(rows[0].url?.host, "linear.app")
        XCTAssertEqual(rows[0].atcFragment, "flight/ISS-12")
    }

    func testTheDrawerLinkNeedsAWellFormedKey() {
        XCTAssertEqual(WorkPanel.flightFragment("ABC-3"), "flight/ABC-3")
        XCTAssertNil(WorkPanel.flightFragment("ABC-3/../strips"))
        XCTAssertNil(WorkPanel.flightFragment("x y"))
        let base = URL(string: "http://localhost:7700")!
        XCTAssertEqual(ATCLink.url(base: base, link: "#flight/ISS-12")?.absoluteString, "http://localhost:7700/#flight/ISS-12")
    }

    func testHeader() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(WorkPanel.linearHeader(LinearSnapshot(), now: t0, timeZone: utc), "읽는 중…")
        XCTAssertEqual(WorkPanel.linearHeader(snap([issue("ISS-1", .unstarted)]), now: t0.addingTimeInterval(120), timeZone: utc), "1 open · 2m 전 갱신")
        XCTAssertEqual(WorkPanel.linearHeader(snap([], truncated: true), now: t0, timeZone: utc), "0 open · <1m 전 갱신 · 처음 250개만")
        XCTAssertEqual(WorkPanel.linearHeader(snap([], status: .needsSignIn), now: t0, timeZone: utc), "다시 로그인이 필요합니다 (Settings)")
    }

    func testNoAtcVerdictWordAppearsInTheLineOrRows() {
        let s = snap([issue("ISS-1", .unstarted), issue("ISS-2", .started)])
        let text = ([line(s)?.text ?? ""] + WorkPanel.linearRows(s, now: t0).flatMap { [$0.title, $0.detail, $0.stateName] }).joined(separator: " ")
        for word in ["CLEARED", "STRANDED", "LANDING", "DISPATCH", "SCHEDULE"] { XCTAssertFalse(text.contains(word), word) }
    }

    func testLinearJoinsTheStatusGroupAndNeverNeedsAttention() {
        let github = WorkLine(text: "GitHub: 3 open", isNotice: false, openCount: 3)
        let linearLine = WorkLine(text: "Linear: 2 Todo · 1 Started", isNotice: false, openCount: 3)
        let rows = StatusRows(duty: nil, work: github, linear: linearLine, radio: nil)
        XCTAssertEqual(rows.rows.map(\.kind), [.work, .linear])
        XCTAssertEqual(rows.summary, "GitHub 3 · Linear 3")
        XCTAssertFalse(rows.needsAttention)
        XCTAssertTrue(rows.isFolded)
        let noticeOnly = StatusRows(duty: nil, work: nil, linear: WorkLine(text: "Linear: 읽는 중…", isNotice: true), radio: nil)
        XCTAssertFalse(noticeOnly.needsAttention)
    }
}
