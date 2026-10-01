// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

// ATC-246 (GL0). Tokens here are made-up shapes, not real credentials.

final class SecretStoreTests: XCTestCase {
    func testKeyNamesAreStable() {
        XCTAssertEqual(SecretKey(.github, .access).serviceName, "dev.atc.annunciator.github")
        XCTAssertEqual(SecretKey(.linear, .refresh).serviceName, "dev.atc.annunciator.linear")
        XCTAssertEqual(SecretKey(.github, .access).account, "access")
        XCTAssertEqual(SecretKey(.github, .refresh).account, "refresh")
    }

    func testWriteReadDeleteAndSignOut() throws {
        let store = InMemorySecretStore()
        XCTAssertFalse(store.isSignedIn(.github))
        try store.write("a", for: SecretKey(.github, .access))
        try store.write("r", for: SecretKey(.github, .refresh))
        try store.write("l", for: SecretKey(.linear, .access))
        XCTAssertTrue(store.isSignedIn(.github))
        try store.deleteAll(.github)
        XCTAssertFalse(store.isSignedIn(.github))
        XCTAssertNil(try store.read(SecretKey(.github, .refresh)))
        XCTAssertTrue(store.isSignedIn(.linear), "signing out of one service leaves the other")
        try store.deleteAll(.github)  // deleting nothing is fine
    }

    func testDeleteAllTriesBothItemsEvenIfOneFails() {
        final class Flaky: SecretStore {
            var deleted: [SecretKey] = []
            func read(_ key: SecretKey) throws -> String? { nil }
            func write(_ value: String, for key: SecretKey) throws {}
            func delete(_ key: SecretKey) throws {
                deleted.append(key)
                if key.kind == .access { throw SecretStoreError.failed(-1) }
            }
        }
        let s = Flaky()
        XCTAssertThrowsError(try s.deleteAll(.linear))
        XCTAssertEqual(s.deleted.count, SecretKey.Kind.allCases.count, "every item is tried, the expiry (ATC-247) included")
    }
}

final class RedactTests: XCTestCase {
    private let samples = [
        "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
        "gho_abcdefghijklmnop",
        "ghu_abcdefghijklmnop",
        "ghr_abcdefghijklmnop",
        "github_pat_11ABCDEFG0abcdefghij_klmnopqrstuvwxyz",
        "lin_api_abcdefghijklmnop",
        "lin_oauth_abcdefghijklmnop",
    ]

    func testTokenShapesAreMasked() {
        for t in samples {
            let out = Redact.text("failed with \(t) at host")
            XCTAssertFalse(out.contains(t), t)
            XCTAssertTrue(out.contains(Redact.mask))
        }
    }

    func testAuthorizationHeaderForms() {
        for line in ["Authorization: Bearer abcdef123456", "authorization=Bearer abcdef123456",
                     "Authorization: token abcdef123456", "Authorization: Basic YWJjOmRlZg==", "got Bearer abcdef123456.x-y"] {
            let out = Redact.text(line)
            XCTAssertFalse(out.contains("abcdef123456"), line)
            XCTAssertFalse(out.contains("YWJjOmRlZg"), line)
        }
    }

    func testKeyValueAndJSONForms() {
        let body = #"{"access_token":"s3cretvalue","refresh_token": "r3fresh", "device_code":"dc123456"}"#
        let out = Redact.text(body)
        for secret in ["s3cretvalue", "r3fresh", "dc123456"] { XCTAssertFalse(out.contains(secret), secret) }
        let q = Redact.text("callback?code=abc123&state=xyz789&code_verifier=ver1fier")
        for secret in ["abc123", "xyz789", "ver1fier"] { XCTAssertFalse(q.contains(secret), secret) }
        XCTAssertTrue(Redact.text("code=abc&x=1").contains("&x=1"), "other parameters survive")
    }

    func testExtraLiteralIsMaskedWhateverItsShape() {
        let out = Redact.text("oops weirdtokenvalue happened", extra: ["weirdtokenvalue"])
        XCTAssertEqual(out, "oops [redacted] happened")
        XCTAssertEqual(Redact.text("keep abc", extra: ["abc"]), "keep abc", "extras under 4 characters are ignored")
    }

    func testPlainTextIsUntouched() {
        XCTAssertEqual(Redact.text("GitHub 로그인 실패: timeout"), "GitHub 로그인 실패: timeout")
    }

    func testURLDropsQueryFragmentAndUserInfo() {
        let u = URL(string: "https://user:pw@api.linear.app/oauth/token?code=abc&state=x#frag")!
        XCTAssertEqual(Redact.url(u), "https://api.linear.app/oauth/token")
    }

    func testErrorDescriptionIsRedacted() {
        struct E: Error { let detail: String }
        let out = Redact.error(E(detail: "Authorization: Bearer abcdef123456"))
        XCTAssertFalse(out.contains("abcdef123456"))
    }
}

final class PkceTests: XCTestCase {
    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    func testSHA256Vectors() {
        XCTAssertEqual(hex(SHA256Digest.hash([])), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hex(SHA256Digest.hash(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex(SHA256Digest.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(hex(SHA256Digest.hash([UInt8](repeating: 0x61, count: 1000))),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }

    func testRFC7636AppendixBChallenge() {
        XCTAssertEqual(Pkce.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierShape() {
        for _ in 0..<50 {
            let v = Pkce.makeVerifier()
            XCTAssertEqual(v.count, Pkce.verifierLength)
            XCTAssertTrue(Pkce.isValidVerifier(v))
        }
        XCTAssertNotEqual(Pkce.makeVerifier(), Pkce.makeVerifier())
        XCTAssertFalse(Pkce.isValidVerifier("short"))
        XCTAssertFalse(Pkce.isValidVerifier(String(repeating: "a", count: 129)))
        XCTAssertFalse(Pkce.isValidVerifier(String(repeating: "a", count: 42) + "+"))
    }

    func testChallengeIsBase64urlWithoutPadding() {
        let c = Pkce.challenge(for: Pkce.makeVerifier())
        XCTAssertEqual(c.count, 43)
        XCTAssertFalse(c.contains("=") || c.contains("+") || c.contains("/"))
    }

    func testStateIsLongAndDistinct() {
        let a = Pkce.makeState(), b = Pkce.makeState()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
    }
}

final class DeviceFlowTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testRequestsCarryNoSecret() {
        let r = DeviceFlow.deviceCodeRequest(clientID: "Iv1.abc12345")
        XCTAssertEqual(r.url.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(r.body, "client_id=Iv1.abc12345&scope=repo")
        let p = DeviceFlow.pollRequest(clientID: "Iv1.abc12345", deviceCode: "dc")
        XCTAssertEqual(p.body, "client_id=Iv1.abc12345&device_code=dc&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code")
        let rr = DeviceFlow.refreshRequest(clientID: "Iv1.abc12345", refreshToken: "rt")
        XCTAssertFalse(rr.body.contains("client_secret"))
        XCTAssertEqual(p.urlRequest.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(p.urlRequest.httpMethod, "POST")
    }

    func testParseDeviceCode() throws {
        let d = try DeviceFlow.parseDeviceCode(data(#"{"device_code":"dc1","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#))
        XCTAssertEqual(d.userCode, "ABCD-1234")
        XCTAssertEqual(d.interval, 5)
        XCTAssertEqual(d.verificationURL.host, "github.com")
    }

    func testIntervalHasAFloor() throws {
        let d = try DeviceFlow.parseDeviceCode(data(#"{"device_code":"dc1","user_code":"U","verification_uri":"https://github.com/login/device","interval":1}"#))
        XCTAssertEqual(d.interval, DeviceFlow.minInterval)
    }

    func testVerificationURLMustBeGitHubHTTPS() {
        for uri in ["http://github.com/login/device", "https://evil.example/login/device", "javascript:alert(1)", "file:///etc/passwd"] {
            XCTAssertThrowsError(try DeviceFlow.parseDeviceCode(data(#"{"device_code":"d","user_code":"U","verification_uri":"\#(uri)"}"#)), uri)
        }
    }

    func testDeviceCodeErrors() {
        XCTAssertThrowsError(try DeviceFlow.parseDeviceCode(data(#"{"error":"device_flow_disabled"}"#))) {
            XCTAssertEqual($0 as? DeviceFlowError, .flowDisabled)
        }
        XCTAssertThrowsError(try DeviceFlow.parseDeviceCode(data("not json"))) {
            XCTAssertEqual($0 as? DeviceFlowError, .malformed)
        }
    }

    func testPollStates() {
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"authorization_pending"}"#), currentInterval: 5), .pending)
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"slow_down","interval":10}"#), currentInterval: 5), .slowDown(interval: 10))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"slow_down"}"#), currentInterval: 5), .slowDown(interval: 10))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"slow_down","interval":2}"#), currentInterval: 5), .slowDown(interval: 10), "never faster than before")
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"expired_token"}"#), currentInterval: 5), .failed(.expired))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"access_denied"}"#), currentInterval: 5), .failed(.denied))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"device_flow_disabled"}"#), currentInterval: 5), .failed(.flowDisabled))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"error":"weird"}"#), currentInterval: 5), .failed(.other("weird")))
        XCTAssertEqual(DeviceFlow.parsePoll(data("<html>"), currentInterval: 5), .failed(.malformed))
        XCTAssertEqual(DeviceFlow.parsePoll(data(#"{"token_type":"bearer"}"#), currentInterval: 5), .failed(.malformed))
    }

    func testPollSuccess() {
        let t = DeviceFlow.parsePoll(data(#"{"access_token":"ghu_x","expires_in":28800,"refresh_token":"ghr_y","refresh_token_expires_in":15897600,"token_type":"bearer"}"#), currentInterval: 5)
        XCTAssertEqual(t, .done(TokenSet(accessToken: "ghu_x", refreshToken: "ghr_y", expiresIn: 28800)))
    }

    func testScopeIsRepoAndNothingElse() {
        XCTAssertEqual(GitHubAuth.scope, "repo")
        let body = DeviceFlow.deviceCodeRequest(clientID: "Iv1.abc12345").body
        XCTAssertTrue(body.hasSuffix("&scope=repo"))
        for wider in ["read%3Aorg", "workflow", "delete_repo", "user"] { XCTAssertFalse(body.contains(wider), wider) }
        XCTAssertFalse(DeviceFlow.pollRequest(clientID: "Iv1.abc12345", deviceCode: "dc").body.contains("scope"))
    }

    func testRevokeHelpPointsAtAuthorizedOAuthApps() {
        XCTAssertEqual(GitHubAuth.revokeHelpURL.absoluteString, "https://github.com/settings/applications")
    }

    func testOAuthAppTokenHasNoExpiryAndNoRefreshToken() {
        let t = DeviceFlow.parsePoll(data(#"{"access_token":"gho_x","token_type":"bearer","scope":"repo"}"#), currentInterval: 5)
        XCTAssertEqual(t, .done(TokenSet(accessToken: "gho_x", refreshToken: nil, expiresIn: nil)))
    }

    func testScopeHeaderCheck() {
        XCTAssertEqual(GitHubAuth.checkScopes(headers: ["x-oauth-scopes": "repo"]), .exact)
        XCTAssertEqual(GitHubAuth.checkScopes(headers: ["x-oauth-scopes": " repo "]), .exact)
        XCTAssertEqual(GitHubAuth.checkScopes(headers: ["x-oauth-scopes": "repo, workflow"]), .different(["repo", "workflow"]))
        XCTAssertEqual(GitHubAuth.checkScopes(headers: ["x-oauth-scopes": "public_repo"]), .different(["public_repo"]))
        XCTAssertEqual(GitHubAuth.checkScopes(headers: ["x-oauth-scopes": ""]), .different([]))
        XCTAssertEqual(GitHubAuth.checkScopes(headers: [:]), .unknown)
    }

    func testRefresh() {
        XCTAssertEqual(DeviceFlow.parseRefresh(data(#"{"access_token":"a","refresh_token":"b","expires_in":10}"#))?.refreshToken, "b")
        XCTAssertNil(DeviceFlow.parseRefresh(data(#"{"error":"bad_refresh_token"}"#)))
        XCTAssertNil(DeviceFlow.parseRefresh(data("")))
    }

    func testClientIDValidation() {
        XCTAssertEqual(GitHubAuth.validClientID(" Iv1.abcdef0123 "), "Iv1.abcdef0123")
        for bad in ["", "short", "has space inside", "a&b=cdefgh", String(repeating: "a", count: 65)] {
            XCTAssertNil(GitHubAuth.validClientID(bad), bad)
        }
    }
}

final class LinearAuthTests: XCTestCase {
    private let pending = PendingAuth(state: "state-123", verifier: "v")

    private func cb(_ query: String, base: String = "dev.atc.annunciator://linear-callback") -> URL { URL(string: base + query)! }

    func testAuthorizeURL() throws {
        let url = try XCTUnwrap(LinearAuth.authorizeRequestURL(clientID: "abc12345", challenge: "chal", state: "st"))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "linear.app")
        XCTAssertEqual(c.path, "/oauth/authorize")
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["scope"], "read")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["state"], "st")
        XCTAssertEqual(q["redirect_uri"], LinearAuth.redirectURI)
        XCTAssertNil(q["client_secret"])
    }

    func testTokenRequestHasVerifierAndNoSecret() {
        let r = LinearAuth.tokenRequest(clientID: "abc12345", code: "c o/de", verifier: "ver")
        XCTAssertTrue(r.body.contains("code_verifier=ver"))
        XCTAssertTrue(r.body.contains("code=c%20o%2Fde"))
        XCTAssertFalse(r.body.contains("client_secret"))
        XCTAssertEqual(r.url.host, "api.linear.app")
    }

    func testRevokeRequest() {
        let r = LinearAuth.revokeRequest(token: "t", kind: .refresh)
        XCTAssertEqual(r.url.absoluteString, "https://api.linear.app/oauth/revoke")
        XCTAssertEqual(r.body, "token=t&token_type_hint=refresh_token")
    }

    func testCallbackAcceptsCodeWithMatchingState() {
        XCTAssertEqual(pending.evaluate(cb("?code=abc&state=state-123")), .code("abc"))
    }

    func testCallbackIgnoresMismatchedOrMissingState() {
        XCTAssertEqual(pending.evaluate(cb("?code=abc&state=other")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=abc")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=abc&state=")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=abc&state=state-12")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=abc&state=state-1234")), .ignored)
    }

    func testCallbackIgnoresDuplicateOrEmptyParameters() {
        XCTAssertEqual(pending.evaluate(cb("?code=a&code=b&state=state-123")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=a&state=state-123&state=state-123")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=&state=state-123")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?state=state-123")), .ignored)
    }

    func testCallbackIgnoresOtherSchemeOrHost() {
        XCTAssertEqual(pending.evaluate(URL(string: "https://evil.example/linear-callback?code=a&state=state-123")!), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=a&state=state-123", base: "dev.atc.annunciator://other")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?code=a&state=state-123", base: "other.app://linear-callback")), .ignored)
    }

    func testErrorNeedsMatchingStateToo() {
        XCTAssertEqual(pending.evaluate(cb("?error=access_denied&state=state-123")), .error("access_denied"))
        XCTAssertEqual(pending.evaluate(cb("?error=access_denied&state=nope")), .ignored)
        XCTAssertEqual(pending.evaluate(cb("?error=access_denied")), .ignored)
    }

    func testParseToken() {
        let ok = LinearAuth.parseToken(Data(#"{"access_token":"a","token_type":"Bearer","expires_in":86399,"scope":"read","refresh_token":"r"}"#.utf8))
        XCTAssertEqual(ok, TokenSet(accessToken: "a", refreshToken: "r", expiresIn: 86399))
        XCTAssertNil(LinearAuth.parseToken(Data(#"{"error":"invalid_grant"}"#.utf8)))
        XCTAssertNil(LinearAuth.parseToken(Data()))
    }

    func testClientIDValidation() {
        XCTAssertNotNil(LinearAuth.validClientID("0123456789abcdef"))
        XCTAssertNil(LinearAuth.validClientID("bad id"))
        XCTAssertNil(LinearAuth.validClientID("a.b.c.d.e.f.g.h"))
    }
}
