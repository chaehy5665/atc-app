// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Strips tokens and credentials from any string that may be logged or shown (ATC-246, design 11.7).
/// Every error and log path in the sign-in code goes through `Redact.text`.
public enum Redact {
    public static let mask = "[redacted]"

    /// Known token prefixes: GitHub (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`) and Linear (`lin_api_`, `lin_oauth_`, `lin_`).
    private static let tokenPatterns: [String] = [
        #"github_pat_[A-Za-z0-9_]{8,}"#,
        #"gh[pousr]_[A-Za-z0-9]{8,}"#,
        #"lin_[A-Za-z0-9_]{8,}"#,
    ]

    /// `Authorization: Bearer x` (any scheme word), then a bare `Bearer x` / `Basic x`. Group 1 is kept.
    private static let authPatterns: [String] = [
        #"(?i)(authorization\s*[:=]\s*)(?:(?:bearer|basic|token)\s+)?[^\s,;"']+"#,
        #"(?i)(\b(?:bearer|basic)\s+)[A-Za-z0-9._~+/=-]{6,}"#,
    ]

    /// `access_token=…`, `"refresh_token": "…"`, `code=…`, `device_code=…`, `code_verifier=…`, `state=…`. Group 1 is kept.
    private static let sensitiveKeys = "access_token|refresh_token|id_token|token|device_code|user_code|code|code_verifier|client_secret|state|password"
    private static let keyValuePatterns: [String] = [
        "(?i)(\"?(?:\(sensitiveKeys))\"?\\s*[:=]\\s*\"?)[^\\s&\",;}]+",
    ]

    /// Redacts tokens, Authorization values and sensitive key/value pairs. Also masks any `extra` literal
    /// (a token the caller holds) wherever it appears, in case it has no recognisable shape.
    public static func text(_ s: String, extra: [String] = []) -> String {
        var out = s
        for literal in extra where literal.count >= 4 {
            out = out.replacingOccurrences(of: literal, with: mask)
        }
        for p in authPatterns + keyValuePatterns { out = replace(out, p, keepGroup: true) }
        for p in tokenPatterns { out = replace(out, p, keepGroup: false) }
        return out
    }

    /// A URL for logging: scheme, host, path. No query, fragment or user info.
    public static func url(_ u: URL) -> String {
        guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return mask }
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        return c.string ?? mask
    }

    /// A string for any error: the description, redacted.
    public static func error(_ e: Error, extra: [String] = []) -> String {
        text(String(describing: e), extra: extra)
    }

    private static func replace(_ s: String, _ pattern: String, keepGroup: Bool) -> String {
        // A pattern that fails to compile must not leak: mask everything.
        guard let re = try? NSRegularExpression(pattern: pattern) else { return mask }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: keepGroup ? "$1" + mask : mask)
    }
}
