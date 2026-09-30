// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// N4: which alerts notify, what sounds, and when it stays quiet. Pure; the app target only
// posts notifications and plays audio from the plan computed here.

/// What a notifying alert is. Ordered: call < warning (the tone of the highest one plays).
/// The server's `level` and `cue` decide; the key prefix is never looked at.
public enum NotifyLevel: Int, Comparable, Sendable {
    case call = 1, warning = 2

    public init?(_ alert: SupervisorAlert) {
        if alert.level == .warning { self = .warning } else if alert.cue == .call { self = .call } else { return nil }
    }

    public static func < (a: NotifyLevel, b: NotifyLevel) -> Bool { a.rawValue < b.rawValue }

    public var label: String { self == .warning ? "WARNING" : "CALL" }
}

/// Quiet hours in local time, minutes since midnight. A window that crosses midnight is fine;
/// `from == to` is empty. Same rule as the web UI's `inQuiet`.
public struct QuietHours: Equatable, Sendable {
    public static let defaultFrom = "22:00"
    public static let defaultTo = "08:00"

    public var on: Bool
    public var from: Int
    public var to: Int

    public init(on: Bool, from: Int, to: Int) {
        self.on = on
        self.from = from
        self.to = to
    }

    /// Text fields "HH:MM"; a bad one falls back to the default.
    public init(on: Bool, from: String, to: String) {
        self.init(
            on: on, from: Self.minutes(from) ?? Self.minutes(Self.defaultFrom)!,
            to: Self.minutes(to) ?? Self.minutes(Self.defaultTo)!)
    }

    /// "HH:MM" (also "H:MM") to minutes since midnight; nil when it isn't a time.
    public static func minutes(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              parts[1].count == 2, (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        return h * 60 + m
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard on, from != to else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return from < to ? (now >= from && now < to) : (now >= from || now < to)
    }
}

/// The app's own switches (Settings). atc does not expose its alert settings (they live in
/// each browser's localStorage), so quiet hours are a Settings field here.
public struct NotifyPrefs: Equatable, Sendable {
    public var notifications = true
    public var sound = true
    /// Off by default, like the browser.
    public var voice = false
    public var quiet = QuietHours(on: false, from: QuietHours.defaultFrom, to: QuietHours.defaultTo)

    public init() {}
}

/// One notification to post. `id` is the alert key, so a repeat replaces the earlier banner.
public struct AlertNotification: Equatable, Sendable {
    public var id: String
    public var level: NotifyLevel
    /// "WARNING · AIRCRAFT TEAM_K · FLIGHT ATC-157"; the place parts are left out when the server names none.
    public var title: String
    /// The server's lamp text, then its next step on a second line.
    public var body: String
    public var url: URL?

    public init(_ a: SupervisorAlert, level: NotifyLevel, base: URL) {
        id = a.key
        self.level = level
        let place = [a.aircraft.map { "AIRCRAFT \($0)" }, a.flight.map { "FLIGHT \($0)" }].compactMap { $0 }
        title = ([level.label] + place).joined(separator: " · ")
        if let next = a.next, !next.isEmpty { body = a.text + "\n" + next } else { body = a.text }
        url = ATCLink.url(base: base, link: a.link)
    }
}

/// What to do about one alert list update.
public struct NotifyPlan: Equatable, Sendable {
    public var notifications: [AlertNotification] = []
    /// The tone to play, for the highest level among the new keys; nil when silent.
    public var tone: NotifyLevel?
    /// The key whose voice WAV to play after the tone: the first new key at the highest level. Nil when voice is off or quiet.
    public var voiceKey: String?

    /// Public so the app target can build one (the Settings test alert); a memberwise init is internal.
    public init(notifications: [AlertNotification] = [], tone: NotifyLevel? = nil, voiceKey: String? = nil) {
        self.notifications = notifications
        self.tone = tone
        self.voiceKey = voiceKey
    }

    public var isEmpty: Bool { notifications.isEmpty && tone == nil && voiceKey == nil }
}

/// Feeds the full alert list in, gets a plan out.
/// - Nothing on the first list. After that a key notifies once, when it first shows up in the list.
///   The comparison is with the last list seen (kept across reconnects, sleep and wake), never with an empty one,
///   so keys raised while away notify once and keys raised and cleared while away never do.
/// - A burst (several new keys in one update) gets one tone and one voice: the highest level, first in server order.
/// - Quiet hours silence tone and voice. Banners still post, since they make no sound.
public struct AlertNotifier: Sendable {
    private var seen = SeenKeys()

    public init() {}

    public mutating func update(
        items: [SupervisorAlert], base: URL, prefs: NotifyPrefs, now: Date, calendar: Calendar = .current
    ) -> NotifyPlan {
        let fresh = Set(seen.update(items: items))
        var plan = NotifyPlan()
        var top: (level: NotifyLevel, key: String)?
        for a in items where fresh.contains(a.key) {
            guard let level = NotifyLevel(a) else { continue }
            plan.notifications.append(AlertNotification(a, level: level, base: base))
            if top == nil || level > top!.level { top = (level, a.key) }
        }
        guard let top else { return plan }
        if !prefs.notifications { plan.notifications = [] }
        if prefs.quiet.contains(now, calendar: calendar) { return plan }
        if prefs.sound { plan.tone = top.level }
        if prefs.voice { plan.voiceKey = top.key }
        return plan
    }
}

public enum VoiceURL {
    /// `GET /api/voice/alert/<key>.wav`. Keys hold `|`, `/` and `?`, so everything but unreserved characters is escaped.
    public static func url(base: URL, key: String) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: root + "/api/voice/alert/" + escaped + ".wav")
    }
}

/// The alert tone, generated as a 16-bit mono WAV so the app bundles no sound file.
/// WARNING: three short beeps at 880 Hz. CALL: a low then a high beep.
public enum AlertTone {
    public static let sampleRate = 22_050

    /// (frequency in Hz, seconds); frequency 0 is a gap.
    static func notes(_ level: NotifyLevel) -> [(Double, Double)] {
        switch level {
        case .warning: return [(880, 0.14), (0, 0.07), (880, 0.14), (0, 0.07), (880, 0.14)]
        case .call: return [(660, 0.12), (0, 0.05), (880, 0.18)]
        }
    }

    public static func wav(for level: NotifyLevel) -> Data {
        var samples: [Int16] = []
        for (freq, seconds) in notes(level) {
            let n = Int(seconds * Double(sampleRate))
            let fade = Int(0.006 * Double(sampleRate))
            for i in 0..<n {
                guard freq > 0 else { samples.append(0); continue }
                let edge = min(1, Double(min(i, n - 1 - i)) / Double(fade))
                let v = sin(2 * Double.pi * freq * Double(i) / Double(sampleRate)) * 0.4 * edge
                samples.append(Int16(v * Double(Int16.max)))
            }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: s)) }
        return d
    }
}
