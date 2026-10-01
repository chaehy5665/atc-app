// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): the popover line and the Work window rows. Raw GitHub counts and labels only. This never
// lights the MASTER light and never recomputes an atc verdict (CLEARED TO LAND, a LANDING tier, STRANDED).

public enum WorkFilter: String, Sendable, CaseIterable {
    case all
    /// PRs that ask the signed-in user for review (`requested_reviewers` has their login).
    case reviewRequested
}

public struct WorkLine: Equatable, Sendable {
    public var text: String
    /// A notice (rate limit, sign-in, error) rather than the counts.
    public var isNotice: Bool
    /// Open PRs, for the collapsed status line ("GitHub 3"); nil for a notice.
    public var openCount: Int? = nil
    /// At least one PR has failing CI: the one thing in this line that needs attention.
    public var ciFailing = false
}

public struct WorkRow: Equatable, Sendable, Identifiable {
    public enum CI: String, Sendable { case failing, pending, passing, none }

    public var id: String
    public var title: String
    /// `repo-a #12 · author · 3h`
    public var detail: String
    public var ci: CI
    public var ciLabel: String
    public var reviewLabel: String?
    public var isDraft: Bool
    /// The PR page; nil if it is not a link the app may open (`LinkRoute.workLink`).
    public var url: URL?
}

public enum WorkPanel {
    /// "Decide in atc ↗" opens this atc tab. The PR drawer (`#pr/<AIRPORT>/<n>`) needs atc's airport name, which the
    /// app does not know, so the row opens STRIPS, where atc lists the PRs per team (PILOT'S DISCRETION).
    public static let atcFragment = "strips"

    // MARK: Popover line

    /// nil hides the line: signed out. `repos` is the number of configured repositories.
    public static func line(_ s: GitHubSnapshot, signedIn: Bool, repos: Int, now: Date, timeZone: TimeZone = .current) -> WorkLine? {
        guard signedIn else { return nil }
        if repos == 0 { return notice("GitHub: 저장소를 Settings에 추가하세요") }
        switch s.status {
        case .rateLimited(let until): return notice("GitHub rate limited, retrying at \(clock(until, timeZone))")
        case .capReached(let until): return notice("GitHub: 시간당 요청 한도에 도달, \(clock(until, timeZone))에 다시 시작")
        case .needsSignIn: return notice("GitHub: 다시 로그인이 필요합니다")
        case .error(let message): return s.fetchedAt == nil ? notice("GitHub: 읽지 못함 (\(message))") : counts(s)
        case .idle: return s.fetchedAt == nil ? notice("GitHub: 읽는 중…") : counts(s)
        case .ok: return counts(s)
        }
    }

    private static func notice(_ text: String) -> WorkLine { WorkLine(text: text, isNotice: true) }

    private static func counts(_ s: GitHubSnapshot) -> WorkLine {
        let failing = s.pulls.filter { $0.ci?.isFailing ?? false }.count
        let review = s.pulls.filter { $0.review.requests(login: s.login) }.count
        var parts = ["\(s.pulls.count) open"]
        if failing > 0 { parts.append("\(failing) CI failing") }
        if review > 0 { parts.append("\(review) review requested") }
        return WorkLine(text: "GitHub: " + parts.joined(separator: " · "), isNotice: false, openCount: s.pulls.count, ciFailing: failing > 0)
    }

    // MARK: Window

    public static func rows(_ s: GitHubSnapshot, filter: WorkFilter, now: Date) -> [WorkRow] {
        s.pulls
            .filter { filter == .all || $0.review.requests(login: s.login) }
            .map { pr in
                let ci = ciState(pr.ci)
                var detail = "\(pr.repo.name) #\(pr.number)"
                if !pr.author.isEmpty { detail += " · \(pr.author)" }
                detail += " · " + AgeFormat.short(since: pr.updatedAt, now: now)
                return WorkRow(
                    id: pr.id, title: pr.title, detail: detail, ci: ci, ciLabel: ciLabel(ci),
                    reviewLabel: pr.review.requests(login: s.login) ? "review requested" : nil,
                    isDraft: pr.isDraft, url: LinkRoute.workLink(pr.url))
            }
    }

    /// Window header: the same notices as the popover, or when the list was read.
    public static func header(_ s: GitHubSnapshot, now: Date, timeZone: TimeZone = .current) -> String {
        switch s.status {
        case .rateLimited(let until): return "GitHub rate limited, retrying at \(clock(until, timeZone))"
        case .capReached(let until): return "시간당 요청 한도에 도달, \(clock(until, timeZone))에 다시 시작"
        case .needsSignIn: return "다시 로그인이 필요합니다 (Settings)"
        case .error(let message): return "읽지 못함: \(message)"
        case .idle, .ok:
            guard let at = s.fetchedAt else { return "읽는 중…" }
            var text = "\(s.pulls.count) open · \(AgeFormat.short(since: at, now: now)) 전 갱신"
            if !s.failedRepos.isEmpty { text += " · 읽지 못한 저장소 \(s.failedRepos.count)" }
            return text
        }
    }

    static func ciState(_ ci: CheckRollup?) -> WorkRow.CI {
        guard let ci else { return .none }
        if ci.isFailing { return .failing }
        if ci.isPending { return .pending }
        return ci.isEmpty ? .none : .passing
    }

    static func ciLabel(_ ci: WorkRow.CI) -> String {
        switch ci {
        case .failing: return "CI failing"
        case .pending: return "CI pending"
        case .passing: return "CI passing"
        case .none: return "CI —"
        }
    }

    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
