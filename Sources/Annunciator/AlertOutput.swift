// SPDX-License-Identifier: Apache-2.0
import ATCCore
import AVFoundation
import Foundation
import UserNotifications

/// System calls for a `NotifyPlan`: banners, the tone, the voice WAV. Every rule is in ATCCore.
/// Sound goes through AVFoundation, so it plays with no window open and with no browser.
@MainActor
final class AlertOutput {
    private let center: UNUserNotificationCenter?
    private let clickDelegate = NotificationClickDelegate()
    private var playing: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var askedForPermission = false
    private var generation = 0
    /// True while an alert tone or voice is playing. RADIO waits for it, and stops when it starts.
    private(set) var isBusy = false
    var onBusyChanged: ((Bool) -> Void)?

    init() {
        // A bare executable (swift run) has no bundle and UNUserNotificationCenter would trap.
        if Bundle.main.bundleIdentifier != nil {
            center = UNUserNotificationCenter.current()
            center?.delegate = clickDelegate
        } else {
            center = nil
        }
    }

    func perform(_ plan: NotifyPlan, base: URL) {
        for note in plan.notifications { post(note) }
        if plan.tone != nil || plan.voiceKey != nil { play(tone: plan.tone, voiceKey: plan.voiceKey, base: base) }
    }

    // MARK: Notifications

    /// Asks once (the first time a banner is needed, or from Settings). macOS remembers the answer.
    func requestPermission() {
        guard let center, !askedForPermission else { return }
        askedForPermission = true
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error { NSLog("ANNUNCIATOR notification permission error: %@", String(describing: error)) }
        }
    }

    private func post(_ note: AlertNotification) {
        guard let center else { return }
        requestPermission()
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        // The app plays its own tone; the banner itself stays silent.
        content.sound = nil
        content.threadIdentifier = "atc-alerts"
        if let url = note.url { content.userInfo = ["url": url.absoluteString] }
        center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: nil)) { error in
            if let error { NSLog("ANNUNCIATOR notification error: %@", String(describing: error)) }
        }
    }

    // MARK: Sound

    /// A new plan replaces one still playing: only the highest of the latest burst should be heard.
    private func play(tone: NotifyLevel?, voiceKey: String?, base: URL) {
        playing?.cancel()
        player?.stop()
        generation += 1
        let gen = generation
        setBusy(true)
        playing = Task { [weak self] in
            defer { Task { @MainActor in self?.finish(gen) } }
            // Start the download now so the callout follows the tone without a gap.
            let voice = voiceKey.flatMap { VoiceURL.url(base: base, key: $0) }.map { url in
                Task { await Self.fetchVoice(url) }
            }
            if let tone { await self?.play(data: AlertTone.wav(for: tone)) }
            if Task.isCancelled { voice?.cancel(); return }
            if let data = await voice?.value { await self?.play(data: data) }
        }
    }

    private func finish(_ gen: Int) {
        if gen == generation { setBusy(false) }
    }

    private func setBusy(_ busy: Bool) {
        guard busy != isBusy else { return }
        isBusy = busy
        onBusyChanged?(busy)
    }

    /// GET only. A 404 means the server has no phrase for this alert (tone only); that is not an error.
    private static func fetchVoice(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    private func play(data: Data) async {
        guard let p = try? AVAudioPlayer(data: data) else { return }
        player = p
        guard p.play() else { return }
        while p.isPlaying, !Task.isCancelled { try? await Task.sleep(nanoseconds: 50_000_000) }
        if Task.isCancelled { p.stop() }
    }

    /// Settings "Test": the WARNING tone and one banner.
    func test(base: URL) {
        let alert = SupervisorAlert(key: "test|annunciator", group: "alert", level: .warning, text: "테스트 알림", next: "이 알림은 시험용입니다", link: nil)
        perform(NotifyPlan(notifications: [AlertNotification(alert, level: .warning, base: base)], tone: .warning, voiceKey: nil), base: base)
    }
}

/// Shows banners even while the app is active, and opens the atc tab on a click.
final class NotificationClickDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let text = response.notification.request.content.userInfo["url"] as? String
        completionHandler()
        Task { @MainActor in LinkOpener.open(text.flatMap { URL(string: $0) }) }
    }
}
