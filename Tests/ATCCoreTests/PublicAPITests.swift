// SPDX-License-Identifier: Apache-2.0
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
// Plain import, as the app target sees ATCCore: an internal init used by the app fails to compile here, not only on the Mac.
import ATCCore

final class PublicAPITests: XCTestCase {
    // Mirrors AlertOutput.test(base:) in the app target.
    func testSettingsTestAlertBuildsFromPublicAPI() {
        let base = URL(string: "http://localhost:7700")!
        let alert = SupervisorAlert(key: "test|annunciator", group: "alert", level: .warning, text: "테스트 알림", next: "이 알림은 시험용입니다", link: nil)
        let plan = NotifyPlan(notifications: [AlertNotification(alert, level: .warning, base: base)], tone: .warning, voiceKey: nil)
        XCTAssertEqual(plan.notifications.count, 1)
        XCTAssertEqual(plan.tone, .warning)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(NotifyPlan().isEmpty)
    }

    // Mirrors WorkTransport, GitHubTokenBroker, WorkModel and the Work window in the app target (ATC-247).
    func testWorkTypesBuildFromPublicAPI() async throws {
        final class Net: GitHubTransport {
            func send(_ request: URLRequest) async throws -> GitHubResponse { GitHubResponse(status: 200, headers: GitHubParse.lowercased([:]), body: Data()) }
        }
        final class Tokens: GitHubTokenSource {
            func accessToken(forceRefresh: Bool) async -> GitHubToken { .signedOut }
        }
        let client = GitHubClient(transport: Net(), tokens: Tokens(), cap: RateBudget.clamp(RateBudget.defaultCap))
        client.setRepos(RepoRef.parseList("octo/repo-a").repos)
        client.setCap(500)
        let snapshot = await client.refresh()
        XCTAssertEqual(snapshot.status, .needsSignIn)
        XCTAssertEqual(client.budget.used(at: Date()), 0)
        client.reset()
        XCTAssertNil(WorkPanel.line(snapshot, signedIn: false, repos: 1, now: Date()))
        XCTAssertTrue(WorkPanel.rows(snapshot, filter: .reviewRequested, now: Date()).isEmpty)
        XCTAssertFalse(WorkPanel.header(snapshot, now: Date()).isEmpty)
        XCTAssertEqual(WorkPanel.atcFragment, "strips")
        XCTAssertNotNil(LinkRoute.workLink(URL(string: "https://github.com/octo/repo-a/pull/1")!))
        XCTAssertEqual(SecretKey(.github, .expiry).account, "expiry")
    }
}
