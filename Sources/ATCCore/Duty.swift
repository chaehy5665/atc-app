// SPDX-License-Identifier: Apache-2.0
import Foundation

// D6: DUTY's state at a glance. Read only: `GET /api/duty/status`. The `duty` SSE topic carries chat
// text and is never subscribed to; DUTY text is never spoken or notified (atc docs/duty.md).

/// The part of `/api/duty/status` the app shows. Every field but `enabled` may be missing (older atc, or DUTY off).
public struct DutyStatus: Decodable, Equatable, Sendable {
    public var enabled: Bool
    /// atc's own readout: `idle`, `answering`, `down`, `blocked`; other values are kept as sent.
    public var state: String?
    public var blocked: Bool?
    public var account: String?
    public var context: Int?
    public var cap: Int?

    public init(enabled: Bool, state: String? = nil, blocked: Bool? = nil, account: String? = nil, context: Int? = nil, cap: Int? = nil) {
        self.enabled = enabled
        self.state = state
        self.blocked = blocked
        self.account = account
        self.context = context
        self.cap = cap
    }
}

/// The dot next to DUTY. It follows atc's own drawer readout; the app does not add rules.
public enum DutyDot: String, Equatable, Sendable {
    case green, amber, red
    /// A state this build does not know: shown, but not coloured.
    case grey
}

public struct DutyLamp: Equatable, Sendable {
    public var dot: DutyDot
    /// `DUTY · <account> · context <k>/<cap>k`; parts atc did not send are left out.
    public var tooltip: String

    /// The fragment the DUTY row and menu item open: the web UI opens the drawer at `#duty`.
    public static let fragment = "duty"

    /// nil hides the row: no status yet, a failed read, or DUTY disabled.
    public static func of(_ status: DutyStatus?) -> DutyLamp? {
        guard let status, status.enabled else { return nil }
        return DutyLamp(dot: dot(status), tooltip: tooltip(status))
    }

    private static func dot(_ s: DutyStatus) -> DutyDot {
        if s.blocked == true { return .red }
        switch s.state {
        case "idle": return .green
        case "answering": return .amber
        case "down", "blocked": return .red
        default: return .grey
        }
    }

    private static func tooltip(_ s: DutyStatus) -> String {
        var parts = ["DUTY"]
        if let account = s.account, !account.isEmpty { parts.append(account) }
        if let context = s.context {
            let k = Int((Double(context) / 1000).rounded())
            if let cap = s.cap, cap > 0 {
                parts.append("context \(k)/\(Int((Double(cap) / 1000).rounded()))k")
            } else {
                parts.append("context \(k)k")
            }
        }
        return parts.joined(separator: " · ")
    }
}

extension ATCDecoding {
    public static func duty(from data: Data) throws -> DutyStatus {
        try JSONDecoder().decode(DutyStatus.self, from: data)
    }
}
