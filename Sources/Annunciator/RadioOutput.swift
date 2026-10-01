// SPDX-License-Identifier: Apache-2.0
import ATCCore
import AVFoundation
import Foundation

/// Plays one RADIO transmission at a time: GET the WAV atc rendered from its phrase template, play it.
/// The app never builds speech from free text. Every rule (what, when, how many) is in `RadioMonitor`.
@MainActor
final class RadioOutput {
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?

    var isPlaying: Bool { task != nil }

    /// Plays `transmission`, then calls `done` (not after `stop`). A 404 (no phrase) or any failure just ends it.
    func play(_ transmission: RadioTransmission, base: URL, done: @escaping () -> Void) {
        stop()
        guard let url = RadioURL.wav(base: base, id: transmission.id) else { done(); return }
        task = Task { [weak self] in
            if let data = await Self.fetch(url), !Task.isCancelled { await self?.play(data: data) }
            guard !Task.isCancelled else { return }
            self?.task = nil
            done()
        }
    }

    /// An alert tone started, atc went away or the monitor was turned off: cut it off, no `done`.
    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
    }

    /// GET only.
    private static func fetch(_ url: URL) async -> Data? {
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
}
