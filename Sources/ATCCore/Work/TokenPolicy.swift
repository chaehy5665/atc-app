// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-247 (GL1a): when a token is refreshed. ATC-303: a GitHub OAuth App token has no expiry and no refresh token,
// so nothing is stored for them and no refresh goes out ahead of a request; a 401 means sign in again.

public enum TokenPolicy {
    /// Refresh this long before the stored expiry, so a request never goes out with a token about to die.
    public static let margin: TimeInterval = 300

    /// The expiry to store for a token set received at `now`; nil when the server gave no `expires_in`.
    public static func expiry(expiresIn: Int?, now: Date) -> Date? {
        expiresIn.map { now.addingTimeInterval(TimeInterval(max($0, 0))) }
    }

    /// The stored text form (ISO 8601). It is not a secret, but it rests next to the tokens so sign-out removes it.
    public static func encode(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func decode(_ text: String?) -> Date? {
        text.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Stores a received token set: access, refresh (and the expiry beside them). A refresh response that carries no
    /// new refresh token keeps the old one (`keepRefreshIfAbsent`); a first sign-in without one clears it.
    public static func save(_ tokens: TokenSet, service: SecretKey.Service, in store: SecretStore, now: Date, keepRefreshIfAbsent: Bool = false) throws {
        try store.write(tokens.accessToken, for: SecretKey(service, .access))
        if let refresh = tokens.refreshToken {
            try store.write(refresh, for: SecretKey(service, .refresh))
        } else if !keepRefreshIfAbsent {
            try store.delete(SecretKey(service, .refresh))
        }
        if let expiry = expiry(expiresIn: tokens.expiresIn, now: now) {
            try store.write(encode(expiry), for: SecretKey(service, .expiry))
        } else {
            try store.delete(SecretKey(service, .expiry))
        }
    }

    /// Refresh before the request when the expiry is known and near. An unknown expiry (a sign-in made before
    /// GL1a) is not refreshed ahead of time: the first 401 does it.
    public static func needsRefresh(expiry: Date?, now: Date) -> Bool {
        guard let expiry else { return false }
        return expiry.timeIntervalSince(now) <= margin
    }
}
