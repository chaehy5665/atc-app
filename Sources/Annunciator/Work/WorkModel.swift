// SPDX-License-Identifier: Apache-2.0
import ATCCore
import Combine
import Foundation

/// The PR list and the Linear issue list for the popover lines and the Work window (ATC-247, ATC-248). Glue only:
/// the polling rules, the budget and the text are in ATCCore (`GitHubClient`, `LinearClient`, `RateBudget`, `WorkPanel`).
/// Reads only: every GitHub request is a GET and every Linear request a GraphQL query.
/// Polls every 60 s, and only while the popover or the Work window is open, plus a manual Refresh.
///
/// `GitHubClient.refresh()` runs off the main actor, so the client is touched by one pass at a time:
/// settings changes and sign-in resets wait until no pass is running (`whenIdle`), and the numbers the UI reads
/// are copies taken after a pass.
@MainActor
final class WorkModel: ObservableObject {
    static let reposKey = "work.github.repos"
    static let capKey = "work.github.cap"
    static let teamsKey = "work.linear.teams"
    static let pollSeconds: UInt64 = 60

    @Published private(set) var snapshot = GitHubSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var linearSnapshot = LinearSnapshot()
    @Published var filter: WorkFilter = .all
    /// Which list the Work window shows.
    @Published var source: WorkSource = .github
    /// Settings text: Linear team keys, one per line. Saved when `setTeams` accepts it.
    @Published private(set) var teamText: String
    /// Settings text: one `owner/name` per line. Saved when `setRepos` accepts it.
    @Published private(set) var repoText: String
    @Published private(set) var cap: Int
    /// Requests counted this hour, as of the last pass.
    @Published private(set) var used = 0

    private let signIn: SignInModel
    private let broker: TokenBroker
    private let client: GitHubClient
    private let linearBroker: TokenBroker
    private let linear: LinearClient
    private var viewers: Set<String> = []
    private var pollTask: Task<Void, Never>?
    private var phaseWatch: AnyCancellable?
    private var linearPhaseWatch: AnyCancellable?

    init(signIn: SignInModel, store: SecretStore = KeychainStore()) {
        self.signIn = signIn
        let defaults = UserDefaults.standard
        let text = defaults.string(forKey: Self.reposKey) ?? ""
        let startCap = RateBudget.clamp((defaults.object(forKey: Self.capKey) as? Int) ?? RateBudget.defaultCap)
        let clientKey = SignInModel.githubClientKey
        let broker = TokenBroker(
            service: .github, store: store,
            refreshRequest: { token in
                GitHubAuth.validClientID(UserDefaults.standard.string(forKey: clientKey) ?? "")
                    .map { DeviceFlow.refreshRequest(clientID: $0, refreshToken: token) }
            },
            parseRefresh: { DeviceFlow.parseRefresh($0) })
        let transport = WorkTransport()
        let client = GitHubClient(transport: transport, tokens: broker, cap: startCap)
        client.setRepos(RepoRef.parseList(text).repos)
        self.broker = broker
        self.client = client

        let linearKey = SignInModel.linearClientKey
        let linearBroker = TokenBroker(
            service: .linear, store: store,
            refreshRequest: { token in
                LinearAuth.validClientID(UserDefaults.standard.string(forKey: linearKey) ?? "")
                    .map { LinearAuth.refreshRequest(clientID: $0, refreshToken: token) }
            },
            parseRefresh: { LinearAuth.parseToken($0) })
        let teams = defaults.string(forKey: Self.teamsKey) ?? ""
        let linear = LinearClient(transport: transport, tokens: linearBroker)
        linear.setTeams(TeamKey.parseList(teams).keys)
        self.linearBroker = linearBroker
        self.linear = linear
        teamText = teams
        repoText = text
        cap = startCap
        // Signing in or out starts from nothing: no list, no ETag, no cached token.
        phaseWatch = signIn.$githubPhase.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.signInChanged() }
        }
        linearPhaseWatch = signIn.$linearPhase.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.linearSignInChanged() }
        }
    }

    var signedIn: Bool { signIn.githubPhase == .signedIn }
    var linearSignedIn: Bool { signIn.linearPhase == .signedIn }
    var repos: [RepoRef] { RepoRef.parseList(repoText).repos }
    var teams: [TeamKey] { TeamKey.parseList(teamText).keys }

    /// The popover line; nil while signed out.
    func line(now: Date = Date()) -> WorkLine? {
        WorkPanel.line(snapshot, signedIn: signedIn, repos: repos.count, now: now)
    }

    /// The Linear popover line; nil while signed out of Linear.
    func linearLine(now: Date = Date()) -> WorkLine? {
        WorkPanel.linearLine(linearSnapshot, signedIn: linearSignedIn, teams: teams.count, now: now)
    }

    var rows: [WorkRow] { WorkPanel.rows(snapshot, filter: filter, now: Date()) }
    var header: String { WorkPanel.header(snapshot, now: Date()) }
    var linearRows: [LinearRow] { WorkPanel.linearRows(linearSnapshot, now: Date()) }
    var linearHeader: String { WorkPanel.linearHeader(linearSnapshot, now: Date()) }
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

    /// Returns the entries that are not team keys; nothing is saved while there are any.
    @discardableResult
    func setTeams(_ text: String) -> [String] {
        let parsed = TeamKey.parseList(text)
        guard parsed.rejected.isEmpty else { return parsed.rejected }
        teamText = parsed.keys.map(\.value).joined(separator: "\n")
        UserDefaults.standard.set(teamText, forKey: Self.teamsKey)
        whenIdle { [self] in
            linear.setTeams(parsed.keys)
            linearSnapshot = linear.snapshot
            if linearSignedIn && !viewers.isEmpty { await pass() }
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
        guard signedIn || linearSignedIn, !busy else { return }
        busy = true
        if signedIn {
            snapshot = await client.refresh()
            used = client.budget.used(at: Date())
        }
        if linearSignedIn { linearSnapshot = await linear.refresh() }
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

    private func linearSignInChanged() {
        whenIdle { [self] in
            await linearBroker.invalidate()
            linear.reset()
            linearSnapshot = linear.snapshot
            if linearSignedIn && !viewers.isEmpty { await pass() }
        }
    }
}
