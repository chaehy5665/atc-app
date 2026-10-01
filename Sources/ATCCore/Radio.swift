// SPDX-License-Identifier: Apache-2.0
import Foundation

// R4: the RADIO monitor. Which transmissions are heard, the queue and its cap, and the rule that
// nothing old is replayed after a reconnect. Pure; the app target only plays the WAVs.

/// The four frequencies atc's RADIO carries. The server's `freq` names them in upper case.
public enum RadioFreq: String, CaseIterable, Sendable {
    case delivery = "DELIVERY", tower = "TOWER", ground = "GROUND", company = "COMPANY"

    public static let defaultFreq = RadioFreq.tower
}

/// The browser's "calls only / unanswered only / everything" choice (`web/src/radio-listen.ts`).
public enum RadioNoise: String, CaseIterable, Sendable {
    case calls, unanswered, all

    /// Same default as the browser.
    public static let defaultNoise = RadioNoise.calls

    public var label: String {
        switch self {
        case .calls: return "호출만"
        case .unanswered: return "답 없는 호출만"
        case .all: return "전부"
        }
    }
}

/// The monitor's switches (Settings). Off by default.
public struct RadioPrefs: Equatable, Sendable {
    public var on = false
    public var freq = RadioFreq.defaultFreq
    public var noise = RadioNoise.defaultNoise

    public init() {}

    /// Stored strings; an unknown value falls back to the default.
    public init(on: Bool, freq: String?, noise: String?) {
        self.on = on
        self.freq = freq.flatMap(RadioFreq.init(rawValue:)) ?? .defaultFreq
        self.noise = noise.flatMap(RadioNoise.init(rawValue:)) ?? .defaultNoise
    }
}

/// One recorded call or reply, as `GET /api/radio` and the SSE topic `radio` send it.
/// Only the fields the monitor uses; the server's `head` is shown as is.
public struct RadioTransmission: Decodable, Equatable, Sendable {
    public var id: String
    public var at: Date
    public var freq: String
    public var head: String
    public var replyTo: String?
    public var open: Bool

    public init(id: String, at: Date, freq: String, head: String, replyTo: String? = nil, open: Bool = false) {
        self.id = id
        self.at = at
        self.freq = freq
        self.head = head
        self.replyTo = replyTo
        self.open = open
    }

    private enum CodingKeys: String, CodingKey { case id, at, freq, head, replyTo, open }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        freq = try c.decode(String.self, forKey: .freq)
        head = try c.decodeIfPresent(String.self, forKey: .head) ?? ""
        replyTo = try c.decodeIfPresent(String.self, forKey: .replyTo)
        open = try c.decodeIfPresent(Bool.self, forKey: .open) ?? false
    }

    /// A reply has `replyTo`; everything else is a call.
    public var isCall: Bool { replyTo == nil }

    /// Same rule as the browser's `wantsToHear`.
    public func wanted(_ noise: RadioNoise) -> Bool {
        switch noise {
        case .all: return true
        case .calls: return isCall
        case .unanswered: return isCall && open
        }
    }
}

/// `{ "transmissions": [...] }`: the SSE `radio` data and the body of `GET /api/radio`.
struct RadioBatch: Decodable {
    var transmissions: [RadioTransmission]
}

extension ATCDecoding {
    public static func radio(from data: Data) throws -> [RadioTransmission] {
        try makeDecoder().decode(RadioBatch.self, from: data).transmissions
    }
}

public enum RadioURL {
    /// `GET /api/radio/<id>.wav`. Ids hold `#` and `:`, so everything but unreserved characters is escaped.
    public static func wav(base: URL, id: String) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: root + "/api/radio/" + escaped + ".wav")
    }
}

/// What to hear and in what order. Feed it transmissions and connection changes, ask it for the next one.
/// - Only what is recorded after the monitor was turned on, or after the last (re)connect, is heard.
///   The floor is the local time of that moment; anything with an older `at` is dropped, and so is
///   an old transmission the server sends again because it changed (a reply arrived). atc never
///   replays on connect, so this also covers a first burst after a reconnect.
///   (atc and the app are compared by clock; on another machine a skewed clock shifts the floor.)
/// - A transmission is considered once (by `id`): a call that gets its reply later is not played again.
/// - Nothing is queued or played while atc is unreachable, in quiet hours, or when the monitor is off.
///   Quiet hours and an unreachable atc drop what is waiting; they do not hold it.
/// - The queue holds `queueCap`; a longer one drops the oldest, as the browser does.
public struct RadioMonitor: Equatable, Sendable {
    public static let queueCap = 5
    static let seenCap = 1_000

    public private(set) var prefs = RadioPrefs()
    public private(set) var connected = false
    /// Newest transmission on the chosen frequency since the floor (or from the seed), for the popover hint.
    public private(set) var last: RadioTransmission?
    public private(set) var queue: [RadioTransmission] = []
    /// How many the cap dropped since the monitor was turned on.
    public private(set) var dropped = 0

    private var floor = Date.distantFuture
    private var seen: [String] = []
    private var seenSet = Set<String>()

    public init() {}

    /// True while the monitor is on: the app opens the `radio` stream only then.
    public var isOn: Bool { prefs.on }

    /// Applies new Settings. Turning it on, or changing the frequency, starts from `now`.
    public mutating func configure(_ new: RadioPrefs, now: Date) {
        let old = prefs
        prefs = new
        if !new.on {
            queue = []; last = nil; dropped = 0
        } else if !old.on || old.freq != new.freq {
            floor = now; queue = []; last = nil; dropped = 0
        } else if old.noise != new.noise {
            queue = queue.filter { $0.wanted(new.noise) }
        }
    }

    /// The `radio` stream is up (first connect or a reconnect): nothing before `now` is heard.
    public mutating func connect(now: Date) {
        connected = true
        floor = now
        queue = []
    }

    /// The stream is down or atc is unreachable: drop what waits, play nothing.
    public mutating func disconnect() {
        connected = false
        queue = []
    }

    /// Sets the hint from a plain GET (newest last) and marks those ids as seen, so they never play.
    public mutating func seed(_ items: [RadioTransmission]) {
        for t in items where matches(t) {
            mark(t.id)
            if last == nil || t.at >= last!.at { last = t }
        }
    }

    /// New or changed transmissions from the stream. Returns how many were queued.
    @discardableResult
    public mutating func ingest(_ items: [RadioTransmission], quiet: Bool) -> Int {
        guard prefs.on, connected else { return 0 }
        var queued = 0
        for t in items.sorted(by: { $0.at < $1.at }) where matches(t) && t.at >= floor {
            if last == nil || t.at >= last!.at { last = t }
            guard !seenSet.contains(t.id) else { continue }
            mark(t.id)
            guard !quiet, t.wanted(prefs.noise) else { continue }
            queue.append(t)
            queued += 1
        }
        if queue.count > Self.queueCap {
            dropped += queue.count - Self.queueCap
            queue.removeFirst(queue.count - Self.queueCap)
        }
        return queued
    }

    /// The next transmission to play, or nil. WARNING and CALL audio wins: while `alertBusy` nothing starts
    /// and what waits stays queued for after the alert.
    public mutating func next(alertBusy: Bool, quiet: Bool) -> RadioTransmission? {
        guard prefs.on, connected else { return nil }
        if quiet { queue = []; return nil }
        guard !alertBusy, !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    private func matches(_ t: RadioTransmission) -> Bool { t.freq.uppercased() == prefs.freq.rawValue }

    private mutating func mark(_ id: String) {
        guard seenSet.insert(id).inserted else { return }
        seen.append(id)
        if seen.count > Self.seenCap { seenSet.remove(seen.removeFirst()) }
    }
}

/// The popover's RADIO line.
public struct RadioHint: Equatable, Sendable {
    /// "RADIO ● TOWER"
    public var title: String
    /// The last transmission's `head`, or "대기 중" until one is heard.
    public var detail: String
    /// "TOWER"
    public var freq: String
    public var connected: Bool

    public init?(_ monitor: RadioMonitor) {
        guard monitor.isOn else { return nil }
        freq = monitor.prefs.freq.rawValue
        connected = monitor.connected
        title = "RADIO ● \(monitor.prefs.freq.rawValue)" + (monitor.connected ? "" : " (연결 안 됨)")
        detail = monitor.last?.head ?? "대기 중"
    }
}
