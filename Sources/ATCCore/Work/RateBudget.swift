// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): the app's own cap on GitHub requests, and the back-off when GitHub says slow down.
//
// Docs read 2026-10-01 (design 11.5): a GitHub App user token draws on the user's own 5,000 an hour, shared with
// every other app and token of that user, so the cap is 20 percent of it (atc's LOGBOOK keeps its room). A
// conditional request answered `304` with an Authorization header does not count against the primary limit,
// so a `304` costs nothing here either. The Mac check compares `x-ratelimit-remaining` around a `304` to confirm.

public struct RateBudget: Equatable, Sendable {
    public static let defaultCap = 1_000
    /// Settings can move the cap within this range.
    public static let capRange = 100...4_000
    public static let window: TimeInterval = 3_600
    public static let backoffBase: TimeInterval = 60
    public static let backoffCap: TimeInterval = 900
    public static let jitter = 0.2

    public enum Verdict: Equatable, Sendable {
        case allowed
        /// Back-off after a 403/429 is still running.
        case backingOff(until: Date)
        /// The hourly cap is spent; the oldest request leaves the window at `until`.
        case capReached(until: Date)
    }

    public private(set) var cap: Int
    /// Times of counted requests in the last hour.
    private var stamps: [Date] = []
    private var blockedUntil: Date?
    private var failures = 0

    public init(cap: Int = defaultCap) {
        self.cap = Self.clamp(cap)
    }

    public static func clamp(_ cap: Int) -> Int { min(max(cap, capRange.lowerBound), capRange.upperBound) }

    public mutating func setCap(_ value: Int) { cap = Self.clamp(value) }

    /// Requests counted in the hour up to `now`.
    public func used(at now: Date) -> Int {
        stamps.filter { now.timeIntervalSince($0) < Self.window }.count
    }

    public func verdict(at now: Date) -> Verdict {
        if let until = blockedUntil, until > now { return .backingOff(until: until) }
        let live = stamps.filter { now.timeIntervalSince($0) < Self.window }
        if live.count >= cap, let oldest = live.min() { return .capReached(until: oldest.addingTimeInterval(Self.window)) }
        return .allowed
    }

    /// One request went out. A `304` is free; everything else counts one, whatever its status.
    public mutating func record(at now: Date, notModified: Bool) {
        stamps.removeAll { now.timeIntervalSince($0) >= Self.window }
        if !notModified { stamps.append(now) }
        if blockedUntil.map({ $0 <= now }) ?? false { blockedUntil = nil }
    }

    /// A request that GitHub did not refuse: the back-off resets.
    public mutating func succeeded() {
        failures = 0
        blockedUntil = nil
    }

    /// GitHub refused with 403 or 429 for rate reasons. Returns when to try again.
    /// `retry-after` wins, then `x-ratelimit-reset` when nothing is left, else 60 s doubling to 15 minutes with jitter.
    /// `unit` is a random value in 0..<1 (injected so tests are exact).
    @discardableResult
    public mutating func limited(info: RateLimitInfo, at now: Date, unit: Double) -> Date {
        let delay: TimeInterval
        if let retry = info.retryAfter {
            delay = min(max(retry, 1), Self.window)
        } else if info.remaining == 0, let reset = info.reset, reset > now {
            delay = min(reset.timeIntervalSince(now) + 1, Self.window)
        } else {
            let raw = min(Self.backoffBase * pow(2, Double(failures)), Self.backoffCap)
            delay = raw * (1 + (unit * 2 - 1) * Self.jitter)
        }
        failures += 1
        let until = now.addingTimeInterval(delay)
        blockedUntil = max(blockedUntil ?? until, until)
        return blockedUntil!
    }
}
