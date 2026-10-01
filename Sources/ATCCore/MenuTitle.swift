// SPDX-License-Identifier: Apache-2.0
import Foundation

/// What the menu bar item shows (ATC-222). The level, the counts and the FUEL numbers are the server's;
/// this only picks the glyph, the badge shape and the words. The shapes differ, so nothing rests on colour alone.
public struct MenuTitle: Equatable, Sendable {
    public enum Glyph: Equatable, Sendable {
        /// Template aircraft, nothing else.
        case idle
        /// Amber dot beside the count.
        case caution
        /// Red triangle badge beside the count, glyph filled.
        case warning
        /// Grey aircraft with a slash.
        case unreachable
    }

    public var glyph: Glyph
    /// Number beside the badge; 0 (nothing shown) for idle and unreachable. Warning: the WARNING count;
    /// caution: CAUTION plus WARNING. The server's `master` decides which glyph applies.
    public var count: Int
    /// A separate small blue dot: someone waits for the SUPERVISOR.
    public var needsYou: Bool
    /// "5h 6% · 7d 65%" when the Settings toggle is on and atc sent numbers; nil otherwise.
    public var fuel: String?
    /// Spoken form: "WARNING 2, CAUTION 23, advisory 13, needs you 1, 5h 16% · 7d 66%".
    public var accessibility: String

    /// Text drawn after the badge: count and FUEL, space separated; empty when there is none.
    public var text: String {
        [count > 0 ? "\(count)" : nil, fuel].compactMap { $0 }.joined(separator: " ")
    }

    public init(_ feed: FeedState, showFuel: Bool = false) {
        guard feed.connection == .live, let summary = feed.summary else {
            glyph = .unreachable
            count = 0
            needsYou = false
            fuel = nil
            accessibility = "atc unreachable"
            return
        }
        let master = MasterState(summary: summary)
        switch master.light {
        case .warning: glyph = .warning
        case .caution: glyph = .caution
        case .off: glyph = .idle
        }
        count = master.count
        needsYou = !summary.needsYou.isEmpty
        let line = FuelFormat.line(summary.fuel)
        fuel = showFuel && !line.isEmpty ? line : nil

        let c = summary.counts
        var spoken: [String] = []
        if c.warning > 0 { spoken.append("WARNING \(c.warning)") }
        if c.caution > 0 { spoken.append("CAUTION \(c.caution)") }
        if c.advisory > 0 { spoken.append("advisory \(c.advisory)") }
        if spoken.isEmpty { spoken.append("no alerts") }
        if needsYou { spoken.append("needs you \(summary.needsYou.count)") }
        if !line.isEmpty { spoken.append(line) }
        accessibility = spoken.joined(separator: ", ")
    }
}
