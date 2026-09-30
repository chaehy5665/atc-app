// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import Foundation
import ServiceManagement

/// Owns the live feed and the settings. Layout-free glue: every rule is in ATCCore.
@MainActor
final class AppModel: ObservableObject {
    static let urlKey = "atcURL"

    @Published private(set) var feed = FeedState()
    @Published private(set) var baseURL: URL
    /// Called on the main actor whenever the feed changes.
    var onFeedChange: (() -> Void)?

    private var task: Task<Void, Never>?
    private var live: LiveFeed?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.urlKey) ?? ATCSettings.defaultURLString
        baseURL = ATCSettings.normalizeURL(saved) ?? ATCSettings.normalizeURL(ATCSettings.defaultURLString)!
    }

    func start() {
        task?.cancel()
        feed = FeedState()
        let feed = LiveFeed(client: ATCClient(baseURL: baseURL)) { [weak self] state in
            Task { @MainActor in
                self?.feed = state
                self?.onFeedChange?()
            }
        }
        live = feed
        task = Task.detached { await feed.run() }
        onFeedChange?()
    }

    func refresh() {
        guard let live else { return }
        Task { await live.refresh() }
    }

    /// Returns false when `text` isn't a usable atc URL.
    @discardableResult
    func setURL(_ text: String) -> Bool {
        guard let url = ATCSettings.normalizeURL(text) else { return false }
        UserDefaults.standard.set(url.absoluteString, forKey: Self.urlKey)
        if url != baseURL {
            baseURL = url
            start()
        }
        return true
    }

    var panel: PanelContent { PanelContent(feed, base: baseURL) }
    var title: StatusBarTitle { StatusBarTitle(feed) }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    var launchAtLoginNote: String {
        switch SMAppService.mainApp.status {
        case .requiresApproval: return "시스템 설정 > 일반 > 로그인 항목에서 허용해야 합니다"
        case .notFound: return "~/Applications의 앱 번들에서 실행해야 합니다"
        default: return ""
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ANNUNCIATOR launch at login error: %@", String(describing: error))
        }
        objectWillChange.send()
    }
}
