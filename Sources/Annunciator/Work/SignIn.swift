// SPDX-License-Identifier: Apache-2.0
import AppKit
import ATCCore
import AuthenticationServices
import Foundation

/// GitHub and Linear sign-in state for Settings (ATC-246, GL0). No data is fetched: this only obtains tokens,
/// stores them in the Keychain and deletes them. All rules (request shapes, state check, Redact) are in ATCCore.
/// Nothing here logs; every error text shown goes through `Redact`.
@MainActor
final class SignInModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let githubClientKey = "signin.github.clientID"
    static let linearClientKey = "signin.linear.clientID"

    enum Phase: Equatable {
        case signedOut
        case working
        /// GitHub device flow: the code to type at `url`.
        case waitingForCode(userCode: String, url: URL)
        case signedIn
    }

    @Published private(set) var githubPhase: Phase = .signedOut
    @Published private(set) var linearPhase: Phase = .signedOut
    @Published private(set) var githubMessage = ""
    /// The scope the token has, read once after sign-in (empty when not read this run).
    @Published private(set) var githubScopeNote = ""
    @Published private(set) var linearMessage = ""

    private let store: SecretStore
    private let session: URLSession
    private var githubTask: Task<Void, Never>?
    private var linearTask: Task<Void, Never>?
    private var webSession: ASWebAuthenticationSession?
    /// The one pending Linear sign-in; nil when none. Cleared as soon as a callback is judged.
    private var pending: PendingAuth?

    init(store: SecretStore = KeychainStore()) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: config)
        super.init()
        refresh()
    }

    var githubClientID: String { UserDefaults.standard.string(forKey: Self.githubClientKey) ?? "" }
    var linearClientID: String { UserDefaults.standard.string(forKey: Self.linearClientKey) ?? "" }

    /// Re-reads which items exist (no secret is read).
    func refresh() {
        if githubPhase == .signedOut || githubPhase == .signedIn {
            githubPhase = store.isSignedIn(.github) ? .signedIn : .signedOut
        }
        if linearPhase == .signedOut || linearPhase == .signedIn {
            linearPhase = store.isSignedIn(.linear) ? .signedIn : .signedOut
        }
    }

    // MARK: GitHub (device flow)

    /// Saves the client ID (not a secret) when it has the right shape; empty clears it.
    @discardableResult
    func setGitHubClientID(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { UserDefaults.standard.removeObject(forKey: Self.githubClientKey); return true }
        guard let ok = GitHubAuth.validClientID(t) else { return false }
        UserDefaults.standard.set(ok, forKey: Self.githubClientKey)
        return true
    }

    func signInGitHub() {
        guard githubPhase == .signedOut, let clientID = GitHubAuth.validClientID(githubClientID) else {
            githubMessage = "GitHub client ID를 먼저 넣고 Apply를 누르세요."
            return
        }
        githubMessage = ""
        githubPhase = .working
        githubTask = Task { await runDeviceFlow(clientID: clientID) }
    }

    func cancelGitHub() {
        githubTask?.cancel()
        githubTask = nil
        githubPhase = .signedOut
        githubMessage = ""
    }

    private func runDeviceFlow(clientID: String) async {
        do {
            let (data, _) = try await send(DeviceFlow.deviceCodeRequest(clientID: clientID))
            let code = try DeviceFlow.parseDeviceCode(data)
            githubPhase = .waitingForCode(userCode: code.userCode, url: code.verificationURL)
            var interval = code.interval
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while Date() < deadline {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                try Task.checkCancellation()
                let (body, _) = try await send(DeviceFlow.pollRequest(clientID: clientID, deviceCode: code.deviceCode))
                switch DeviceFlow.parsePoll(body, currentInterval: interval) {
                case .pending: continue
                case .slowDown(let next): interval = next
                case .done(let tokens):
                    try save(tokens, service: .github)
                    githubPhase = .signedIn
                    githubMessage = "로그인됨. 이 토큰은 만료되지 않으니, 필요 없으면 GitHub에서 해지하세요."
                    await checkGitHubScopes(token: tokens.accessToken)
                    return
                case .failed(let error):
                    fail(.github, Self.describe(error))
                    return
                }
            }
            fail(.github, "코드가 만료됐습니다. 다시 시작하세요.")
        } catch is CancellationError {
            // cancelled by the user or by sign-out: the caller already set the phase
        } catch let error as DeviceFlowError {
            fail(.github, Self.describe(error))
        } catch {
            fail(.github, "연결 실패: " + Redact.error(error))
        }
    }

    private static func describe(_ e: DeviceFlowError) -> String {
        switch e {
        case .malformed: return "GitHub 응답을 읽지 못했습니다."
        case .expired: return "코드가 만료됐습니다. 다시 시작하세요."
        case .denied: return "GitHub에서 거부했습니다."
        case .flowDisabled: return "GitHub OAuth App 설정에서 Device Flow가 꺼져 있습니다."
        case .other(let s): return "GitHub 오류: " + Redact.text(s)
        }
    }

    /// Opens the verification page (https on github.com only; `DeviceFlow.parseDeviceCode` already enforced it).
    func openVerification(_ url: URL) {
        guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return }
        NSWorkspace.shared.open(url)
    }

    /// One GET /user right after sign-in, only to read `X-OAuth-Scopes`. Nothing from the response is logged.
    private func checkGitHubScopes(token: String) async {
        guard let (_, response) = try? await session.data(for: GitHubRequests.currentUser.urlRequest(token: token, etag: nil)),
              let http = response as? HTTPURLResponse else { return }
        githubScopeNote = Self.describe(GitHubAuth.checkScopes(headers: GitHubParse.lowercased(http.allHeaderFields)))
    }

    private static func describe(_ c: GitHubAuth.ScopeCheck) -> String {
        switch c {
        case .exact: return "scope: \(GitHubAuth.scope)"
        case .different(let names): return "scope가 다릅니다: " + (names.isEmpty ? "(없음)" : names.joined(separator: ", ")) + " (필요: \(GitHubAuth.scope))"
        case .unknown: return "scope를 확인하지 못했습니다."
        }
    }

    func openGitHubRevokePage() { NSWorkspace.shared.open(GitHubAuth.revokeHelpURL) }

    // MARK: Linear (PKCE in ASWebAuthenticationSession)

    @discardableResult
    func setLinearClientID(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { UserDefaults.standard.removeObject(forKey: Self.linearClientKey); return true }
        guard let ok = LinearAuth.validClientID(t) else { return false }
        UserDefaults.standard.set(ok, forKey: Self.linearClientKey)
        return true
    }

    func signInLinear() {
        guard linearPhase == .signedOut, let clientID = LinearAuth.validClientID(linearClientID) else {
            linearMessage = "Linear client ID를 먼저 넣고 Apply를 누르세요."
            return
        }
        let auth = PendingAuth(state: Pkce.makeState(), verifier: Pkce.makeVerifier())
        guard let url = LinearAuth.authorizeRequestURL(clientID: clientID, challenge: Pkce.challenge(for: auth.verifier), state: auth.state) else {
            linearMessage = "인증 주소를 만들지 못했습니다."
            return
        }
        linearMessage = ""
        linearPhase = .working
        pending = auth
        let web = ASWebAuthenticationSession(url: url, callbackURLScheme: LinearAuth.callbackScheme) { [weak self] callback, error in
            Task { @MainActor in self?.linearCallback(callback, error: error, clientID: clientID) }
        }
        web.presentationContextProvider = self
        // Ephemeral: no Linear web login is shared with or left in the browser (PILOT'S DISCRETION, see the PR).
        web.prefersEphemeralWebBrowserSession = true
        webSession = web
        if !web.start() {
            pending = nil
            webSession = nil
            fail(.linear, "인증 창을 열지 못했습니다.")
        }
    }

    func cancelLinear() {
        webSession?.cancel()
        webSession = nil
        linearTask?.cancel()
        linearTask = nil
        pending = nil
        linearPhase = .signedOut
        linearMessage = ""
    }

    private func linearCallback(_ url: URL?, error: Error?, clientID: String) {
        webSession = nil
        guard let auth = pending else { return }  // no pending sign-in: nothing is accepted
        pending = nil  // one try per state
        if let error {
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            if cancelled { linearPhase = .signedOut; linearMessage = ""; return }
            fail(.linear, "인증 실패: " + Redact.error(error))
            return
        }
        guard let url else { fail(.linear, "콜백이 비어 있습니다."); return }
        switch auth.evaluate(url) {
        case .ignored:
            fail(.linear, "콜백을 받아들이지 않았습니다(state 불일치).")
        case .error(let e):
            fail(.linear, "Linear 오류: " + Redact.text(e))
        case .code(let code):
            linearTask = Task { await exchange(code: code, verifier: auth.verifier, clientID: clientID) }
        }
    }

    private func exchange(code: String, verifier: String, clientID: String) async {
        do {
            let (data, status) = try await send(LinearAuth.tokenRequest(clientID: clientID, code: code, verifier: verifier))
            guard status == 200, let tokens = LinearAuth.parseToken(data) else {
                fail(.linear, "토큰을 받지 못했습니다(HTTP \(status)).")
                return
            }
            try save(tokens, service: .linear)
            linearPhase = .signedIn
            linearMessage = "로그인됨."
        } catch is CancellationError {
        } catch {
            fail(.linear, "연결 실패: " + Redact.error(error, extra: [code, verifier]))
        }
    }

    // MARK: Sign out

    /// Deletes the items first (no network needed), stops any flow, then tells Linear to revoke what it held.
    /// GitHub cannot be revoked from the app (it needs a client secret): Settings links to the page for that.
    func signOut(_ service: SecretKey.Service) {
        switch service {
        case .github: githubTask?.cancel(); githubTask = nil; githubScopeNote = ""
        case .linear: cancelLinearWork()
        }
        let held = service == .linear ? readLinearTokens() : []
        do {
            try store.deleteAll(service)
            message(service, service == .github ? "로그아웃: 앱의 토큰을 지웠습니다. GitHub의 승인은 아래 링크에서 해지하세요." : "로그아웃: 앱의 토큰을 지우고 Linear에 해지를 요청했습니다.")
        } catch {
            message(service, "Keychain 삭제 실패: " + Redact.error(error))
        }
        setPhase(service, store.isSignedIn(service) ? .signedIn : .signedOut)
        for (token, kind) in held {
            Task { _ = try? await send(LinearAuth.revokeRequest(token: token, kind: kind)) }
        }
    }

    private func cancelLinearWork() {
        webSession?.cancel()
        webSession = nil
        linearTask?.cancel()
        linearTask = nil
        pending = nil
    }

    private func readLinearTokens() -> [(String, SecretKey.Kind)] {
        [SecretKey.Kind.access, .refresh].compactMap { kind in
            guard let t = (try? store.read(SecretKey(.linear, kind))) ?? nil else { return nil }
            return (t, kind)
        }
    }

    // MARK: Helpers

    private func save(_ tokens: TokenSet, service: SecretKey.Service) throws {
        try TokenPolicy.save(tokens, service: service, in: store, now: Date())
    }

    private func fail(_ service: SecretKey.Service, _ text: String) {
        setPhase(service, .signedOut)
        message(service, text)
    }

    private func setPhase(_ service: SecretKey.Service, _ phase: Phase) {
        if service == .github { githubPhase = phase } else { linearPhase = phase }
    }

    private func message(_ service: SecretKey.Service, _ text: String) {
        if service == .github { githubMessage = text } else { linearMessage = text }
    }

    /// The app's only sign-in network call. It never logs; errors are redacted by the callers.
    private func send(_ request: FormRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request.urlRequest)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}
