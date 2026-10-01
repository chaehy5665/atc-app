// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// ATC-246: Linear OAuth 2 with PKCE (no client secret), as pure rules.
// The app target runs ASWebAuthenticationSession and the token POST.

public enum LinearAuth {
    public static let authorizeURL = URL(string: "https://linear.app/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.linear.app/oauth/token")!
    public static let revokeURL = URL(string: "https://api.linear.app/oauth/revoke")!
    /// Custom scheme for the redirect. The bundle ID is `dev.atc.annunciator`; no real names.
    public static let callbackScheme = "dev.atc.annunciator"
    public static let callbackHost = "linear-callback"
    public static let redirectURI = "dev.atc.annunciator://linear-callback"
    /// GL0 and GL1 only read.
    public static let scope = "read"

    public static func validClientID(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...64).contains(t.utf8.count), t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return t
    }

    public static func authorizeRequestURL(clientID: String, challenge: String, state: String) -> URL? {
        var c = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        c?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return c?.url
    }

    public static func tokenRequest(clientID: String, code: String, verifier: String) -> FormRequest {
        .form(tokenURL, [("client_id", clientID), ("grant_type", "authorization_code"), ("code", code),
                         ("redirect_uri", redirectURI), ("code_verifier", verifier)])
    }

    public static func refreshRequest(clientID: String, refreshToken: String) -> FormRequest {
        .form(tokenURL, [("client_id", clientID), ("grant_type", "refresh_token"), ("refresh_token", refreshToken)])
    }

    public static func revokeRequest(token: String, kind: SecretKey.Kind) -> FormRequest {
        .form(revokeURL, [("token", token), ("token_type_hint", kind == .access ? "access_token" : "refresh_token")])
    }

    public static func parseToken(_ data: Data) -> TokenSet? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["error"] == nil,
              let access = o["access_token"] as? String, !access.isEmpty
        else { return nil }
        let refresh = (o["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TokenSet(accessToken: access, refreshToken: refresh, expiresIn: o["expires_in"] as? Int)
    }
}

/// What a redirect carried, judged against the one pending sign-in.
public enum CallbackResult: Equatable, Sendable {
    case code(String)
    /// The user denied or Linear reported an error (a short `error` value only).
    case error(String)
    /// Not ours: wrong scheme or host, a missing or different state, or neither `code` nor `error`. Ignore it.
    case ignored
}

/// One pending Linear sign-in: the state and verifier live only in memory and only until a callback uses them.
public struct PendingAuth: Equatable, Sendable {
    public let state: String
    public let verifier: String

    public init(state: String, verifier: String) {
        self.state = state
        self.verifier = verifier
    }

    /// Accepts only a `code` whose single `state` equals this pending state. An `error` needs the matching state
    /// too, so a forged callback cannot cancel a sign-in either.
    public func evaluate(_ url: URL) -> CallbackResult {
        guard url.scheme?.lowercased() == LinearAuth.callbackScheme, url.host?.lowercased() == LinearAuth.callbackHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return .ignored }
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }
        let states = values("state")
        guard states.count == 1, Self.constantTimeEqual(states[0], state) else { return .ignored }
        if let e = values("error").first { return .error(String(e.prefix(64))) }
        let codes = values("code")
        guard codes.count == 1, !codes[0].isEmpty, codes[0].utf8.count <= 2048 else { return .ignored }
        return .code(codes[0])
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
