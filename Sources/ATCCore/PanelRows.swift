// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-222: the calm popover. Header rows that open only when they hold items, and one status row group
// for DUTY, GitHub and RADIO. Words and counts are the server's (or GitHub's); this decides what folds.

public struct InfoItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var url: URL?
}

/// One collapsed header row under the LAMP list: PENDING, NEEDS YOU, RTS, working sessions.
public struct InfoGroup: Equatable, Sendable, Identifiable {
    public var id: String
    public var header: String
    public var items: [InfoItem]
    /// Only a group with items can open.
    public var isExpandable: Bool { !items.isEmpty }
    /// NEEDS YOU keeps its own (accent) style, so it is never mistaken for a CAUTION.
    public var isNeedsYou: Bool { id == "needsYou" }

    public func visibleItems(expanded: Bool) -> [InfoItem] { expanded && isExpandable ? items : [] }
}

public struct StatusRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case duty, work, radio }
    public var kind: Kind
    public var text: String
    /// A short word for the collapsed line: "DUTY", "GitHub 3", "RADIO TOWER".
    public var part: String
    /// DUTY not idle, CI failing, RADIO unreachable.
    public var attention: Bool
    /// DUTY only: the dot colour atc's readout gives.
    public var dot: DutyDot?
    /// GitHub only: a notice rather than counts.
    public var isNotice: Bool
    public var id: String { kind.rawValue }
}

/// DUTY, GitHub and RADIO in one group, one line each. They fold into a single line while none needs attention.
public struct StatusRows: Equatable, Sendable {
    public var rows: [StatusRow]

    public static let none = StatusRows(duty: nil, work: nil, radio: nil)

    public init(duty: DutyLamp?, work: WorkLine?, radio: RadioHint?) {
        var rows: [StatusRow] = []
        if let duty {
            rows.append(StatusRow(kind: .duty, text: duty.tooltip, part: "DUTY", attention: duty.dot != .green, dot: duty.dot, isNotice: false))
        }
        if let work {
            let part = work.openCount.map { "GitHub \($0)" } ?? "GitHub"
            rows.append(StatusRow(kind: .work, text: work.text, part: part, attention: work.ciFailing, dot: nil, isNotice: work.isNotice))
        }
        if let radio {
            rows.append(StatusRow(
                kind: .radio, text: radio.title + " " + radio.detail, part: "RADIO \(radio.freq)",
                attention: !radio.connected, dot: nil, isNotice: false))
        }
        self.rows = rows
    }

    public var needsAttention: Bool { rows.contains(where: \.attention) }
    /// `DUTY · GitHub 3 · RADIO TOWER`
    public var summary: String { rows.map(\.part).joined(separator: " · ") }
    /// While nothing needs attention the group is one summary line that the user may open.
    public var isFolded: Bool { !rows.isEmpty && !needsAttention }

    /// Lines drawn: the rows when something needs attention, else the summary plus the rows if opened.
    public func lineCount(opened: Bool) -> Int {
        if rows.isEmpty { return 0 }
        if needsAttention { return rows.count }
        return 1 + (opened ? rows.count : 0)
    }
}
