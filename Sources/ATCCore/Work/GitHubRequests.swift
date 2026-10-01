// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ATC-247 (GL1a): request building only, no networking. There is no method parameter anywhere:
// every GitHub request the app can build is a GET (design 11.2, no write path).

public struct GitHubRequest: Equatable, Sendable {
    public let url: URL

    /// A GET with the token and, when known, `If-None-Match`. The token is never part of the URL.
    public func urlRequest(token: String, etag: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue(GitHubRequests.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(GitHubRequests.userAgent, forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty { r.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        r.timeoutInterval = 20
        return r
    }
}

public enum GitHubRequests {
    public static let host = "api.github.com"
    public static let apiVersion = "2022-11-28"
    public static let userAgent = "ANNUNCIATOR"
    public static let pageSize = 50

    private static func make(_ path: String, _ query: [(String, String)] = []) -> GitHubRequest {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = path
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        return GitHubRequest(url: c.url!)
    }

    /// Open PRs of one repository, newest update first. Review-requested is a filter of this list, not a search.
    public static func pulls(_ repo: RepoRef) -> GitHubRequest {
        make("/repos/\(repo.owner)/\(repo.name)/pulls", [("state", "open"), ("sort", "updated"), ("direction", "desc"), ("per_page", String(pageSize))])
    }

    /// Check runs of a head commit. nil unless `sha` is a plain hex object name.
    public static func checkRuns(_ repo: RepoRef, sha: String) -> GitHubRequest? {
        guard isSHA(sha) else { return nil }
        return make("/repos/\(repo.owner)/\(repo.name)/commits/\(sha)/check-runs", [("per_page", "100")])
    }

    public static func combinedStatus(_ repo: RepoRef, sha: String) -> GitHubRequest? {
        guard isSHA(sha) else { return nil }
        return make("/repos/\(repo.owner)/\(repo.name)/commits/\(sha)/status", [("per_page", "1")])
    }

    /// Whose token this is: needed once to filter `review-requested:@me`.
    public static let currentUser = make("/user")

    /// The next page from a `Link` header. Followed only when it stays on https://api.github.com.
    public static func page(url: URL) -> GitHubRequest? {
        guard url.scheme == "https", url.host?.lowercased() == host, url.user == nil, url.port == nil || url.port == 443 else { return nil }
        return GitHubRequest(url: url)
    }

    static func isSHA(_ s: String) -> Bool {
        (7...64).contains(s.utf8.count) && s.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
