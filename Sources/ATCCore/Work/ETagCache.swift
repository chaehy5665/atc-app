// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): ETag and body of the last 200, keyed by URL. Memory only, never written to disk
// (design 11.5); sign-out empties it.

public struct ETagCache: Sendable {
    public struct Entry: Equatable, Sendable {
        public let etag: String
        public let body: Data
        public let link: String?
    }

    public static let maxEntries = 300

    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    public init() {}

    public var count: Int { entries.count }

    public func entry(for url: URL) -> Entry? { entries[url.absoluteString] }

    public mutating func store(_ entry: Entry, for url: URL) {
        let key = url.absoluteString
        if entries[key] == nil { order.append(key) }
        entries[key] = entry
        while order.count > Self.maxEntries {
            entries[order.removeFirst()] = nil
        }
    }

    public mutating func removeAll() {
        entries = [:]
        order = []
    }
}
