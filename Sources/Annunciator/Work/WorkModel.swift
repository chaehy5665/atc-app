// SPDX-License-Identifier: Apache-2.0
import ATCCore
import Combine
import Foundation

/// The PR list for the popover line and the Work window (ATC-247). Glue only: the polling rules, the budget and the
/// text are in ATCCore (`GitHubClient`, `RateBudget`, `WorkPanel`). Reads only: every request is a GET.
/// Polls every 60 s, and only while the popover or the Work window is open, plus a manual Refresh.
///
/// `GitHubClient.refresh()` runs off the main actor, so the client is touched by one pass at a time:
/// settings changes and sign-in resets wait until no pass is running (`whenIdle`), and the numbers the UI reads
/// are copies taken after a pass.
@MainActor
final class WorkModel: ObservableObject {
    static let reposKey = "work.github.repos"
    static let capKey = "work.github.cap"
    static let pollSeconds: UInt64 = 60

    @Published private(set) var snapshot = GitHubSnapshot()
    @Published private(set) var busy = false
    @Published var filter: WorkFilter = .all
    /// Settings text: one `owner/name` per line. Saved when `setRepos` accepts it.
    @Published private(set) var repoText: String
    @Published private(set) var cap: Int
    /// Requests counted this hour, as of the last pass.
    @Published private(set) var used = 0

    private let signIn: SignInModel
    private let broker: GitHubTokenBroker
    private let client: GitHubClient
    private var viewers: Set<String> = []
    private var pollTask: Task<Void, Never>?
    private var phaseWatch: AnyCancellable?

    init(signIn: SignInModel, store: SecretStore = KeychainStore()) {
        self.signIn = signIn
        let defaults = UserDefaults.standard
        let text = defaults.string(forKey: Self.reposKey) ?? ""
        let startCap = RateBudget.clamp((defaults.object(forKey: Self.capKey) as? Int) ?? RateBudget.defaultCap)
        let clientKey = SignInModel.githubClientKey
        let broker = GitHubTokenBroker(store: store, clientID: { UserDefaults.standard.string(forKey: clientKey) ?? "" })
        let client = GitHubClient(transport: WorkTransport(), tokens: broker, cap: startCap)
        client.setRepos(RepoRef.parseList(text).repos)
        self.broker = broker
        self.client = client
        repoText = text
        cap = startCap
        // Signing in or out starts from nothing: no list, no ETag, no cached token.
        phaseWatch = signIn.$githubPhase.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.signInChanged() }
        }
    }

    var signedIn: Bool { signIn.githubPhase == .signedIn }
    var repos: [RepoRef] { RepoRef.parseList(repoText).repos }

    /// The popover line; nil while signed out.
    func line(now: Date = Date()) -> WorkLine? {
        WorkPanel.line(snapshot, signedIn: signedIn, repos: repos.count, now: now)
    }

    var rows: [WorkRow] { WorkPanel.rows(snapshot, filter: filter, now: Date()) }
    var header: String { WorkPanel.header(snapshot, now: Date()) }
    /// For Settings: "123 / 1000".
    var usageText: String { "\(used) / \(cap)" }

    // MARK: Settings

    /// Returns the entries that were not `owner/name`; nothing is saved while there are any.
    @discardableResult
    func setRepos(_ text: String) -> [String] {
        let parsed = RepoRef.parseList(text)
        guard parsed.rejected.isEmpty else { return parsed.rejected }
        repoText = parsed.repos.map(\.fullName).joined(separator: "\n")
        UserDefaults.standard.set(repoText, forKey: Self.reposKey)
        whenIdle { [self] in
            client.setRepos(parsed.repos)
            snapshot = client.snapshot
            if signedIn && !viewers.isEmpty { await pass() }
        }
        return []
    }

    func setCap(_ value: Int) {
        cap = RateBudget.clamp(value)
        UserDefaults.standard.set(cap, forKey: Self.capKey)
        let newCap = cap
        whenIdle { [self] in client.setCap(newCap) }
    }

    // MARK: Polling

    /// The popover or the Work window opened (true) or closed (false). Polling runs while any is open.
    func setViewing(_ who: String, _ on: Bool) {
        if on { viewers.insert(who) } else { viewers.remove(who) }
        if viewers.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        } else if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pass()
                    try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
                }
            }
        }
    }

    func refreshNow() {
        Task { await pass() }
    }

    private func pass() async {
        guard signedIn, !busy else { return }
        busy = true
        let result = await client.refresh()
        snapshot = result
        used = client.budget.used(at: Date())
        busy = false
    }

    /// Runs `work` once no pass is running.
    private func whenIdle(_ work: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            while busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            await work()
        }
    }

    private func signInChanged() {
        whenIdle { [self] in
            await broker.invalidate()
            client.reset()
            snapshot = client.snapshot
            used = client.budget.used(at: Date())
            if signedIn && !viewers.isEmpty { await pass() }
        }
    }
}
