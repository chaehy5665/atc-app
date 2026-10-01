// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ATC-248 (GL1b): the one GraphQL request the app sends to Linear, a read-only `query`. A GraphQL read is a POST,
// so "read only" is kept here by construction: the query text is a constant with no `mutation` in it, the only
// inputs (team keys, a page cursor) travel as JSON variables, and `LinearClient` refuses a request that is not
// `isQuery`. Scope `read` on the token is the second lock. Cost: only the fields shown, `first` is 50, at most
// five pages, far under Linear's 10,000-point limit per query.

public struct LinearRequest: Equatable, Sendable {
    public let query: String
    /// The JSON body as sent.
    public let body: Data

    /// A document that starts with `query` and holds no `mutation` or `subscription` word.
    public var isQuery: Bool {
        let words = query.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map { $0.lowercased() }
        return words.first == "query" && !words.contains("mutation") && !words.contains("subscription")
    }

    /// A POST with the token; the token is never part of the URL or the body.
    public func urlRequest(token: String) -> URLRequest {
        var r = URLRequest(url: LinearRequests.endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(GitHubRequests.userAgent, forHTTPHeaderField: "User-Agent")
        r.httpBody = body
        r.timeoutInterval = 20
        return r
    }
}

public enum LinearRequests {
    public static let endpoint = URL(string: "https://api.linear.app/graphql")!
    public static let pageSize = 50
    public static let maxPages = 5
    /// What the app lists: work waiting (`unstarted`, shown as Todo) and work under way (`started`).
    /// Backlog, Triage, Done and Canceled are not read (PILOT'S DISCRETION: the backlog is long and not "now").
    public static let listedTypes: [LinearStateType] = [.unstarted, .started]

    static let openIssuesQuery = """
    query OpenIssues($first: Int!, $after: String, $filter: IssueFilter) { \
    issues(first: $first, after: $after, filter: $filter, orderBy: updatedAt) { \
    nodes { identifier title url updatedAt state { name type } team { key } } \
    pageInfo { hasNextPage endCursor } } }
    """

    /// One page of the issues of `teams` whose state type is listed. `after` is the cursor Linear gave for the next page.
    public static func openIssues(teams: [TeamKey], after: String? = nil) -> LinearRequest {
        var variables: [String: Any] = [
            "first": pageSize,
            "filter": [
                "team": ["key": ["in": teams.map(\.value)]],
                "state": ["type": ["in": listedTypes.map(\.rawValue)]],
            ] as [String: Any],
        ]
        if let after, !after.isEmpty, after.utf8.count <= 512 { variables["after"] = after }
        let object: [String: Any] = ["query": openIssuesQuery, "variables": variables]
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return LinearRequest(query: openIssuesQuery, body: body)
    }
}
