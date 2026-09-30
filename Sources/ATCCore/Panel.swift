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
    /// Text after the symbol: "23 +13 5h 45% · 7d 55%". Empty when there is nothing to add.
    public var text: String
    /// Plain-text form for logs.
    public var plain: String
    /// Spoken form: "WARNING 2, CAUTION 23, advisory 13, 5h 16% · 7d 66%".
    public var accessibility: String

    /// Same rule as atc's `menubar/format.mjs` `titleOf`: `warning + caution`, then ` +advisory`
    /// when not zero, then FUEL. The colour comes from the server's `master`, not from the counts.
    public init(_ feed: FeedState) {
        if feed.connection == .live, let summary = feed.summary {
            let c = summary.counts
            let fuel = FuelFormat.line(summary.fuel)
            var count = "\(c.warning + c.caution)"
            if c.advisory > 0 { count += " +\(c.advisory)" }
            symbol = .light(MasterState(summary: summary).light)
            text = [count, fuel].filter { !$0.isEmpty }.joined(separator: " ")
            plain = "✈ " + text
            var spoken: [String] = []
            if c.warning > 0 { spoken.append("WARNING \(c.warning)") }
            if c.caution > 0 { spoken.append("CAUTION \(c.caution)") }
            if c.advisory > 0 { spoken.append("advisory \(c.advisory)") }
            if spoken.isEmpty { spoken.append("no alerts") }
            if !fuel.isEmpty { spoken.append(fuel) }
            accessibility = spoken.joined(separator: ", ")
        } else {
            symbol = .unreachable
            text = "—"
            plain = "✈ —"
            accessibility = "atc unreachable"
        }
    }
}

// MARK: - Height

/// Popover height that fits the content. An estimate, so it can be tested; the lamp list scrolls the rest.
public enum PanelLayout {
    public static let width = 420.0
    public static let minHeight = 240.0
    public static let maxHeight = 640.0

    static let strip = 64.0, chips = 34.0, fuelRow = 22.0, statusLine = 22.0, footer = 46.0, radioLine = 22.0, dutyLine = 22.0
    static let sectionHeader = 26.0, lampRow = 38.0, toggle = 26.0, padding = 24.0

    public static func height(for panel: PanelContent, expansion: LampExpansion, radioLine hasRadio: Bool = false, dutyLine hasDuty: Bool = false) -> Double {
        guard panel.notice == nil else { return minHeight }
        var h = strip + statusLine + footer + padding
        if hasRadio { h += radioLine }
        if hasDuty { h += dutyLine }
        if !panel.pending.isEmpty || !panel.needsYouChips.isEmpty { h += chips }
        h += Double(panel.fuel.count) * fuelRow
        for section in panel.sections {
            let expanded = expansion.isExpanded(section.level)
            h += sectionHeader + Double(section.visibleRows(expanded: expanded).count) * lampRow
            if section.toggleLabel(expanded: expanded) != nil { h += toggle }
        }
        if panel.sections.isEmpty { h += sectionHeader }
        return min(maxHeight, max(minHeight, h))
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
    /// "W", "C" or "A": the level as a letter, so the row doesn't rely on colour alone.
    public var chip: String
    /// "4m", "3h", "2d" from `since`; nil when the server sent none.
    public var age: String?
}

/// "4m", "3h", "2d": how long ago, rounded down to one unit.
public enum AgeFormat {
    public static func short(since: Date, now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(since)))
        if secs < 60 { return "<1m" }
        if secs < 3_600 { return "\(secs / 60)m" }
        if secs < 86_400 { return "\(secs / 3_600)h" }
        return "\(secs / 86_400)d"
    }
}

/// Which lamps a section shows. WARNING is always all of them, CAUTION the first `cautionLimit`
/// until expanded, ADVISORY none until expanded (the header carries the count).
public enum LampFold {
    public static let cautionLimit = 5

    /// Rows shown for `level` with `total` lamps.
    public static func visibleCount(level: AlertLevel, total: Int, expanded: Bool) -> Int {
        if expanded { return total }
        switch level {
        case .warning: return total
        case .caution: return min(total, cautionLimit)
        case .advisory: return 0
        }
    }

    /// WARNING can't be collapsed.
    public static func isCollapsible(_ level: AlertLevel) -> Bool { level != .warning }
}

/// Which sections the user expanded. Persisted as the raw level names.
public struct LampExpansion: Equatable, Sendable {
    public private(set) var expanded: Set<AlertLevel>

    /// Nothing is expanded by default: CAUTION shows its first rows and ADVISORY is folded.
    public init(stored: [String]? = nil) {
        expanded = Set((stored ?? []).compactMap(AlertLevel.init(rawValue:)).filter(LampFold.isCollapsible))
    }

    public func isExpanded(_ level: AlertLevel) -> Bool { level == .warning || expanded.contains(level) }

    public mutating func toggle(_ level: AlertLevel) {
        guard LampFold.isCollapsible(level) else { return }
        if expanded.contains(level) { expanded.remove(level) } else { expanded.insert(level) }
    }

    public var stored: [String] { expanded.map(\.rawValue).sorted() }
}

public struct LampSection: Equatable, Sendable, Identifiable {
    public var level: AlertLevel
    public var rows: [LampRow]
    public var id: AlertLevel { level }
    public var title: String { level.rawValue.uppercased() }
    /// "WARNING 2", "CAUTION 23", "ADVISORY 13".
    public var header: String { "\(title) \(rows.count)" }

    public func visibleRows(expanded: Bool) -> [LampRow] {
        Array(rows.prefix(LampFold.visibleCount(level: level, total: rows.count, expanded: expanded)))
    }

    /// The control that folds or unfolds the rest: "CAUTION 18개 더", "접기"; nil when there is nothing to fold.
    /// ADVISORY folds behind its header, so it has no separate control.
    public func toggleLabel(expanded: Bool) -> String? {
        guard level == .caution, rows.count > LampFold.cautionLimit else { return nil }
        return expanded ? "접기" : "\(title) \(rows.count - LampFold.cautionLimit)개 더"
    }
}

/// One annunciator tile: MASTER WARNING, MASTER CAUTION, ADVISORY.
public struct AnnunciatorTile: Equatable, Sendable, Identifiable {
    public var level: AlertLevel
    public var label: String
    public var count: Int
    public var id: AlertLevel { level }
    public var isLit: Bool { count > 0 }
}

public struct NeedsYouChip: Equatable, Sendable, Identifiable {
    public var name: String
    public var url: URL?
    public var id: String { name }
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
    /// 0...1 for a bar; nil when the server sent no number.
    public var fraction: Double?
    public var id: String { name }
    /// "45% · 07:50Z"; "—" without a number.
    public var detail: String { [used, resets].compactMap { $0 }.joined(separator: " · ") }
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
    public var needsYouChips: [NeedsYouChip] = []
    public var tiles: [AnnunciatorTile] = []
    /// "RTS OK 0e28276 → d5c6346 · 03:22Z · AIRCRAFT 3 · CONTROL 2" (monospaced).
    public var statusLine = ""
    public var hasSummary = false

    public static let connectingNotice = "atc에 연결하는 중…"
    public static let unreachableNotice = "atc 연결 안 됨 — SSH 포워딩을 확인하세요"
    public static let unsupportedNotice = "atc 버전 확인 — 이 앱이 모르는 summary 버전입니다"

    public init(_ feed: FeedState, base: URL, now: Date = Date()) {
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
            sections.append(LampSection(level: level, rows: alerts.map { Self.row($0, level: level, base: base, now: now) }))
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
            FuelRow(
                name: FuelFormat.shortName($0.name), used: $0.pct.map(FuelFormat.percent) ?? "—",
                resets: $0.resetsAt.map(ZTime.format), fraction: $0.pct.map { min(1, max(0, $0 / 100)) })
        }
        workingAircraft = s.working?.aircraft ?? 0
        workingControl = s.working?.control ?? 0
        needsYou = s.needsYou
        // Names are AIRCRAFT; they open the strips tab.
        needsYouChips = s.needsYou.map { NeedsYouChip(name: $0, url: ATCLink.url(base: base, link: "#strips")) }
        tiles = [
            AnnunciatorTile(level: .warning, label: "MASTER WARNING", count: s.counts.warning),
            AnnunciatorTile(level: .caution, label: "MASTER CAUTION", count: s.counts.caution),
            AnnunciatorTile(level: .advisory, label: "ADVISORY", count: s.counts.advisory),
        ]
        statusLine = ([rts] + ["AIRCRAFT \(workingAircraft)", "CONTROL \(workingControl)"]).compactMap { $0 }.joined(separator: " · ")
    }

    private static func row(_ a: SupervisorAlert, level: AlertLevel, base: URL, now: Date) -> LampRow {
        let place = [a.aircraft.map { "AIRCRAFT \($0)" }, a.flight.map { "FLIGHT \($0)" }].compactMap { $0 }.joined(separator: " · ")
        return LampRow(
            id: a.key, level: level, text: a.text, place: place.isEmpty ? nil : place,
            next: a.next.flatMap { $0.isEmpty ? nil : $0 }, url: ATCLink.url(base: base, link: a.link), since: a.since,
            chip: String(level.rawValue.prefix(1)).uppercased(), age: a.since.map { AgeFormat.short(since: $0, now: now) })
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
