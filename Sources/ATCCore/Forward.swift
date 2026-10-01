// SPDX-License-Identifier: Apache-2.0
import Foundation

// ATC-204: the launchd SSH forward (`dev.atc.forward`). Pure rules only: the app target writes the
// plist and launches launchctl/lsof, and feeds what it saw back in as `ForwardFacts`.

/// An SSH destination the app is willing to put in a plist: `host` or `user@host`, each part `[A-Za-z0-9._-]+`
/// and not starting with `-`. No spaces, no `=`, no `:`; this keeps `-oProxyCommand=…` and friends out of ssh's argv.
public enum ForwardHost {
    public static let maxLength = 253

    /// The trimmed host when it is acceptable, nil otherwise (empty included).
    public static func validate(_ text: String) -> String? {
        let host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.utf8.count <= maxLength else { return nil }
        let parts = host.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        for part in parts {
            guard let first = part.unicodeScalars.first, first != "-", part.unicodeScalars.allSatisfy(allowed) else { return nil }
        }
        return host
    }

    private static func allowed(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
        default: return false
        }
    }
}

/// What the launchd agent is: label, plist text and the `launchctl` argument lists.
public struct ForwardSpec: Equatable, Sendable {
    public static let label = "dev.atc.forward"
    public static let localPort = 7700
    public static let remote = "127.0.0.1:7700"
    public static let sshPath = "/usr/bin/ssh"
    public static let launchctlPath = "/bin/launchctl"
    public static let lsofPath = "/usr/sbin/lsof"

    public let host: String

    /// Nil unless `ForwardHost.validate` accepts `host`.
    public init?(host: String) {
        guard let ok = ForwardHost.validate(host) else { return nil }
        self.host = ok
    }

    /// argv of the agent, `ssh` first.
    public var programArguments: [String] {
        [
            Self.sshPath, "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "BatchMode=yes",
            "-L", "\(Self.localPort):\(Self.remote)",
            host,
        ]
    }

    /// The exact plist the app installs. No keys, passwords, log paths or environment.
    public var plistXML: String {
        let args = programArguments.map { "        <string>\(Self.escape($0))</string>\n" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
        \(args)    </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>

        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// `~/Library/LaunchAgents/dev.atc.forward.plist` for a home directory: the only file the app writes.
    public static func plistPath(home: String) -> String {
        (home as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func domain(uid: UInt32) -> String { "gui/\(uid)" }
    public static func target(uid: UInt32) -> String { "gui/\(uid)/\(label)" }

    // launchctl argument lists (run without a shell, never with sudo).
    public static func bootoutArguments(uid: UInt32) -> [String] { ["bootout", target(uid: uid)] }
    public static func bootstrapArguments(uid: UInt32, plistPath: String) -> [String] { ["bootstrap", domain(uid: uid), plistPath] }
    public static func kickstartArguments(uid: UInt32) -> [String] { ["kickstart", "-k", target(uid: uid)] }
    public static func printArguments(uid: UInt32) -> [String] { ["print", target(uid: uid)] }
    public static let lsofArguments = ["-nP", "-iTCP:\(localPort)", "-sTCP:LISTEN"]
}

/// What `launchctl print gui/<uid>/dev.atc.forward` said.
public enum LaunchdStatus: Equatable, Sendable {
    /// `print` failed: the agent is not loaded.
    case notLoaded
    case loaded(running: Bool, pid: Int?, lastExitCode: Int?)

    /// Reads the `state = running`, `pid = N` and `last exit code = N` lines. Anything else is "loaded, not running".
    public static func parse(printOutput: String) -> LaunchdStatus {
        var running = false, pid: Int?, exit: Int?
        for raw in printOutput.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("state = ") { running = line.dropFirst("state = ".count) == "running" }
            else if line.hasPrefix("pid = ") { pid = Int(line.dropFirst("pid = ".count)) }
            else if line.hasPrefix("last exit code = ") { exit = Int(line.dropFirst("last exit code = ".count)) }
        }
        return .loaded(running: running, pid: pid, lastExitCode: exit)
    }
}

/// A process listening on 7700, from `lsof -nP -iTCP:7700 -sTCP:LISTEN`.
public struct PortHolder: Equatable, Sendable {
    public let pid: Int
    public let command: String
    public init(pid: Int, command: String) { self.pid = pid; self.command = command }

    /// The first data row (`COMMAND PID USER …`); lsof escapes spaces in COMMAND as `\x20`. Nil when nothing listens.
    public static func parse(lsofOutput: String) -> PortHolder? {
        for raw in lsofOutput.split(whereSeparator: \.isNewline) {
            let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 2, f[0] != "COMMAND", let pid = Int(f[1]) else { continue }
            return PortHolder(pid: pid, command: String(f[0]).replacingOccurrences(of: "\\x20", with: " "))
        }
        return nil
    }
}

/// Everything the app looked at, as plain values.
public struct ForwardFacts: Equatable, Sendable {
    public var installed: Bool
    /// The installed plist equals `ForwardSpec.plistXML`.
    public var plistMatches: Bool
    public var launchd: LaunchdStatus
    /// `http://localhost:7700` answered.
    public var answers: Bool
    public var holder: PortHolder?

    public init(installed: Bool, plistMatches: Bool, launchd: LaunchdStatus, answers: Bool, holder: PortHolder? = nil) {
        self.installed = installed; self.plistMatches = plistMatches
        self.launchd = launchd; self.answers = answers; self.holder = holder
    }
}

/// The one button a state offers.
public enum ForwardAction: Equatable, Sendable {
    case none, install, repair, restart

    public var title: String? {
        switch self {
        case .none: return nil
        case .install: return "설치"
        case .repair: return "복구"
        case .restart: return "다시 시작"
        }
    }
}

public enum ForwardKind: Equatable, Sendable {
    case notInstalled, plistDiffers, notLoaded, stopped, noAnswer, healthy
    /// 7700 is held by something that is not the agent; the app leaves it alone.
    case portClash
}

/// A popover line and an action from `ForwardFacts`.
public struct ForwardState: Equatable, Sendable {
    public let kind: ForwardKind
    /// One popover line, e.g. `포워드: 멈춤 (exit 255) — 다시 시작`.
    public let line: String
    public let action: ForwardAction
    /// Extra Settings text (passphrase hint, clash details); empty when there is none.
    public let hint: String

    public static let keychainHint = "암호가 있는 키는 BatchMode에서 실패합니다. ssh-add --apple-use-keychain <키 파일> 로 키체인에 넣으세요."

    public init(_ f: ForwardFacts) {
        let agentPid: Int?
        if case .loaded(_, let pid, _) = f.launchd { agentPid = pid } else { agentPid = nil }
        // Something else on 7700 (a manual `ssh -L`, an editor's port forward): report it, do not fight it.
        if let h = f.holder, h.pid != agentPid {
            kind = .portClash
            line = "포워드: 7700을 \(h.command)(PID \(h.pid))이 쓰는 중"
            action = .none
            hint = "다른 프로그램이 localhost:7700을 잡고 있어 에이전트가 뜨지 못합니다. 그 포워드를 끄거나, 그대로 쓰려면 SSH 호스트를 비우세요."
            return
        }
        guard f.installed else {
            (kind, line, action, hint) = (.notInstalled, "포워드: 설치 안 됨 — 설치", .install, "")
            return
        }
        guard f.plistMatches else {
            (kind, line, action, hint) = (.plistDiffers, "포워드: 설정이 다름 — 복구", .repair, "")
            return
        }
        switch f.launchd {
        case .notLoaded:
            (kind, line, action, hint) = (.notLoaded, "포워드: 로드 안 됨 — 복구", .repair, "")
        case .loaded(let running, _, let exit):
            if !running {
                let code = exit.map { " (exit \($0))" } ?? ""
                (kind, line, action) = (.stopped, "포워드: 멈춤\(code) — 다시 시작", .restart)
                hint = exit == 255 ? Self.keychainHint : ""
            } else if !f.answers {
                (kind, line, action, hint) = (.noAnswer, "포워드: 실행 중, 응답 없음 — 다시 시작", .restart,
                                              "원격 atc가 꺼져 있거나 호스트에 닿지 않을 수 있습니다.")
            } else {
                (kind, line, action, hint) = (.healthy, "포워드: 정상", .none, "")
            }
        }
    }
}
