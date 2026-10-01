// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): GitHub responses to models. Lenient about missing fields, strict about URLs the app may open.

/// The rate-limit headers of one response.
public struct RateLimitInfo: Equatable, Sendable {
    public var limit: Int?
    public var remaining: Int?
    /// `x-ratelimit-reset`, epoch seconds.
    public var reset: Date?
    /// `retry-after`, seconds.
    public var retryAfter: TimeInterval?

    public init(limit: Int? = nil, remaining: Int? = nil, reset: Date? = nil, retryAfter: TimeInterval? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
        self.retryAfter = retryAfter
    }
}

public enum GitHubParse {
    /// Header names lowercased, so lookups do not depend on how a transport cased them.
    public static func lowercased(_ headers: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            if let key = k as? String { out[key.lowercased()] = String(describing: v) }
        }
        return out
    }

    public static func rateLimit(_ headers: [String: String]) -> RateLimitInfo {
        let h = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        return RateLimitInfo(
            limit: h["x-ratelimit-limit"].flatMap { Int($0) },
            remaining: h["x-ratelimit-remaining"].flatMap { Int($0) },
            reset: h["x-ratelimit-reset"].flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) },
            retryAfter: h["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }.map { max(0, $0) })
    }

    /// Whether a 403 or 429 is GitHub saying "slow down" (primary or secondary limit) and not a permission error.
    public static func isRateLimited(status: Int, info: RateLimitInfo, body: Data) -> Bool {
        if status == 429 { return true }
        guard status == 403 else { return false }
        if info.retryAfter != nil || info.remaining == 0 { return true }
        let text = String(decoding: body.prefix(2_000), as: UTF8.self).lowercased()
        return text.contains("rate limit")
    }

    /// The `rel="next"` URL of a `Link` header, if any.
    public static func nextLink(_ header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces[0].hasPrefix("<"), pieces[0].hasSuffix(">") else { continue }
            guard pieces.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == "rel=\"next\"" }) else { continue }
            return URL(string: String(pieces[0].dropFirst().dropLast()))
        }
        return nil
    }

    // MARK: Bodies

    private static func array(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// Open PRs of one repository. An entry without a number, title, head SHA or a github.com page URL is skipped.
    /// nil when the body is not a JSON array.
    public static func pulls(_ data: Data, repo: RepoRef) -> [PullRequest]? {
        guard let items = array(data) else { return nil }
        return items.compactMap { o in
            guard let number = o["number"] as? Int,
                  let title = o["title"] as? String,
                  let head = o["head"] as? [String: Any], let sha = head["sha"] as? String, GitHubRequests.isSHA(sha),
                  let raw = o["updated_at"] as? String, let updated = date(raw),
                  let htmlString = o["html_url"] as? String, let html = URL(string: htmlString),
                  LinkRoute.workLink(html) != nil
            else { return nil }
            let user = o["user"] as? [String: Any]
            let reviewers = (o["requested_reviewers"] as? [[String: Any]])?.compactMap { $0["login"] as? String } ?? []
            let teams = (o["requested_teams"] as? [[String: Any]])?.compactMap { ($0["slug"] as? String) ?? ($0["name"] as? String) } ?? []
            return PullRequest(
                repo: repo, number: number, title: title, author: (user?["login"] as? String) ?? "",
                isDraft: (o["draft"] as? Bool) ?? false, headSHA: sha, updatedAtRaw: raw, updatedAt: updated, url: html,
                review: ReviewState(requestedReviewers: reviewers, requestedTeams: teams))
        }
    }

    public static func checkRuns(_ data: Data) -> [CheckRun]? {
        guard let o = object(data), let runs = o["check_runs"] as? [[String: Any]] else { return nil }
        return runs.compactMap { r in
            guard let status = r["status"] as? String else { return nil }
            return CheckRun(status: status, conclusion: r["conclusion"] as? String)
        }
    }

    /// The legacy combined status: `success`, `failure`, `error` or `pending`.
    public static func combinedState(_ data: Data) -> String? {
        object(data)?["state"] as? String
    }

    public static func login(_ data: Data) -> String? {
        (object(data)?["login"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
