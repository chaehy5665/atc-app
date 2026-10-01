// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-248 (GL1b): raw Linear values. Nothing here is an atc verdict (no DISPATCH or SCHEDULE state).

/// A team key typed into Settings (`ISS`, `ABC2`). Only letters and digits, starting with a letter, so a key can
/// never carry anything but data into a request (it travels as a GraphQL variable, not inside the query text).
public struct TeamKey: Hashable, Sendable {
    public let value: String

    public init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...10).contains(t.utf8.count), let first = t.first, first.isASCII, first.isLetter,
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        value = t
    }

    /// Settings text (one key per line, comma or space) to keys; bad entries are returned apart, duplicates dropped.
    public static func parseList(_ text: String) -> (keys: [TeamKey], rejected: [String]) {
        var keys: [TeamKey] = []
        var rejected: [String] = []
        for piece in text.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == " " || $0 == ";" }) {
            if let k = TeamKey(String(piece)) {
                if !keys.contains(k) { keys.append(k) }
            } else {
                rejected.append(String(piece))
            }
        }
        return (keys, rejected)
    }
}

/// Linear's own workflow state types.
public enum LinearStateType: String, Sendable, CaseIterable {
    case triage, backlog, unstarted, started, completed, canceled

    /// The word the popover line uses for the type ("Todo" is Linear's name for `unstarted`).
    public var label: String {
        switch self {
        case .triage: return "Triage"
        case .backlog: return "Backlog"
        case .unstarted: return "Todo"
        case .started: return "Started"
        case .completed: return "Done"
        case .canceled: return "Canceled"
        }
    }
}

public struct LinearWorkflowState: Equatable, Sendable {
    /// The name as the team wrote it ("In Review").
    public let name: String
    /// nil for a type this app does not know (kept in the list, counted under no label).
    public let type: LinearStateType?

    public init(name: String, type: LinearStateType?) {
        self.name = name
        self.type = type
    }
}

public struct LinearTeam: Equatable, Sendable {
    public let key: String

    public init(key: String) { self.key = key }
}

public struct LinearIssue: Equatable, Sendable, Identifiable {
    /// `ISS-12`
    public let identifier: String
    public let title: String
    public let state: LinearWorkflowState
    public let team: LinearTeam
    public let updatedAt: Date
    public let url: URL

    public var id: String { identifier }

    public init(identifier: String, title: String, state: LinearWorkflowState, team: LinearTeam, updatedAt: Date, url: URL) {
        self.identifier = identifier
        self.title = title
        self.state = state
        self.team = team
        self.updatedAt = updatedAt
        self.url = url
    }

    /// `ISS-12`: letters and digits, a dash, digits. Only such a key may be sent to atc's FLIGHT drawer.
    public static func validIdentifier(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...10).contains(parts[0].utf8.count), (1...9).contains(parts[1].utf8.count),
              let first = parts[0].first, first.isASCII, first.isLetter,
              parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber })
        else { return false }
        return true
    }
}
