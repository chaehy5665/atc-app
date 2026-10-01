// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import ATCCore

final class ForwardTests: XCTestCase {
    func testValidHosts() {
        for h in ["atc-host", "me@atc-host", "host.example.com", "u_1@10.0.0.5", "a", " padded "] {
            XCTAssertNotNil(ForwardHost.validate(h), h)
        }
        XCTAssertEqual(ForwardHost.validate(" me@h "), "me@h")
    }

    func testRejectedHosts() {
        let bad = [
            "", " ", "-oProxyCommand=touch /tmp/x", "-h", "--help", "-", "-o", "me@-host", "-me@host",
            "a b", "host name", "a=b", "host;id", "host$(id)", "`id`", "a|b", "a&b", "a\nb", "a\tb",
            "@host", "me@", "a@b@c", "host:22", "[::1]", "host/../x", "hóst", "ho\u{0}st",
            String(repeating: "a", count: 254),
        ]
        for h in bad { XCTAssertNil(ForwardHost.validate(h), h.debugDescription); XCTAssertNil(ForwardSpec(host: h)) }
    }

    func testProgramArguments() {
        let spec = ForwardSpec(host: "me@atc-host")!
        XCTAssertEqual(spec.programArguments.joined(separator: " "),
            "/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o BatchMode=yes -L 7700:127.0.0.1:7700 me@atc-host")
    }

    func testPlistExact() {
        let expected = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>dev.atc.forward</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/ssh</string>
                <string>-N</string>
                <string>-o</string>
                <string>ExitOnForwardFailure=yes</string>
                <string>-o</string>
                <string>ServerAliveInterval=30</string>
                <string>-o</string>
                <string>BatchMode=yes</string>
                <string>-L</string>
                <string>7700:127.0.0.1:7700</string>
                <string>atc-host</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>

        """
        XCTAssertEqual(ForwardSpec(host: "atc-host")!.plistXML, expected)
    }

    func testPlistHasNoSecretsOrExtraKeys() {
        let xml = ForwardSpec(host: "atc-host")!.plistXML
        for word in ["Password", "IdentityFile", "Environment", "StandardOutPath", "StandardErrorPath", "sudo", "SSH_AUTH"] {
            XCTAssertFalse(xml.contains(word), word)
        }
    }

    func testPaths() {
        XCTAssertEqual(ForwardSpec.plistPath(home: "/Users/x"), "/Users/x/Library/LaunchAgents/dev.atc.forward.plist")
        XCTAssertEqual(ForwardSpec.bootoutArguments(uid: 501), ["bootout", "gui/501/dev.atc.forward"])
        XCTAssertEqual(ForwardSpec.bootstrapArguments(uid: 501, plistPath: "/p"), ["bootstrap", "gui/501", "/p"])
        XCTAssertEqual(ForwardSpec.kickstartArguments(uid: 501), ["kickstart", "-k", "gui/501/dev.atc.forward"])
        XCTAssertEqual(ForwardSpec.lsofArguments, ["-nP", "-iTCP:7700", "-sTCP:LISTEN"])
    }

    func testParseLaunchctlPrint() {
        let running = """
        gui/501/dev.atc.forward = {
        \tactive count = 1
        \tstate = running
        \tpid = 4242
        \tlast exit code = (never exited)
        }
        """
        XCTAssertEqual(LaunchdStatus.parse(printOutput: running), .loaded(running: true, pid: 4242, lastExitCode: nil))
        let stopped = "\tstate = waiting\n\tlast exit code = 255\n"
        XCTAssertEqual(LaunchdStatus.parse(printOutput: stopped), .loaded(running: false, pid: nil, lastExitCode: 255))
    }

    func testParseLsof() {
        let out = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        ssh     31337   me    5u  IPv4 0x1234      0t0  TCP 127.0.0.1:7700 (LISTEN)
        ssh     31337   me    6u  IPv6 0x1235      0t0  TCP [::1]:7700 (LISTEN)
        """
        XCTAssertEqual(PortHolder.parse(lsofOutput: out), PortHolder(pid: 31337, command: "ssh"))
        XCTAssertEqual(PortHolder.parse(lsofOutput: "Code\\x20Helper 99 me 1u IPv4 0 0t0 TCP *:7700 (LISTEN)"),
                       PortHolder(pid: 99, command: "Code Helper"))
        XCTAssertNil(PortHolder.parse(lsofOutput: ""))
        XCTAssertNil(PortHolder.parse(lsofOutput: "COMMAND PID USER\n"))
    }

    private func facts(installed: Bool = true, matches: Bool = true, launchd: LaunchdStatus = .loaded(running: true, pid: 10, lastExitCode: nil),
                       answers: Bool = true, holder: PortHolder? = nil) -> ForwardState {
        ForwardState(ForwardFacts(installed: installed, plistMatches: matches, launchd: launchd, answers: answers, holder: holder))
    }

    func testStates() {
        var s = facts(installed: false, matches: false, launchd: .notLoaded, answers: false)
        XCTAssertEqual(s.kind, .notInstalled); XCTAssertEqual(s.action, .install)
        s = facts(matches: false)
        XCTAssertEqual(s.kind, .plistDiffers); XCTAssertEqual(s.action, .repair)
        s = facts(launchd: .notLoaded, answers: false)
        XCTAssertEqual(s.kind, .notLoaded); XCTAssertEqual(s.action, .repair)
        s = facts(launchd: .loaded(running: false, pid: nil, lastExitCode: 255), answers: false)
        XCTAssertEqual(s.kind, .stopped); XCTAssertEqual(s.action, .restart)
        XCTAssertEqual(s.line, "포워드: 멈춤 (exit 255) — 다시 시작")
        XCTAssertTrue(s.hint.contains("ssh-add --apple-use-keychain"))
        s = facts(launchd: .loaded(running: false, pid: nil, lastExitCode: 1), answers: false)
        XCTAssertFalse(s.hint.contains("keychain"))
        s = facts(launchd: .loaded(running: false, pid: nil, lastExitCode: nil), answers: false)
        XCTAssertEqual(s.line, "포워드: 멈춤 — 다시 시작")
        s = facts(answers: false)
        XCTAssertEqual(s.kind, .noAnswer); XCTAssertEqual(s.action, .restart)
        s = facts()
        XCTAssertEqual(s.kind, .healthy); XCTAssertEqual(s.action, .none)
    }

    func testPortClashLeavesItAlone() {
        let other = PortHolder(pid: 555, command: "Code Helper")
        var s = facts(launchd: .loaded(running: false, pid: nil, lastExitCode: 255), answers: true, holder: other)
        XCTAssertEqual(s.kind, .portClash); XCTAssertEqual(s.action, .none)
        XCTAssertTrue(s.line.contains("555")); XCTAssertTrue(s.line.contains("Code Helper"))
        // Not installed at all: still a clash, no install offered.
        s = facts(installed: false, matches: false, launchd: .notLoaded, answers: true, holder: other)
        XCTAssertEqual(s.kind, .portClash); XCTAssertEqual(s.action, .none)
        // The agent's own ssh holding the port is not a clash.
        s = facts(holder: PortHolder(pid: 10, command: "ssh"))
        XCTAssertEqual(s.kind, .healthy)
        // Agent "running" with a different pid than the holder is a clash.
        s = facts(holder: PortHolder(pid: 11, command: "ssh"))
        XCTAssertEqual(s.kind, .portClash)
    }
}
