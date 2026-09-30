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

    /// Notification, tone and voice switches; changing one saves it.
    @Published var notifyPrefs: NotifyPrefs {
        didSet { Self.save(notifyPrefs) }
    }

    /// RADIO monitor switches (off by default); changing one saves it and restarts the monitor.
    @Published var radioPrefs: RadioPrefs {
        didSet { Self.save(radioPrefs); applyRadio() }
    }
    /// The monitor state, for the popover hint.
    @Published private(set) var radio = RadioMonitor()
    /// Where click-throughs open: the atc window (default) or the browser (D10).
    @Published var linkPreference: LinkPreference {
        didSet { UserDefaults.standard.set(linkPreference.rawValue, forKey: "linkPreference") }
    }

    /// The launchd SSH forward (ATC-204); does nothing while its host is empty.
    let forward = ForwardMonitor()

    /// The DUTY row (D6); nil hides it. Read with GET only, and only while the popover is open or atc comes back.
    @Published private(set) var duty: DutyLamp?
    private var dutyTask: Task<Void, Never>?
    private var dutyPolling = false
    private static let dutyPollSeconds: UInt64 = 5

    private var task: Task<Void, Never>?
    private var live: LiveFeed?
    private var radioTask: Task<Void, Never>?
    private var radioStream: RadioStream?
    private let radioOutput = RadioOutput()
    private var notifier = AlertNotifier()
    private let output = AlertOutput()

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.urlKey) ?? ATCSettings.defaultURLString
        baseURL = ATCSettings.normalizeURL(saved) ?? ATCSettings.normalizeURL(ATCSettings.defaultURLString)!
        notifyPrefs = Self.loadPrefs()
        linkPreference = UserDefaults.standard.string(forKey: "linkPreference").flatMap(LinkPreference.init(rawValue:)) ?? .window
        radioPrefs = Self.loadRadioPrefs()
        // An alert tone or voice wins: RADIO stops when one starts and goes on after it.
        output.onBusyChanged = { [weak self] busy in
            guard let self else { return }
            if busy { self.radioOutput.stop() } else { self.pumpRadio() }
        }
    }

    func start() {
        task?.cancel()
        feed = FeedState()
        duty = nil
        // A new atc (or first start) gets a new baseline: its first list is silent.
        notifier = AlertNotifier()
        let feed = LiveFeed(client: ATCClient(baseURL: baseURL)) { [weak self] state in
            Task { @MainActor in
                let cameBack = state.connection == .live && self?.feed.connection != .live
                self?.feed = state
                if cameBack { self?.fetchDuty() }
                if state.connection == .unreachable { self?.forward.refresh() }
                self?.notify(state)
                self?.onFeedChange?()
            }
        }
        live = feed
        task = Task.detached { await feed.run() }
        applyRadio()
        onFeedChange?()
    }

    func refresh() {
        guard let live else { return }
        Task { await live.refresh() }
    }

    /// After wake or a network change: drop the old connection so the feed reconnects with its backoff.
    /// The last seen alert keys are kept, so what was raised while away notifies once.
    func reconnectNow() {
        live?.dropConnection()
        radioStream?.dropConnection()
    }

    // MARK: DUTY row

    /// The popover opened (true) or closed (false): poll `GET /api/duty/status` only while it is open.
    func setDutyPolling(_ on: Bool) {
        dutyPolling = on
        dutyTask?.cancel()
        dutyTask = nil
        guard on else { return }
        dutyTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readDuty()
                try? await Task.sleep(nanoseconds: Self.dutyPollSeconds * 1_000_000_000)
            }
        }
    }

    /// One read, on the reconnect.
    private func fetchDuty() {
        guard !dutyPolling else { return }  // the poll already reads it
        Task { await readDuty() }
    }

    /// A failed read (older atc without the endpoint, or unreachable) hides the row.
    private func readDuty() async {
        let client = ATCClient(baseURL: baseURL)
        let status = try? await client.dutyStatus()
        guard !Task.isCancelled else { return }
        duty = DutyLamp.of(status)
    }

    // MARK: RADIO monitor

    /// (Re)starts the `radio` stream for the current switches, or stops it. Its own connection: alerts don't depend on it.
    private func applyRadio() {
        radioTask?.cancel()
        radioTask = nil
        radioStream = nil
        radioOutput.stop()
        radio.configure(radioPrefs, now: Date())
        guard radioPrefs.on else { return }
        let client = ATCClient(baseURL: baseURL)
        let freq = radioPrefs.freq
        let stream = RadioStream(
            client: client,
            onUp: { [weak self] in
                Task { @MainActor in
                    self?.radio.connect(now: Date())
                    // The hint starts from the newest transmission on the frequency; it is never played.
                    if let items = try? await client.radio(freq: freq), self?.radioPrefs.freq == freq { self?.radio.seed(items) }
                }
            },
            onDown: { [weak self] in
                Task { @MainActor in
                    self?.radio.disconnect()
                    self?.radioOutput.stop()
                }
            },
            onItems: { [weak self] items in
                Task { @MainActor in
                    guard let self else { return }
                    self.radio.ingest(items, quiet: self.notifyPrefs.quiet.contains(Date()))
                    self.pumpRadio()
                }
            })
        radioStream = stream
        radioTask = Task.detached { await stream.run() }
    }

    /// Starts the next queued transmission when nothing else is sounding.
    private func pumpRadio() {
        guard !radioOutput.isPlaying else { return }
        guard let next = radio.next(alertBusy: output.isBusy, quiet: notifyPrefs.quiet.contains(Date())) else { return }
        radioOutput.play(next, base: baseURL) { [weak self] in self?.pumpRadio() }
    }

    // MARK: Notifications and sound

    private func notify(_ state: FeedState) {
        // Only a real list counts; the empty default before the first event would make every key "new".
        guard state.alertsLoaded else { return }
        let plan = notifier.update(items: state.alerts, base: baseURL, prefs: notifyPrefs, now: Date())
        if !plan.isEmpty { output.perform(plan, base: baseURL) }
    }

    func requestNotificationPermission() { output.requestPermission() }
    func testAlert() { output.test(base: baseURL) }

    private static func loadPrefs() -> NotifyPrefs {
        let d = UserDefaults.standard
        var p = NotifyPrefs()
        if d.object(forKey: "notify.banner") != nil { p.notifications = d.bool(forKey: "notify.banner") }
        if d.object(forKey: "notify.sound") != nil { p.sound = d.bool(forKey: "notify.sound") }
        p.voice = d.bool(forKey: "notify.voice")
        p.quiet = QuietHours(
            on: d.bool(forKey: "notify.quiet.on"),
            from: d.string(forKey: "notify.quiet.from") ?? QuietHours.defaultFrom,
            to: d.string(forKey: "notify.quiet.to") ?? QuietHours.defaultTo)
        return p
    }

    private static func save(_ p: NotifyPrefs) {
        let d = UserDefaults.standard
        d.set(p.notifications, forKey: "notify.banner")
        d.set(p.sound, forKey: "notify.sound")
        d.set(p.voice, forKey: "notify.voice")
        d.set(p.quiet.on, forKey: "notify.quiet.on")
        d.set(clock(p.quiet.from), forKey: "notify.quiet.from")
        d.set(clock(p.quiet.to), forKey: "notify.quiet.to")
    }

    private static func loadRadioPrefs() -> RadioPrefs {
        let d = UserDefaults.standard
        return RadioPrefs(on: d.bool(forKey: "radio.on"), freq: d.string(forKey: "radio.freq"), noise: d.string(forKey: "radio.noise"))
    }

    private static func save(_ p: RadioPrefs) {
        let d = UserDefaults.standard
        d.set(p.on, forKey: "radio.on")
        d.set(p.freq.rawValue, forKey: "radio.freq")
        d.set(p.noise.rawValue, forKey: "radio.noise")
    }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

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
