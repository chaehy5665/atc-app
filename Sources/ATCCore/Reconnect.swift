// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Source of jitter, injected so tests are deterministic.
public protocol RandomSource {
    /// A value in 0..<1.
    mutating func nextUnit() -> Double
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public mutating func nextUnit() -> Double { Double.random(in: 0..<1) }
}

/// Reconnect delays: 1 s, doubling, capped at 30 s, then +-20 % jitter.
/// Jitter is applied after the cap, so at the cap a delay is 24...36 s.
public struct Backoff<R: RandomSource> {
    public static var base: TimeInterval { 1 }
    public static var cap: TimeInterval { 30 }
    public static var jitter: Double { 0.2 }

    private var attempt = 0
    private var random: R

    public init(random: R) { self.random = random }

    /// The delay before the next attempt.
    public mutating func nextDelay() -> TimeInterval {
        let raw = min(Self.base * pow(2, Double(attempt)), Self.cap)
        if raw < Self.cap { attempt += 1 }
        let factor = 1 + (random.nextUnit() * 2 - 1) * Self.jitter
        return raw * factor
    }

    /// Call after a connection has produced an event.
    public mutating func reset() { attempt = 0 }
}

extension Backoff where R == SystemRandomSource {
    public init() { self.init(random: SystemRandomSource()) }
}

/// A connection is dead after 60 s without any event (`ping` included).
public struct Watchdog: Equatable, Sendable {
    public static let timeout: TimeInterval = 60

    public private(set) var lastEvent: Date

    /// Start it when the connection opens.
    public init(startedAt: Date) { lastEvent = startedAt }

    public mutating func sawEvent(at date: Date) { lastEvent = date }

    public func isDead(at now: Date) -> Bool {
        now.timeIntervalSince(lastEvent) >= Self.timeout
    }
}
