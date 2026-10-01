// SPDX-License-Identifier: Apache-2.0
import Foundation

/// The MASTER light: warning (red), caution (amber) or off.
public enum MasterLight: Equatable, Sendable {
    case off, caution, warning
}

public struct MasterState: Equatable, Sendable {
    public var light: MasterLight
    /// Number lit at that level and above; 0 when off.
    public var count: Int

    /// The light comes from the server's `master`; nothing is re-derived from the alerts.
    public init(summary: SupervisorSummary) {
        switch summary.master {
        case .warning:
            light = .warning
            count = summary.counts.warning
        case .caution:
            light = .caution
            count = summary.counts.caution + summary.counts.warning
        case .advisory, nil:
            light = .off
            count = 0
        }
    }

    /// Nothing known yet, or atc unreachable.
    public static let off = MasterState(light: .off, count: 0)

    public init(light: MasterLight, count: Int) {
        self.light = light
        self.count = count
    }
}

/// Lamps grouped by level, each keeping the server's order.
public struct LampGroups: Equatable, Sendable {
    public var warning: [SupervisorAlert] = []
    public var caution: [SupervisorAlert] = []
    public var advisory: [SupervisorAlert] = []
    /// Items with no level (for example a finished RTS).
    public var unleveled: [SupervisorAlert] = []

    public init(_ alerts: [SupervisorAlert]) {
        for a in alerts {
            switch a.level {
            case .warning: warning.append(a)
            case .caution: caution.append(a)
            case .advisory: advisory.append(a)
            case nil: unleveled.append(a)
            }
        }
    }
}

/// Which alert keys the app has already shown. `update` returns the new
/// WARNING and CALL keys to notify about.
public struct SeenKeys: Sendable {
    private var seen: Set<String> = []
    private var loaded = false

    public init() {}

    /// Call with the full current list. The first call only records a baseline
    /// and returns nothing. A key that is cleared and later comes back is new again.
    public mutating func update(items: [SupervisorAlert]) -> [String] {
        let current = Set(items.map(\.key))
        defer { seen = current; loaded = true }
        guard loaded else { return [] }
        return items.filter { $0.level == .warning || $0.cue == .call }
            .map(\.key)
            .filter { !seen.contains($0) }
    }
}

public enum ZTime {
    /// "HH:MMZ" in UTC.
    public static func format(_ date: Date) -> String {
        let secs = Int(date.timeIntervalSince1970.rounded(.down))
        let day = ((secs % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02dZ", day / 3_600, day % 3_600 / 60)
    }

    /// Formats an ISO 8601 string; nil when it doesn't parse.
    public static func format(iso: String) -> String? {
        ISODate.parse(iso).map(format)
    }
}
