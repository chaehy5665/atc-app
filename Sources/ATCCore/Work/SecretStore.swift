// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// ATC-246 (GL0): where a token rests. The app's Keychain implementation lives in the app target;
// this protocol and an in-memory fake keep the rules testable on Linux.

/// One secret slot: a service (GitHub or Linear) and a kind (access or refresh token).
public struct SecretKey: Hashable, Sendable {
    public enum Service: String, Sendable, CaseIterable {
        case github = "dev.atc.annunciator.github"
        case linear = "dev.atc.annunciator.linear"
    }
    public enum Kind: String, Sendable, CaseIterable {
        case access
        case refresh
    }

    public let service: Service
    public let kind: Kind

    public init(_ service: Service, _ kind: Kind) {
        self.service = service
        self.kind = kind
    }

    /// Keychain `kSecAttrService`.
    public var serviceName: String { service.rawValue }
    /// Keychain `kSecAttrAccount`.
    public var account: String { kind.rawValue }
}

public enum SecretStoreError: Error, Equatable, Sendable {
    /// The underlying store failed; carries a status code only, never a secret.
    case failed(Int)
}

public protocol SecretStore: AnyObject {
    func read(_ key: SecretKey) throws -> String?
    func write(_ value: String, for key: SecretKey) throws
    /// Deleting a missing item is not an error.
    func delete(_ key: SecretKey) throws
    /// Whether an item exists. A real store should answer without reading the secret, so no password prompt appears.
    func exists(_ key: SecretKey) -> Bool
}

extension SecretStore {
    public func exists(_ key: SecretKey) -> Bool { ((try? read(key)) ?? nil) != nil }

    /// Sign-out: both items of a service. Tries both even if the first fails, then rethrows the first error.
    public func deleteAll(_ service: SecretKey.Service) throws {
        var first: Error?
        for kind in SecretKey.Kind.allCases {
            do { try delete(SecretKey(service, kind)) } catch { first = first ?? error }
        }
        if let first { throw first }
    }

    public func isSignedIn(_ service: SecretKey.Service) -> Bool {
        exists(SecretKey(service, .access))
    }
}

/// Test double; also what previews and Linux tests use.
public final class InMemorySecretStore: SecretStore {
    private var items: [SecretKey: String] = [:]
    public init() {}
    public func read(_ key: SecretKey) throws -> String? { items[key] }
    public func write(_ value: String, for key: SecretKey) throws { items[key] = value }
    public func delete(_ key: SecretKey) throws { items[key] = nil }
    public var count: Int { items.count }
}
