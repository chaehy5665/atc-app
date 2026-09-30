// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Wire types for what atc serves (read only). Unknown fields are ignored by
// Codable; optional fields decode to nil when missing.

/// Alert level as sent by the server. Ordered: advisory < caution < warning.
public enum AlertLevel: String, Codable, Comparable, CaseIterable, Sendable {
    case advisory, caution, warning

    private var rank: Int {
        switch self {
        case .advisory: return 0
        case .caution: return 1
        case .warning: return 2
        }
    }

    public static func < (a: AlertLevel, b: AlertLevel) -> Bool { a.rank < b.rank }
}

public enum AlertCue: String, Codable, Sendable {
    case call, done
}

/// One SUPERVISOR alert (`/api/supervisor-alerts` item, one LAMP).
public struct SupervisorAlert: Codable, Equatable, Sendable {
    public var key: String
    public var group: String
    /// nil for null or a level this build doesn't know (the server may add levels).
    public var level: AlertLevel?
    public var cue: AlertCue?
    public var aircraft: String?
    public var flight: String?
    public var text: String
    public var next: String?
    public var link: String?
    public var since: Date?

    public init(
        key: String, group: String, level: AlertLevel?, cue: AlertCue? = nil,
        aircraft: String? = nil, flight: String? = nil, text: String,
        next: String? = nil, link: String? = nil, since: Date? = nil
    ) {
        self.key = key
        self.group = group
        self.level = level
        self.cue = cue
        self.aircraft = aircraft
        self.flight = flight
        self.text = text
        self.next = next
        self.link = link
        self.since = since
    }

    private enum CodingKeys: String, CodingKey {
        case key, group, level, cue, aircraft, flight, text, next, link, since
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        group = try c.decode(String.self, forKey: .group)
        text = try c.decode(String.self, forKey: .text)
        // Unknown level or cue strings become nil instead of failing the whole list.
        level = (try c.decodeIfPresent(String.self, forKey: .level)).flatMap(AlertLevel.init(rawValue:))
        cue = (try c.decodeIfPresent(String.self, forKey: .cue)).flatMap(AlertCue.init(rawValue:))
        aircraft = try c.decodeIfPresent(String.self, forKey: .aircraft)
        flight = try c.decodeIfPresent(String.self, forKey: .flight)
        next = try c.decodeIfPresent(String.self, forKey: .next)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        since = try c.decodeIfPresent(Date.self, forKey: .since)
    }
}

/// `/api/supervisor-alerts` body.
public struct SupervisorAlertsResponse: Codable, Equatable, Sendable {
    public var items: [SupervisorAlert]
}

/// SSE `alert` event body.
public struct AlertEvent: Codable, Equatable, Sendable {
    public var raised: [SupervisorAlert]
    /// Keys that went away.
    public var cleared: [String]
    /// The whole current list.
    public var items: [SupervisorAlert]
    public var initial: Bool

    public init(raised: [SupervisorAlert] = [], cleared: [String] = [], items: [SupervisorAlert] = [], initial: Bool = false) {
        self.raised = raised
        self.cleared = cleared
        self.items = items
        self.initial = initial
    }

    private enum CodingKeys: String, CodingKey { case raised, cleared, items, initial }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raised = try c.decodeIfPresent([SupervisorAlert].self, forKey: .raised) ?? []
        cleared = try c.decodeIfPresent([String].self, forKey: .cleared) ?? []
        items = try c.decodeIfPresent([SupervisorAlert].self, forKey: .items) ?? []
        initial = try c.decodeIfPresent(Bool.self, forKey: .initial) ?? false
    }
}

/// SSE `version` event body.
public struct VersionInfo: Codable, Equatable, Sendable {
    public var build: String?
    public var startedAt: Date?
    public var head: String?
}

// MARK: - /api/supervisor-summary (v: 1)

/// Body of `/api/supervisor-summary` and the `summary` SSE event.
/// Checked against atc's server/README table and a live read (ATC-153, merged).
/// FUEL window names are atc's own (`five_hour`, `seven_day`); see `FuelFormat`.
public struct SupervisorSummary: Codable, Equatable, Sendable {
    public static let supportedVersion = 1

    public struct Counts: Codable, Equatable, Sendable {
        public var warning: Int
        public var caution: Int
        public var advisory: Int

        public init(warning: Int = 0, caution: Int = 0, advisory: Int = 0) {
            self.warning = warning
            self.caution = caution
            self.advisory = advisory
        }

        private enum CodingKeys: String, CodingKey { case warning, caution, advisory }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            warning = try c.decodeIfPresent(Int.self, forKey: .warning) ?? 0
            caution = try c.decodeIfPresent(Int.self, forKey: .caution) ?? 0
            advisory = try c.decodeIfPresent(Int.self, forKey: .advisory) ?? 0
        }
    }

    public struct Pending: Codable, Equatable, Sendable {
        public var dispatch: Int?
        public var humanCheck: Int?
        public var tool: Int?
        /// SCHEDULE decisions (approval mode, ATC-162).
        public var schedule: Int?
    }

    public struct FuelWindow: Codable, Equatable, Sendable {
        public var name: String
        public var pct: Double?
        public var resetsAt: Date?
    }

    public struct Fuel: Codable, Equatable, Sendable {
        public var label: String?
        public var windows: [FuelWindow]?
    }

    public struct RTS: Codable, Equatable, Sendable {
        public var result: String?
        public var at: Date?
        public var from: String?
        public var to: String?
    }

    public struct Working: Codable, Equatable, Sendable {
        public var aircraft: Int?
        public var control: Int?
    }

    public var v: Int
    public var at: Date?
    /// The server's MASTER light: "warning", "caution" or nil (also nil for an unknown string).
    public var master: AlertLevel?
    public var counts: Counts
    public var pending: Pending?
    public var fuel: Fuel?
    public var rts: RTS?
    public var working: Working?
    public var needsYou: [String]

    public init(
        v: Int = SupervisorSummary.supportedVersion, at: Date? = nil, master: AlertLevel? = nil,
        counts: Counts = Counts(), pending: Pending? = nil, fuel: Fuel? = nil, rts: RTS? = nil,
        working: Working? = nil, needsYou: [String] = []
    ) {
        self.v = v
        self.at = at
        self.master = master
        self.counts = counts
        self.pending = pending
        self.fuel = fuel
        self.rts = rts
        self.working = working
        self.needsYou = needsYou
    }

    private enum CodingKeys: String, CodingKey {
        case v, at, master, counts, pending, fuel, rts, working, needsYou
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        at = try c.decodeIfPresent(Date.self, forKey: .at)
        master = (try c.decodeIfPresent(String.self, forKey: .master)).flatMap(AlertLevel.init(rawValue:))
        counts = try c.decodeIfPresent(Counts.self, forKey: .counts) ?? Counts()
        pending = try c.decodeIfPresent(Pending.self, forKey: .pending)
        fuel = try c.decodeIfPresent(Fuel.self, forKey: .fuel)
        rts = try c.decodeIfPresent(RTS.self, forKey: .rts)
        working = try c.decodeIfPresent(Working.self, forKey: .working)
        needsYou = try c.decodeIfPresent([String].self, forKey: .needsYou) ?? []
    }
}

// MARK: - Decoding

public enum ATCError: Error, Equatable {
    /// The summary body has a `v` this build doesn't understand (or none).
    case unsupportedVersion(Int?)
    case badStatus(Int)
    case badResponse
}

public enum ATCDecoding {
    /// Decoder for atc bodies: ISO 8601 UTC dates, with or without fractional seconds.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ISODate.parse(s) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: d.codingPath, debugDescription: "bad ISO 8601 date: \(s)"))
            }
            return date
        }
        return decoder
    }

    public static func alerts(from data: Data) throws -> [SupervisorAlert] {
        try makeDecoder().decode(SupervisorAlertsResponse.self, from: data).items
    }

    /// Checks `v` first, so a future shape fails as `unsupportedVersion` and not as a decode error.
    public static func summary(from data: Data) throws -> SupervisorSummary {
        struct Probe: Decodable { var v: Int? }
        let v = (try? JSONDecoder().decode(Probe.self, from: data))?.v
        guard v == SupervisorSummary.supportedVersion else { throw ATCError.unsupportedVersion(v) }
        return try makeDecoder().decode(SupervisorSummary.self, from: data)
    }
}

public enum ISODate {
    /// Parses "2026-09-29T17:03:16.139Z" and "2026-09-29T17:03:16Z".
    public static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - SSE events

/// A typed SSE event from `/api/events`.
public enum ATCEvent: Equatable, Sendable {
    case alert(AlertEvent)
    case summary(SupervisorSummary)
    case version(VersionInfo)
    case ping
    /// `snapshot` and anything else this build doesn't use.
    case other(String)

    public init(_ event: SSEEvent) throws {
        let decoder = ATCDecoding.makeDecoder()
        let body = Data(event.data.utf8)
        switch event.name {
        case "alert": self = .alert(try decoder.decode(AlertEvent.self, from: body))
        case "summary": self = .summary(try ATCDecoding.summary(from: body))
        case "version": self = .version(try decoder.decode(VersionInfo.self, from: body))
        case "ping": self = .ping
        default: self = .other(event.name)
        }
    }
}
