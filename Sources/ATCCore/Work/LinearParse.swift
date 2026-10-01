// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-248 (GL1b): Linear responses to models. Lenient about missing fields, strict about URLs the app may open.

public struct LinearPage: Equatable, Sendable {
    public var issues: [LinearIssue]
    public var hasNext: Bool
    public var endCursor: String?
}

/// Why a Linear answer is not data.
public enum LinearFailure: Equatable, Sendable {
    /// HTTP 400 with `RATELIMITED` (or 429): treated like GitHub's 429.
    case rateLimited
    /// HTTP 401, or an authentication error in the body: the token is dead.
    case auth
    /// Anything else; a short text without the body.
    case other(String)
}

public enum LinearParse {
    /// The rate-limit headers. Linear sends `X-RateLimit-Requests-*`; the reset is epoch seconds (milliseconds are
    /// accepted too, since a value that large cannot be seconds).
    public static func rateLimit(_ headers: [String: String]) -> RateLimitInfo {
        let h = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        var reset = h["x-ratelimit-requests-reset"].flatMap { TimeInterval($0) }
        if let r = reset, r > 100_000_000_000 { reset = r / 1000 }
        return RateLimitInfo(
            limit: h["x-ratelimit-requests-limit"].flatMap { Int($0) },
            remaining: h["x-ratelimit-requests-remaining"].flatMap { Int($0) },
            reset: reset.map { Date(timeIntervalSince1970: $0) },
            retryAfter: h["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }.map { max(0, $0) })
    }

    /// nil when the answer is data; else what went wrong. A 2xx body with `errors` is a failure too.
    public static func failure(status: Int, body: Data) -> LinearFailure? {
        let errors = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["errors"] as? [[String: Any]] ?? []
        let tags = errors.flatMap { e -> [String] in
            let ext = e["extensions"] as? [String: Any]
            return [(ext?["code"] as? String), (ext?["type"] as? String)].compactMap { $0?.lowercased() }
        }
        if status == 429 || tags.contains(where: { $0.contains("ratelimit") }) { return .rateLimited }
        if status == 401 || tags.contains(where: { $0.contains("authentication") || $0 == "unauthenticated" }) { return .auth }
        if !(200..<300).contains(status) { return .other("HTTP \(status)") }
        if !errors.isEmpty { return .other("GraphQL error") }
        return nil
    }

    static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// One page of `data.issues`. A node without an identifier, title, state, team key, time or a linear.app page URL
    /// is skipped. nil when the body has no `data.issues`.
    public static func issues(_ body: Data) -> LinearPage? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let data = root["data"] as? [String: Any], let issues = data["issues"] as? [String: Any],
              let nodes = issues["nodes"] as? [[String: Any]]
        else { return nil }
        let list: [LinearIssue] = nodes.compactMap { n in
            guard let identifier = n["identifier"] as? String, LinearIssue.validIdentifier(identifier),
                  let title = n["title"] as? String,
                  let state = n["state"] as? [String: Any], let stateName = state["name"] as? String,
                  let team = n["team"] as? [String: Any], let key = team["key"] as? String,
                  let raw = n["updatedAt"] as? String, let updated = date(raw),
                  let urlString = n["url"] as? String, let url = URL(string: urlString), LinkRoute.workLink(url) != nil
            else { return nil }
            let type = (state["type"] as? String).flatMap(LinearStateType.init(rawValue:))
            return LinearIssue(identifier: identifier, title: title, state: LinearWorkflowState(name: stateName, type: type),
                               team: LinearTeam(key: key), updatedAt: updated, url: url)
        }
        let info = issues["pageInfo"] as? [String: Any]
        let cursor = (info?["endCursor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return LinearPage(issues: list, hasNext: (info?["hasNextPage"] as? Bool) ?? false, endCursor: cursor)
    }
}
