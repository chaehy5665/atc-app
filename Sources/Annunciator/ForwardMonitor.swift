// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import Foundation

/// Watches and repairs the launchd SSH forward (ATC-204). All decisions are in ATCCore (`ForwardState`);
/// this only launches `launchctl` and `lsof`, writes one plist in ~/Library/LaunchAgents and probes localhost:7700.
/// No shell, no sudo. With an empty host it does nothing at all.
@MainActor
final class ForwardMonitor: ObservableObject {
    static let hostKey = "forward.host"

    @Published private(set) var host: String
    @Published private(set) var state: ForwardState?
    @Published private(set) var busy = false
    /// The last failed action, shown in Settings.
    @Published private(set) var error = ""

    private var lastRefresh = Date.distantPast
    private let uid = getuid()
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostKey) ?? ""
    }

    var spec: ForwardSpec? { ForwardSpec(host: host) }

    /// Returns false when `text` is not an acceptable host; an empty text turns the feature off.
    @discardableResult
    func setHost(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            host = ""
            state = nil
            error = ""
            UserDefaults.standard.removeObject(forKey: Self.hostKey)
            return true
        }
        guard let ok = ForwardHost.validate(trimmed) else { return false }
        host = ok
        UserDefaults.standard.set(ok, forKey: Self.hostKey)
        refresh(force: true)
        return true
    }

    /// Looks again; rate-limited to once per 5 s unless forced (the feed retries much faster than that).
    func refresh(force: Bool = false) {
        guard let spec, !busy else { return }
        if !force, Date().timeIntervalSince(lastRefresh) < 5 { return }
        lastRefresh = Date()
        let (uid, home) = (self.uid, self.home)
        Task {
            let facts = await Task.detached { Self.gather(spec: spec, uid: uid, home: home) }.value
            // The host may have been changed or cleared while looking.
            guard self.spec == spec else { return }
            self.state = ForwardState(facts)
        }
    }

    /// Install or repair: write the plist atomically, bootout (a "not loaded" failure is fine), bootstrap.
    func install() {
        guard let spec, !busy else { return }
        busy = true
        error = ""
        let (uid, home) = (self.uid, self.home)
        Task {
            let failure = await Task.detached { Self.installNow(spec: spec, uid: uid, home: home) }.value
            self.busy = false
            self.error = failure ?? ""
            self.refresh(force: true)
        }
    }

    func restart() {
        guard spec != nil, !busy else { return }
        busy = true
        error = ""
        let uid = self.uid
        Task {
            let r = await Task.detached { Self.run(ForwardSpec.launchctlPath, ForwardSpec.kickstartArguments(uid: uid)) }.value
            self.busy = false
            if r.status != 0 { self.error = "launchctl kickstart 실패 (\(r.status)): \(r.text)" }
            self.refresh(force: true)
        }
    }

    func perform(_ action: ForwardAction) {
        switch action {
        case .none: break
        case .install, .repair: install()
        case .restart: restart()
        }
    }

    // MARK: Off the main actor

    private struct RunResult { var status: Int32; var text: String }

    private nonisolated static func run(_ path: String, _ args: [String]) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return RunResult(status: -1, text: String(describing: error)) }
        // Read before waiting, so a full pipe cannot block the child.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return RunResult(status: p.terminationStatus, text: text)
    }

    private nonisolated static func gather(spec: ForwardSpec, uid: UInt32, home: String) -> ForwardFacts {
        let path = ForwardSpec.plistPath(home: home)
        let existing = try? String(contentsOfFile: path, encoding: .utf8)
        let printed = run(ForwardSpec.launchctlPath, ForwardSpec.printArguments(uid: uid))
        let launchd: LaunchdStatus = printed.status == 0 ? .parse(printOutput: printed.text) : .notLoaded
        let holder = PortHolder.parse(lsofOutput: run(ForwardSpec.lsofPath, ForwardSpec.lsofArguments).text)
        return ForwardFacts(
            installed: existing != nil, plistMatches: existing == spec.plistXML,
            launchd: launchd, answers: probe(), holder: holder)
    }

    /// One GET to localhost:7700; any HTTP answer counts.
    private nonisolated static func probe() -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:\(ForwardSpec.localPort)/")!, timeoutInterval: 2)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        let ok = Flag()
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok.value = response is HTTPURLResponse
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 3)
        return ok.value
    }

    /// Returns a message on failure, nil on success.
    private nonisolated static func installNow(spec: ForwardSpec, uid: UInt32, home: String) -> String? {
        let path = ForwardSpec.plistPath(home: home)
        do {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(spec.plistXML.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return "plist를 쓰지 못했습니다: \(error.localizedDescription)"
        }
        // "Not loaded" is the normal first-install case; any bootout failure is ignored and bootstrap decides.
        _ = run(ForwardSpec.launchctlPath, ForwardSpec.bootoutArguments(uid: uid))
        let r = run(ForwardSpec.launchctlPath, ForwardSpec.bootstrapArguments(uid: uid, plistPath: path))
        return r.status == 0 ? nil : "launchctl bootstrap 실패 (\(r.status)): \(r.text)"
    }
}

/// Written once by the URLSession callback, read after the semaphore.
private final class Flag: @unchecked Sendable { var value = false }
