<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (ATC-204, SSH forward)

Run after the PR is merged and `Tools/build-app.sh` builds. The app target (AppKit, SwiftUI, Process) was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots.

Use a spare host name or a test alias first if you can: step 4 replaces `~/Library/LaunchAgents/dev.atc.forward.plist`. If the agent is running from the atc `menubar.md` setup, step 4 will replace it (same label), so back the file up: `cp ~/Library/LaunchAgents/dev.atc.forward.plist ~/dev.atc.forward.plist.bak`.

1. `Tools/build-app.sh` succeeds. Paste compiler errors if not.
2. Settings shows **SSH 호스트** empty. With it empty the app runs no `launchctl` or `lsof` and the popover looks as before while atc is unreachable.
3. Type `-oProxyCommand=touch /tmp/x` and press Apply: a red message, nothing saved. Also try `a b`, `a=b`, `-h`: all refused. `me@host` and `host.example.com` are accepted.
4. Enter your real host (`user@host`) and press **설치/복구**. `~/Library/LaunchAgents/dev.atc.forward.plist` has the exact `/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o BatchMode=yes -L 7700:127.0.0.1:7700 <host>` arguments, `RunAtLoad` and `KeepAlive`, and nothing else (`plutil -p`). `launchctl print gui/$(id -u)/dev.atc.forward` shows `state = running`. The status line says `포워드: 정상`. `curl -s localhost:7700/api/supervisor-summary` answers.
5. Press **설치/복구** again: no error (bootout of a loaded agent, then bootstrap).
6. `launchctl bootout gui/$(id -u)/dev.atc.forward`, then quit and reopen Settings (or press **확인**): `포워드: 로드 안 됨 — 복구`. Edit the plist by hand (add a space in a string) and press **확인**: `설정이 다름 — 복구`. **설치/복구** fixes both.
7. Popover while atc is unreachable, forward stopped: `pkill -f 'ssh -N.*7700'` several times so launchd throttles, or stop the agent, then look: the unreachable notice shows a line like `포워드: 멈춤 (exit 255) — 다시 시작` and a **다시 시작** button; pressing it brings the forward and the light back within a few seconds.
8. Passphrase key: with a passphrase-protected key that is not in the keychain, the agent exits 255 and the status line and popover show the `ssh-add --apple-use-keychain` hint. After `ssh-add --apple-use-keychain <key>` and **다시 시작** it runs.
9. Port clash: `launchctl bootout gui/$(id -u)/dev.atc.forward`, then `ssh -N -L 7700:127.0.0.1:7700 <host>` by hand in a terminal. Press **확인**: `포워드: 7700을 ssh(PID n)이 쓰는 중`, no button offered, and the app starts nothing. The PID matches `lsof -nP -iTCP:7700 -sTCP:LISTEN`. Stop the manual ssh, **확인**, then **설치/복구**.
10. Clear the host field and press Apply: the app stops looking (no status line, no buttons in the popover). The plist is left in place; the app never deletes it.
11. `ls ~/Library/LaunchAgents` shows only the one new file from the app; nothing was written elsewhere and no password prompt (`sudo`) appeared.
12. The atc window's unreachable overlay still shows its old text (it does not carry the forward line yet).
