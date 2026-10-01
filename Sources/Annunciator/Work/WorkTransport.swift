// SPDX-License-Identifier: Apache-2.0
import ATCCore
import Foundation

/// The app's only GitHub network code for data (ATC-247): a URLSession that sends the GETs `GitHubClient` builds.
/// No cache and no cookies: the ETag cache is `ETagCache`, in memory, and `If-None-Match` is set by ATCCore.
/// Nothing here logs; error texts are redacted by the caller.
final class WorkTransport: GitHubTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> GitHubResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return GitHubResponse(status: http.statusCode, headers: GitHubParse.lowercased(http.allHeaderFields), body: data)
    }
}

/// Gives `GitHubClient` the access token. An OAuth App token (ATC-303) has no expiry and no refresh token, so it is
/// returned as is and a 401 ends in `.failed` (sign in again) with no network call. A token that does carry an expiry
/// and a refresh token is still refreshed before it dies and after a 401, with the client ID only, no secret (design 11.5). It is an actor because GitHub refresh tokens are single use: two refreshes at once would
/// lose one. Tokens are read from the Keychain once and held in memory until `invalidate()`.
actor GitHubTokenBroker: GitHubTokenSource {
    private let store: SecretStore
    private let session: URLSession
    private let clientID: @Sendable () -> String
    private var cached: (access: String, expiry: Date?)?

    init(store: SecretStore, clientID: @escaping @Sendable () -> String) {
        self.store = store
        self.clientID = clientID
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    /// Sign-in changed: read the Keychain again next time.
    func invalidate() { cached = nil }

    func accessToken(forceRefresh: Bool) async -> GitHubToken {
        if cached == nil {
            guard let access = (try? store.read(SecretKey(.github, .access))) ?? nil else { return .signedOut }
            cached = (access, TokenPolicy.decode((try? store.read(SecretKey(.github, .expiry))) ?? nil))
        }
        guard let current = cached else { return .signedOut }
        let expired = current.expiry.map { $0 <= Date() } ?? false
        if !forceRefresh && !TokenPolicy.needsRefresh(expiry: current.expiry, now: Date()) { return .token(current.access) }
        switch await refresh(replacing: current.access) {
        case .token(let t): return .token(t)
        case .signedOut: return .signedOut
        case .failed:
            // Near the end but not dead, and the refresh did not work: the old token may still do this request.
            return (forceRefresh || expired) ? .failed : .token(current.access)
        }
    }

    private func refresh(replacing old: String) async -> GitHubToken {
        guard let id = GitHubAuth.validClientID(clientID()),
              let refreshToken = (try? store.read(SecretKey(.github, .refresh))) ?? nil
        else { return .failed }
        let request = DeviceFlow.refreshRequest(clientID: id, refreshToken: refreshToken)
        guard let (data, _) = try? await session.data(for: request.urlRequest), let tokens = DeviceFlow.parseRefresh(data) else {
            return .failed
        }
        // Signed out (or signed in again) while the request ran: keep nothing from it.
        guard ((try? store.read(SecretKey(.github, .access))) ?? nil) == old else {
            cached = nil
            return .signedOut
        }
        do {
            try TokenPolicy.save(tokens, service: .github, in: store, now: Date(), keepRefreshIfAbsent: true)
        } catch {
            return .failed
        }
        cached = (tokens.accessToken, TokenPolicy.expiry(expiresIn: tokens.expiresIn, now: Date()))
        return .token(tokens.accessToken)
    }
}
