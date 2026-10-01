// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): raw GitHub values. Nothing here is an atc verdict (no CLEARED, tier or STRANDED).

/// `owner/name`, typed into Settings. Only GitHub's own name characters pass, so a repo can never
/// add path segments or a query to a request URL.
public struct RepoRef: Hashable, Sendable {
    public let owner: String
    public let name: String

    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, Self.valid(String(parts[0]), dot: false), Self.valid(String(parts[1]), dot: true) else { return nil }
        owner = String(parts[0])
        name = String(parts[1])
    }

    public var fullName: String { owner + "/" + name }

    private static func valid(_ s: String, dot: Bool) -> Bool {
        guard (1...100).contains(s.utf8.count), s != ".", s != ".." else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || (dot && $0 == ".")) }
    }

    /// Settings text (one `owner/name` per line, comma or space) to repos; bad entries are returned apart, duplicates dropped.
    public static func parseList(_ text: String) -> (repos: [RepoRef], rejected: [String]) {
        var repos: [RepoRef] = []
        var rejected: [String] = []
        for piece in text.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == " " }) {
            if let r = RepoRef(String(piece)) {
                if !repos.contains(r) { repos.append(r) }
            } else {
                rejected.append(String(piece))
            }
        }
        return (repos, rejected)
    }
}

/// One check run as GitHub reports it: `status` (queued, in_progress, completed) and `conclusion` (success, failure, ...).
public struct CheckRun: Equatable, Sendable {
    public let status: String
    public let conclusion: String?

    public init(status: String, conclusion: String?) {
        self.status = status
        self.conclusion = conclusion
    }
}

/// The CI facts of one head commit: its check runs and the legacy combined status (`success`, `failure`, `error`, `pending`).
public struct CheckRollup: Equatable, Sendable {
    public var checkRuns: [CheckRun]
    public var combinedState: String?

    public init(checkRuns: [CheckRun], combinedState: String?) {
        self.checkRuns = checkRuns
        self.combinedState = combinedState
    }

    /// GitHub's own failure conclusions. `neutral`, `skipped`, `stale` and `cancelled` are not counted as failing.
    static let failingConclusions: Set<String> = ["failure", "timed_out", "startup_failure", "action_required"]

    public var isFailing: Bool {
        checkRuns.contains { $0.conclusion.map(Self.failingConclusions.contains) ?? false }
            || combinedState == "failure" || combinedState == "error"
    }

    /// Something has not finished: worth asking again even when the PR's `updated_at` did not move.
    public var isPending: Bool {
        checkRuns.contains { $0.status != "completed" } || combinedState == "pending"
    }

    /// No check run and no status: GitHub reports `pending` for a commit with no status at all.
    public var isEmpty: Bool { checkRuns.isEmpty && (combinedState == nil || combinedState == "pending") }
}

/// Who GitHub says is asked to review. Submitted reviews are not fetched (one more request per PR).
public struct ReviewState: Equatable, Sendable {
    public var requestedReviewers: [String]
    public var requestedTeams: [String]

    public init(requestedReviewers: [String] = [], requestedTeams: [String] = []) {
        self.requestedReviewers = requestedReviewers
        self.requestedTeams = requestedTeams
    }

    public func requests(login: String?) -> Bool {
        guard let login else { return false }
        return requestedReviewers.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
    }
}

public struct PullRequest: Equatable, Sendable, Identifiable {
    public let repo: RepoRef
    public let number: Int
    public let title: String
    public let author: String
    public let isDraft: Bool
    public let headSHA: String
    /// GitHub's `updated_at` as sent; compared as text so a change is never lost to date rounding.
    public let updatedAtRaw: String
    public let updatedAt: Date
    public let url: URL
    public let review: ReviewState
    /// nil until fetched.
    public var ci: CheckRollup?

    public var id: String { "\(repo.fullName)#\(number)" }

    public init(repo: RepoRef, number: Int, title: String, author: String, isDraft: Bool, headSHA: String, updatedAtRaw: String, updatedAt: Date, url: URL, review: ReviewState, ci: CheckRollup? = nil) {
        self.repo = repo
        self.number = number
        self.title = title
        self.author = author
        self.isDraft = isDraft
        self.headSHA = headSHA
        self.updatedAtRaw = updatedAtRaw
        self.updatedAt = updatedAt
        self.url = url
        self.review = review
        self.ci = ci
    }
}
