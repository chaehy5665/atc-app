// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ATC-246: GitHub App device flow, as pure request building and response parsing.
// The app target does the URLSession calls and the sleeping. No client secret anywhere.

public enum GitHubAuth {
    public static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    public static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    public static let deviceGrant = "urn:ietf:params:oauth:grant-type:device_code"
    /// Where the SUPERVISOR revokes or uninstalls the App by hand (GitHub token revocation needs a client secret).
    public static let revokeHelpURL = URL(string: "https://github.com/settings/apps/authorizations")!

    /// A plain safe shape: ASCII letters, digits, `.`, `_`, `-`. Real client IDs are about 20 characters.
    public static func validClientID(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...64).contains(t.utf8.count),
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") })
        else { return nil }
        return t
    }
}

/// A POST with a form body and `Accept: application/json`.
public struct FormRequest: Equatable, Sendable {
    public let url: URL
    public let body: String

    public var urlRequest: URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = Data(body.utf8)
        r.timeoutInterval = 20
        return r
    }

    static func form(_ url: URL, _ pairs: [(String, String)]) -> FormRequest {
        FormRequest(url: url, body: pairs.map { "\(formEscape($0.0))=\(formEscape($0.1))" }.joined(separator: "&"))
    }

    static func formEscape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public struct DeviceCode: Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Int
    public let interval: Int
}

public struct TokenSet: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    /// Seconds from receipt; nil for a token that does not expire.
    public let expiresIn: Int?
}

public enum DeviceFlowError: Error, Equatable, Sendable {
    case malformed
    case expired
    case denied
    case flowDisabled
    case other(String)
}

public enum DeviceFlowPoll: Equatable, Sendable {
    case pending
    /// Wait this many seconds between polls from now on.
    case slowDown(interval: Int)
    case done(TokenSet)
    case failed(DeviceFlowError)
}

public enum DeviceFlow {
    /// The minimum poll interval in seconds, whatever the server says (GitHub's default is 5).
    public static let minInterval = 5

    public static func deviceCodeRequest(clientID: String) -> FormRequest {
        .form(GitHubAuth.deviceCodeURL, [("client_id", clientID)])
    }

    public static func pollRequest(clientID: String, deviceCode: String) -> FormRequest {
        .form(GitHubAuth.tokenURL, [("client_id", clientID), ("device_code", deviceCode), ("grant_type", GitHubAuth.deviceGrant)])
    }

    public static func refreshRequest(clientID: String, refreshToken: String) -> FormRequest {
        .form(GitHubAuth.tokenURL, [("client_id", clientID), ("grant_type", "refresh_token"), ("refresh_token", refreshToken)])
    }

    /// The device code response. The verification URL must be https on github.com: the app opens it.
    public static func parseDeviceCode(_ data: Data) throws -> DeviceCode {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DeviceFlowError.malformed }
        if let e = o["error"] as? String { throw e == "device_flow_disabled" ? DeviceFlowError.flowDisabled : DeviceFlowError.other(e) }
        guard let device = o["device_code"] as? String, !device.isEmpty,
              let user = o["user_code"] as? String, !user.isEmpty,
              let uri = o["verification_uri"] as? String, let url = URL(string: uri),
              url.scheme == "https", url.host?.lowercased() == "github.com"
        else { throw DeviceFlowError.malformed }
        let expires = (o["expires_in"] as? Int) ?? 900
        let interval = max((o["interval"] as? Int) ?? minInterval, minInterval)
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: url, expiresIn: expires, interval: interval)
    }

    /// One poll response. GitHub answers 200 with an `error` field while pending, so the status code is not needed.
    public static func parsePoll(_ data: Data, currentInterval: Int) -> DeviceFlowPoll {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed(.malformed) }
        if let e = o["error"] as? String {
            switch e {
            case "authorization_pending": return .pending
            case "slow_down":
                let next = (o["interval"] as? Int) ?? currentInterval + 5
                return .slowDown(interval: max(next, currentInterval + 5))
            case "expired_token": return .failed(.expired)
            case "access_denied": return .failed(.denied)
            case "device_flow_disabled": return .failed(.flowDisabled)
            default: return .failed(.other(e))
            }
        }
        guard let token = parseToken(o) else { return .failed(.malformed) }
        return .done(token)
    }

    /// A refresh response: a new token set, or nil on any failure (the caller then asks for a new sign-in).
    public static func parseRefresh(_ data: Data) -> TokenSet? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["error"] == nil else { return nil }
        return parseToken(o)
    }

    private static func parseToken(_ o: [String: Any]) -> TokenSet? {
        guard let access = o["access_token"] as? String, !access.isEmpty else { return nil }
        let refresh = (o["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return TokenSet(accessToken: access, refreshToken: refresh, expiresIn: o["expires_in"] as? Int)
    }
}
