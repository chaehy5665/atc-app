// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Presentation rules for the status item and the popover. The server decides
// levels, texts and numbers; this file only picks words, order and links.

public enum FuelFormat {
    /// "five_hour" -> "5h", "seven_day" -> "7d", "seven_day_opus" -> "7d opus"; unknown names pass through.
    public static func shortName(_ name: String) -> String {
        for (prefix, short) in [("five_hour", "5h"), ("seven_day", "7d")] where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count).replacingOccurrences(of: "_", with: " ")
            return short + rest
        }
        return name
    }

    /// "45%": rounded, never negative.
    public static func percent(_ pct: Double) -> String { "\(max(0, Int(pct.rounded())))%" }

    /// "5h 45% · 7d 55%"; windows without a number are left out.
    public static func line(_ fuel: SupervisorSummary.Fuel?) -> String {
        (fuel?.windows ?? []).compactMap { w in
            w.pct.map { "\(shortName(w.name)) \(percent($0))" }
        }.joined(separator: " · ")
    }
}

public enum Connection: Equatable, Sendable {
    case connecting, live, unreachable
    /// The summary has a `v` this build doesn't know.
    case unsupported
}

/// What the menu bar item shows.
public struct StatusBarTitle: Equatable, Sendable {
    public enum Symbol: Equatable, Sendable {
        /// Filled circle in the MASTER colour (a plain plane when the light is off).
        case light(MasterLight)
        /// Grey `✈ —`.
        case unreachable
    }

    public var symbol: Symbol
    /// Text after the symbol: "3  5h 45% · 7d 55%". Empty when there is nothing to add.
    public var text: String
    /// Plain-text form for accessibility and logs.
    public var plain: String

    public init(_ feed: FeedState) {
        if feed.connection == .live, let summary = feed.summary {
            let master = MasterState(summary: summary)
            let parts = [master.count > 0 ? "\(master.count)" : "", FuelFormat.line(summary.fuel)].filter { !$0.isEmpty }
            symbol = .light(master.light)
            text = parts.joined(separator: "  ")
            plain = "✈" + (text.isEmpty ? "" : " " + text)
        } else {
            symbol = .unreachable
            text = "—"
            plain = "✈ —"
        }
    }
}

// MARK: - Links

public enum ATCLink {
    /// `http://localhost:7700` + "#strips" -> `http://localhost:7700/#strips`. A nil link opens the base.
    public static func url(base: URL, link: String?) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        guard let link, !link.isEmpty else { return URL(string: root + "/") }
        return URL(string: root + "/" + link.drop(while: { $0 == "/" }))
    }
}

// MARK: - Popover

public struct LampRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var level: AlertLevel
    public var text: String
    /// "AIRCRAFT TEAM_K", "FLIGHT ATC-157" or both; nil when the server names neither (a STAND name is in the text).
    public var place: String?
    public var next: String?
    public var url: URL?
    public var since: Date?
}

public struct LampSection: Equatable, Sendable, Identifiable {
    public var level: AlertLevel
    public var rows: [LampRow]
    public var id: AlertLevel { level }
    public var title: String { level.rawValue.uppercased() }
}

public struct PendingRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case dispatch, humanCheck, tool, schedule }
    public var kind: Kind
    public var count: Int
    public var url: URL?
    public var id: String { kind.rawValue }
    public var title: String {
        switch kind {
        case .dispatch: return "DISPATCH"
        case .humanCheck: return "HUMAN CHECK"
        case .tool: return "TOOL APPROVAL"
        case .schedule: return "SCHEDULE"
        }
    }
}

public struct FuelRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var used: String
    /// "07:50Z"; nil when unknown.
    public var resets: String?
    public var id: String { name }
}

public struct PanelContent: Equatable, Sendable {
    /// Shown instead of the body when atc can't be read.
    public var notice: String?
    public var sections: [LampSection] = []
    public var pending: [PendingRow] = []
    /// "RTS OK 0e28276 → d5c6346 · 03:22Z".
    public var rts: String?
    public var fuelLabel: String?
    public var fuel: [FuelRow] = []
    public var workingAircraft = 0
    public var workingControl = 0
    public var needsYou: [String] = []
    public var hasSummary = false

    public static let connectingNotice = "atc에 연결하는 중…"
    public static let unreachableNotice = "atc 연결 안 됨 — SSH 포워딩을 확인하세요"
    public static let unsupportedNotice = "atc 버전 확인 — 이 앱이 모르는 summary 버전입니다"

    public init(_ feed: FeedState, base: URL) {
        switch feed.connection {
        case .connecting: notice = Self.connectingNotice
        case .unreachable: notice = Self.unreachableNotice
        case .unsupported: notice = Self.unsupportedNotice
        case .live: break
        }
        // Stale data stays hidden while the notice shows, so a grey light never sits beside live-looking numbers.
        guard notice == nil else { return }

        let groups = LampGroups(feed.alerts)
        for (level, alerts) in [(AlertLevel.warning, groups.warning), (.caution, groups.caution), (.advisory, groups.advisory)]
        where !alerts.isEmpty {
            sections.append(LampSection(level: level, rows: alerts.map { Self.row($0, level: level, base: base) }))
        }

        guard let s = feed.summary else { return }
        hasSummary = true
        let linkByPrefix = { (prefix: String) in feed.alerts.first { $0.key.hasPrefix(prefix) }?.link }
        for (kind, n, prefix) in [
            (PendingRow.Kind.dispatch, s.pending?.dispatch, "pending|proposal|"),
            (.humanCheck, s.pending?.humanCheck, "pending|humancheck|"),
            (.tool, s.pending?.tool, "pending|tool|"),
            (.schedule, s.pending?.schedule, "pending|schedule|"),
        ] {
            guard let n, n > 0 else { continue }
            pending.append(PendingRow(kind: kind, count: n, url: ATCLink.url(base: base, link: linkByPrefix(prefix) ?? "#dispatch")))
        }
        if let r = s.rts {
            let short = { (sha: String) in String(sha.prefix(7)) }
            let route = [r.from.map(short), r.to.map(short)].compactMap { $0 }.joined(separator: " → ")
            let head = "RTS " + (r.result ?? "?").uppercased() + (route.isEmpty ? "" : " " + route)
            rts = ([head] + [r.at.map(ZTime.format)].compactMap { $0 }).joined(separator: " · ")
        }
        fuelLabel = s.fuel?.label
        fuel = (s.fuel?.windows ?? []).map {
            FuelRow(name: FuelFormat.shortName($0.name), used: $0.pct.map(FuelFormat.percent) ?? "—", resets: $0.resetsAt.map(ZTime.format))
        }
        workingAircraft = s.working?.aircraft ?? 0
        workingControl = s.working?.control ?? 0
        needsYou = s.needsYou
    }

    private static func row(_ a: SupervisorAlert, level: AlertLevel, base: URL) -> LampRow {
        let place = [a.aircraft.map { "AIRCRAFT \($0)" }, a.flight.map { "FLIGHT \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return LampRow(
            id: a.key, level: level, text: a.text, place: place.isEmpty ? nil : place,
            next: a.next.flatMap { $0.isEmpty ? nil : $0 }, url: ATCLink.url(base: base, link: a.link), since: a.since)
    }
}

// MARK: - Settings

public enum ATCSettings {
    public static let defaultURLString = "http://localhost:7700"

    /// Turns what the user typed into the atc base URL, or nil if it isn't one.
    /// A missing scheme means http; only http and https with a host are accepted; path and query are dropped.
    public static func normalizeURL(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var parts = URLComponents(string: s),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        parts.scheme = scheme
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url
    }
}
