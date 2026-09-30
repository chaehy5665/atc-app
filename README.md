# atc-app

**English** · [한국어](README.ko.md)

A native macOS menu bar app for [atc](https://github.com/chaehy5665/atc), the air-traffic-control board for AI coding sessions. Working name: **ANNUNCIATOR**, after the cockpit's MASTER WARNING / MASTER CAUTION panel.

It sits in the menu bar and lights up when atc needs the SUPERVISOR:

- a MASTER WARNING (red) or MASTER CAUTION (amber) light with a count, and the busiest ACCOUNT's FUEL used;
- one click shows the lit items (LAMPS) with their AIRCRAFT, FLIGHT or STAND, pending DISPATCH decisions, the last RTS, and working sessions;
- each item opens the right atc tab in the atc window (the atc web UI in a native window; Settings can switch this to the browser, and ⌥-click opens the browser once);
- a macOS notification, the tone and the voice callout for a new WARNING or CALL.

It only reads from atc. Approvals and switches stay in the atc screen.

> Status (2026-09-30): v1 app (N3) written: MASTER light, popover, settings. Notifications and sound (N4) are written, not yet checked on a Mac. Design: [docs/design.md](docs/design.md). The app target has not been built on a Mac yet; see [docs/mac-checklist-n3.md](docs/mac-checklist-n3.md).

## How it connects

atc listens on `127.0.0.1:7700` on the machine it runs on. From a Mac, keep an SSH local forward up (`ssh -N -L 7700:127.0.0.1:7700 <host>`, or the launchd agent in atc's `docs/guide/menubar.md`). The app talks to `http://localhost:7700` and never opens a port.

The app can also set that forward up and watch it (ATC-204). Put the SSH destination (`host` or `user@host`; letters, digits, `.`, `_`, `-` only) in Settings → **SSH 호스트**. **설치/복구** writes `~/Library/LaunchAgents/dev.atc.forward.plist` (`/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o BatchMode=yes -L 7700:127.0.0.1:7700 <host>`, `RunAtLoad`, `KeepAlive`) and loads it with `launchctl bootstrap gui/<uid>`; **다시 시작** runs `launchctl kickstart -k`. While atc is unreachable the popover names the forward's state and offers the matching button. If something else already listens on 7700 (a manual `ssh -L`, an editor's port forward) the app says which process (PID and command) and leaves it alone. The field is empty by default, and then the app does nothing. No `sudo`, no keys or passwords in the plist: `BatchMode=yes` makes a key with a passphrase fail fast, so add it to the keychain (`ssh-add --apple-use-keychain <key>`). The app only sends GET and SSE to atc; `launchctl` and `lsof` run locally on the Mac. Checklist: [docs/mac-checklist-forward.md](docs/mac-checklist-forward.md). Don't make atc listen on the LAN: atc has no login.

## Build and run (on the Mac)

```sh
Tools/build-app.sh      # swift build -c release, bundle Annunciator.app, ad-hoc sign, copy to ~/Applications
```

```sh
open ~/Applications/Annunciator.app
```

1. Keep the SSH forward to atc up (see above). The atc that serves `/api/supervisor-summary` (ATC-153) must be deployed.
2. Run `Tools/build-app.sh` (needs the Xcode command line tools). With Command Line Tools only, the app must not use SwiftUI macros (`@State`, `#Preview`, …), which need Xcode's plugin; `ObservableObject` and `@ObservedObject` are fine. `Tools/test-linux.sh` checks this.
3. Open the app. `✈ —` in grey means atc is unreachable; it reconnects by itself (1 s backoff, doubling to 30 s).
4. Click the item for the popover: a fixed strip (MASTER WARNING, MASTER CAUTION and ADVISORY counts, PENDING and NEEDS YOU chips, FUEL bars, one line for RTS and working counts) above a scrolling list of LAMPs (WARNING always open, CAUTION shows the first 5, ADVISORY folded; the choice is remembered) with each LAMP's age. The gear button (⌘,) opens Settings. Settings sets the atc URL (default `http://localhost:7700`) and launch at login.

## The atc window

Every click-through (a lamp, a pending row, a NEEDS YOU chip, **Open atc ↗**, a notification) opens the atc web UI in one native window and switches to the right tab without a reload. The window is the atc page itself, so approvals and settings work as in a browser tab, from the same `http://localhost:7700` origin. Only that origin loads in the window; links to GitHub, Linear or anything else, and `target=_blank`, open in the default browser. While the window is open the app has a Dock icon (badge: the MASTER count), Cmd-Tab and a menu bar with Edit, View (Reload ⌘R, zoom) and Window. Closing the window goes back to the menu bar item alone and releases the page. When atc cannot be reached the window shows the popover's text instead of a browser error and reloads by itself when atc returns. Settings: **atc 열기** chooses app window (default) or browser.

## Alerts: notification, tone, voice

For each **new** WARNING (`level: "warning"`) or CALL (`cue: "call"`), whatever its key, the app posts a macOS notification with the lamp text and the next step. A click opens that item's tab in the browser. It asks for notification permission once (the first banner, or **알림 허용 요청** in Settings). Nothing fires for what is already lit at start, and nothing for CAUTION or ADVISORY.

- **Tone:** a short tone the app generates (WARNING three beeps, CALL two). With **음성** on, the callout WAV from atc (`GET /api/voice/alert/<key>.wav`, the phrase always comes from the server) plays after it. Several new alerts at once give one tone and one voice, for the highest level. Both play with no window open and no browser running.
- **Quiet hours:** atc keeps its alert settings in each browser, so the app has its own field in Settings (default off, 22:00 to 08:00, a window may cross midnight). Tone and voice stay silent inside it; banners still post.
- **Sleep, wake, network:** after wake or a network change the feed reconnects with the usual backoff. Alerts raised while away notify once, compared with the last seen list; alerts raised and cleared while away do not.
- **Turn the browser's sound off.** While the app plays sound, switch off 소리 (and 음성) in the atc screen's settings in your browser, or every WARNING sounds twice. Nothing changes in atc for this yet.

The app only reads from atc: a notification has no ACK. Acknowledge in the browser.

## RADIO monitor

Settings has a **RADIO monitor** switch (off by default). It plays one frequency of atc's RADIO (`TOWER` by default; `DELIVERY`, `GROUND` and `COMPANY` too) through the app, with no browser tab open.

- **Noise:** the same choice as the browser: calls only (default), unanswered calls only, or everything.
- **What plays:** the app opens its own SSE connection with `topics=radio`, and for each new transmission it downloads `GET /api/radio/<id>.wav` (atc renders it from a phrase template; the app never builds speech from free text) and plays it, one at a time. The queue holds 5 and drops the oldest.
- **Alerts win:** a WARNING or CALL tone or voice stops RADIO audio and RADIO waits until it ends. Quiet hours (the same field as for alerts) silence RADIO and drop what waits.
- **No replay:** only what is recorded after you turn it on, or after the last (re)connect, is heard. While atc is unreachable nothing plays; when it comes back, traffic from the gap is not played. A call that later gets its reply is not played twice.
- **Popover:** while it is on, a `RADIO ● TOWER` line under the status line shows the last transmission's head (`TOWER → GOLF · GO AROUND · ATC-147`). The menu bar title does not change.
- Settings are kept in UserDefaults (`radio.on`, `radio.freq`, `radio.noise`). The app only reads from atc (GET and SSE).
- Turn off LISTEN in the browser's RADIO tab while the app plays, or you hear it twice.

A locally built app carries no quarantine flag, so it opens without a Developer ID.

Core tests run on Linux with `Tools/test-linux.sh` (Docker).

CI (`.github/workflows/ci.yml`) runs on every PR and push to `main`: job `mac` builds the app target and runs `swift test` on a macOS runner; job `linux` runs `Tools/test-linux.sh` (core tests and the SwiftUI macro check). A PR must be green on both. CI cannot see runtime behaviour, so screens, sound and notifications are still checked on a Mac with the checklists in `docs/`.

## Licence

GPL-3.0-or-later, see [LICENSE](LICENSE). atc itself is a separate program with its own licence; the app talks to it only over HTTP. Code reused from other GPL-3.0 projects keeps its copyright notice, and the source file names where it came from.
