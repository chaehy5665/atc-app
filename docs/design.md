# atc-app design (ANNUNCIATOR: a native menu bar app for the SUPERVISOR)

A cockpit's annunciator panel is the row of MASTER WARNING and MASTER CAUTION lights plus the labelled lamps that say which system needs the crew. ANNUNCIATOR is the same for the SUPERVISOR's Mac: a native menu bar app that lights up when atc needs them, says why, and opens the right atc tab. It replaces the SwiftBar plugin from ATC-149 once it does at least as much.

> Status (2026-09-29): adopted. The SUPERVISOR asked for it after using the SwiftBar plugin (ATC-149) for a day. They chose a separate public repository, `atc-app`, under GPL-3.0 (D8). The working name ANNUNCIATOR is decision D1. Nothing is built. The server side (what atc serves to this app) is in atc's `docs/mac-app.md`.

Related, in the atc repository: [docs/mac-app.md](https://github.com/chaehy5665/atc/blob/main/docs/mac-app.md) (the server side), [docs/guide/menubar.md](https://github.com/chaehy5665/atc/blob/main/docs/guide/menubar.md) (the SwiftBar plugin and SSH forward), [docs/guide/alerts.md](https://github.com/chaehy5665/atc/blob/main/docs/guide/alerts.md) and [docs/guide/voice.md](https://github.com/chaehy5665/atc/blob/main/docs/guide/voice.md) (SUPERVISOR alerts, sounds, voice callouts), `server/supervisor-alerts.ts` (ATC-87), `menubar/format.mjs` (ATC-149), ATC-152 (alert noise).

## 1. Current facts

**Where things run**

- atc runs on a Linux host (`vocado-dev`). The production server listens only on `127.0.0.1:7700`.
- The SUPERVISOR works on a Mac. They reach atc through an SSH local forward, kept up by a launchd agent (`dev.atc.forward`, set up on 2026-09-29 from atc's `docs/guide/menubar.md`).
- atc has no login. SUPERVISOR-only writes are guarded by a browser Origin check (`server/origin.ts`). That check stops other sites' browser requests. It is not access control: any direct client can send `Origin: http://localhost`. The access control is that atc listens on localhost only.

**What a client can read today** (all GET, no auth)

| Endpoint | Content | Size on 2026-09-29 |
|---|---|---|
| `/api/supervisor-alerts` | `items[]`: `key`, `group` (health, alert, following, pending, land, rts), `level` (advisory, caution, warning or null), `cue` (call, done or null), `aircraft`, `flight`, `text`, `next`, `link` (screen hash), `since` | 40 KB |
| `/api/events` (SSE) | `version`; `snapshot` (the whole snapshot on every change); `alert` (`raised`, `cleared`, `items`, `initial`); `ping` every 25 s | the snapshot alone is 340 KB per event |
| `/api/fleet` | AIRCRAFT rows, `fuelAccounts` (plan-limit windows per ACCOUNT) | — |
| `/api/update` | RTS state: deployed, main, CI, last result | — |
| `/api/control/sessions` | control sessions, job state, NEEDS YOU | — |
| `/api/voice/alert/:key.wav` | the voice callout for a WARNING or CALL alert, rendered by the host's TTS engine (ATC-140) | — |

**The SwiftBar plugin (ATC-149), after one day of use**

- **How it works:** a node script polls every 15 s. The pure formatting is in `menubar/format.mjs` (13 tests). Notifications go through `swiftbar://notify`, and "seen" keys are kept in SwiftBar's cache folder.
- **What falls short:**
  - no live updates (15 s polling) and no sound or voice;
  - a text-only menu with no grouping, no icons and no expanding rows;
  - it needs node on the Mac and SwiftBar running;
  - it can't do anything; every action opens the browser.
- **What it exposed:** the alert list itself is noisy. It showed `✈ 73`, most of it stale `no-report` CAUTIONs and old `disagreed` proposals. ATC-152 fixes that on the server, and any client benefits.

**Who can build and test what**

- Team sessions run on the Linux host. They can't run macOS, AppKit or SwiftUI, and they can't see the UI.
- There is no Swift toolchain on the host. Docker works without sudo (29.1.3), so the official `swift` image can build and test Foundation-only Swift code there. The image is pulled once, about 1 GB.
- GitHub Actions has macOS runners, and this repository can use them (N6).
- The SUPERVISOR's Mac can build a Swift package with the Xcode command line tools. **An app built locally carries no quarantine flag, so Gatekeeper doesn't block it**, with no signing needed.

**Prior art**

- Vorssaint (`vorssaint/vorssaint-utils`, GPL-3.0) is a large open-source menu bar suite. Its structure:
  - SwiftPM only, no Xcode project, no third-party dependencies;
  - AppKit `NSStatusItem`s, several of them, with SwiftUI inside;
  - `LSUIElement` (no Dock icon);
  - per-feature `…Service` (I/O) and `…Support` (pure) files;
  - Developer ID signing and notarization in CI.
- It also reads Claude Code usage from `~/.claude/projects` on the Mac. atc's sessions run on the host, so that doesn't cover them.
- **Licences.** atc and atc-app are both Apache-2.0 (D8, changed 2026-09-30), and the two talk only over HTTP. Vorssaint is GPL-3.0: it stays a design reference only and its code may not be copied here. Code from other projects is allowed only under Apache-2.0-compatible permissive licences (MIT, BSD, Apache-2.0, ISC), keeping its copyright notice and naming the source file and commit at the top of the file (`CLAUDE.md` "라이선스").

## 2. Goals and non-goals

**Goals**

- **Title:** the menu bar shows a MASTER WARNING or MASTER CAUTION light (colour plus count) and the FUEL used of the busiest ACCOUNT. It updates live (SSE), not by polling.
- **Popover:** one click opens it, with:
  - the lit items by level, each naming its AIRCRAFT, FLIGHT or STAND;
  - pending DISPATCH decisions, the last RTS, working AIRCRAFT and control sessions (with NEEDS YOU), and the ACCOUNT FUEL windows.
  - Each item opens the right atc tab: in the browser until N7, then in the app's own atc window (section 10).
- **macOS notifications** for new WARNING and CALL alerts, with the tone and, if VOICE is on, the voice callout WAV from the host.
- Graceful when atc is unreachable: a grey light, "atc 연결 안 됨 — SSH 포워딩", and it reconnects by itself.
- Launch at login. No Dock icon, except while the atc window (N7) is open.

**Non-goals for v1**

- No writes from the app's own code to atc: no ACK, approve, reject or switch sent by Swift. That needs an auth design first (section 7, N5). The atc web UI hosted in the atc window (N7) is the browser client in a different frame and keeps the browser's access model (section 10.3, D9).
- No new server state and no telemetry. Network use is the configured atc URL and, once signed in, the GitHub and Linear APIs with the app's own Keychain tokens (section 11, D12, decided 2026-10-01). Nothing outside atc is contacted before sign-in.
- No per-Mac Claude usage reading (the Vorssaint feature). atc FUEL already covers the host.

## 3. Principles

1. **The server decides, the app shows.** Levels, texts, counts, "what is pending" and the title numbers come from the server as data. The app doesn't re-derive atc rules, so the browser, the SwiftBar plugin and the app always agree.
2. **Read only until there is an access model.** Adding writes means adding real authentication for SUPERVISOR routes. That is a separate design with `Risk: Security`, not a side effect of the app. *(Section 11 (D12, decided 2026-10-01): this stays true for atc. GitHub and Linear are a different trust boundary with their own rules in 11.2 and 11.4: read only first, no merge ever, and only the writes listed in `WritePolicy`.)*
3. **A pure core tested on Linux.** Everything that isn't AppKit or SwiftUI (decoding, SSE parsing, reconnect backoff, seen-key diff, formatting) lives in a Foundation-only target. Team sessions test it in the `swift` Docker image on the host.
4. **Built on the Mac, not shipped as a binary.** v1 has no signed download. The SUPERVISOR builds from the checkout with one script, which avoids Developer ID, notarization and CI secrets.
5. **The public repo stays clean.** No screenshots, and no real names or emails in code or bundle IDs. Reused permissively licensed code keeps its notices; no GPL code is copied.
6. **One client at a time.** atc's SwiftBar plugin stays as the fallback until the app matches it; then it is retired or kept documented as the fallback (D5).

## 4. Terms

| Term | Meaning |
|---|---|
| ANNUNCIATOR | The native Mac menu bar app (working name, D1) |
| MASTER WARNING / MASTER CAUTION | The title light: red when any WARNING is lit, amber when any CAUTION is, off otherwise. The count next to it is the number lit at that level and above |
| LAMP | One lit item in the popover: one SUPERVISOR alert, with its text, place and next step |

## 5. Architecture

```
atc-app/
  Package.swift              swift-tools 5.9+, macOS 14+, no dependencies
  Sources/ATCCore/           Foundation only (builds on Linux)
    Models.swift             Codable: SupervisorAlert, AlertEvent, Summary, FuelAccount, Update, ControlSession
    SSE.swift                line parser for text/event-stream (event, data, id, retry), pure
    Reconnect.swift          backoff schedule (1 s → 30 s cap, jitter), pure
    Annunciator.swift        title state from Summary; seen-key diff (new WARNING/CALL); Z-time formatting
    Client.swift             URLSession GET and SSE stream (FoundationNetworking on Linux, excluded from tests that need a server)
  Sources/Annunciator/       AppKit + SwiftUI (macOS only)
    App.swift                NSApplication, LSUIElement, launch at login (SMAppService)
    StatusItem.swift         NSStatusItem, title light, popover toggle
    Popover/*.swift          SwiftUI views: lamps by level, pending, RTS, FUEL, control sessions
    Notify.swift             UNUserNotificationCenter, tone, voice WAV playback (AVFoundation)
    Settings.swift           atc URL (default http://localhost:7700), sound/voice on/off, quiet hours mirror
  Tests/ATCCoreTests/        XCTest (or swift-testing), fixtures copied from the SwiftBar plugin tests
  Tools/build-app.sh         swift build -c release → Annunciator.app (Info.plist, icon), ad-hoc codesign, copy to ~/Applications
```

**Server additions in atc (small, read-only; atc's `docs/mac-app.md`)**

- **`GET /api/events?topics=alert,version`:** the same SSE with the 340 KB `snapshot` events left out. The browser keeps the default, which is all topics.
- **`GET /api/supervisor-summary`:** the title and panel numbers as one pure function of what the server already has:
  - counts by level;
  - the most-used ACCOUNT FUEL windows;
  - the pending DISPATCH count;
  - the last RTS;
  - working AIRCRAFT and control counts, and NEEDS YOU names.
  - The SwiftBar plugin moves to it too, so both clients show the same numbers.
  - It is sent on the alert topic whenever it changes.

**Connection**

- The app talks to `http://localhost:7700` through the existing SSH forward.
- It never opens a port and never needs the host's LAN address. The SSH tunnel is a launchd agent (`dev.atc.forward`), not the app's process. Since ATC-204 the app can set that agent up, watch it and restart it, only when the SUPERVISOR puts an SSH host in Settings (empty = the app does nothing, as before):
  - `ForwardSpec` (ATCCore) renders the one plist the app writes, in `~/Library/LaunchAgents` only; `ForwardHost` accepts `host` or `user@host` with `[A-Za-z0-9._-]`, never a leading `-`, no spaces, `=` or `:`, so ssh options cannot be injected; the plist has no keys, passwords, log paths or environment;
  - `ForwardState` maps what the app saw (installed, plist equal to the rendered one, `launchctl print` state and last exit code, whether `localhost:7700` answers, who listens on 7700) to one popover line and one action (none, install, repair, restart); the app target only launches `launchctl` and `lsof` (no shell, no `sudo`) and writes the plist;
  - if 7700 is held by something that is not the agent, the app says which process (PID, command) and does not fight it;
  - these are local process launches on the Mac. They are not atc writes: the app still sends only GET and SSE to atc (N5 unchanged).

## 6. Testing and landing

- **ATCCore:** `Tools/test-linux.sh` runs `swift build` and `swift test` in a pinned `swift` Docker image on the atc host, from any team STAND.
- **App target:** team sessions can't compile it. The PR says so and lists what to look at. The SUPERVISOR runs `Tools/build-app.sh` on the Mac after merge.
- **CI (N6/D4):** `.github/workflows/ci.yml` runs on every PR and push to `main`. Job `mac` (macOS runner, pinned Xcode) runs `swift build -c release --product Annunciator` and `swift test`; job `linux` runs `Tools/test-linux.sh`, including the `FORBIDDEN_MACROS` check, because GitHub's Xcode has the SwiftUI macro plugin and the mac job alone would not catch a macro that breaks Command Line Tools builds. A PR is green when both pass. CI cannot see runtime behaviour, so the Mac checklist stays for screens, sound and notifications. Job names are stable so the SUPERVISOR can make them required checks.
- **Merging:** the SUPERVISOR merges every PR here; atc's MCC lands only atc PRs. Until atc can mark an AIRPORT as "teams don't merge here" (an atc follow-up to ATC-151), TOWER gives LAND to the STAND holder, who answers UNABLE (`CLAUDE.md`), and the SUPERVISOR merges.
- **Checking the screen:** nobody but the SUPERVISOR sees the UI. They write what they saw in the PR or a comment, never a screenshot.

## 7. Implementation order

| Step | What | Needs | atc tier | Size |
|---|---|---|---|---|
| N0 | **SURVEY:** pin a `swift` Docker image that builds a Foundation-only package on the host; build a hello `NSStatusItem` app with `Tools/build-app.sh` spec'd for the Mac; check that an ad-hoc signed, locally built app can post `UNUserNotificationCenter` notifications and launch at login on the SUPERVISOR's macOS version (the SUPERVISOR runs the check) | — | — | S |
| N1 | **In atc:** `topics` filter on `/api/events`, `GET /api/supervisor-summary` (pure, tested), SwiftBar plugin switched to the summary | ATC-152 merged (clean counts) | atc auto | M |
| N2 | Package skeleton: ATCCore (models, SSE parser, reconnect, annunciator state, formatting) with Linux tests, `Tools/test-linux.sh`, `CHANGELOG.md` | N0 | — | M |
| N3 | App v1: status item with the MASTER light, the popover with lamps, pending, RTS, FUEL and control sessions, click-through to atc tabs, unreachable state, launch at login, `build-app.sh` | N1, N2 | — | M |
| N4 | Notifications and sound: new WARNING and CALL, the tone, the voice WAV (from `/api/voice/alert`), quiet hours taken from the server's alert settings, a notification click opening the tab | N3 | — | M |
| R4 | **RADIO monitor** (ATC-173, atc `docs/radio.md` section 4): a Settings switch plays one RADIO frequency (TOWER by default) from atc's `radio` SSE topic and `/api/radio/<id>.wav` through the N4 audio path; alerts win, quiet hours apply, no replay after a reconnect. Popover line, not the title | N4; atc R1, R3 | — | M |
| N5 | **Design only:** a SUPERVISOR token for write routes (ACK, approve, reject) that the app would hold in the Keychain; what it protects, how it rotates, how it is revoked. Not built until adopted | D3 | — | — |
| N6 | Later, by use: a notch view, a separate FUEL status item, an update check against GitHub Releases (the macOS CI job is built, ATC-205) | N3 | varies | — |
| N7 | **atc window** (section 10): one native window hosting the atc web UI in a `WKWebView`; remembered frame; Dock icon and Cmd-Tab only while open; every click-through (MASTER light, lamps, "Open atc", notifications) opens the right tab inside it; the popover's unreachable state; links outside atc go to the browser | N3; N4's single link opener | — | M |
| N7a | **In atc:** the web UI recognises the app window (a user-agent suffix) and leaves alert tones, voice callouts and browser notifications to the app there, since N4 plays them natively | N7 | atc auto | S |
| N8 | **Design only:** which screens, if any, become native SwiftUI views (section 10.6). Nothing is built until the SUPERVISOR picks one after using N7 | N7, two weeks of use | — | — |

## 8. Risks

| Risk | Mitigation |
|---|---|
| Nobody but the SUPERVISOR sees the UI, so regressions slip through | Keep logic in ATCCore with tests. The app target stays thin (layout only). Each app PR lists what the SUPERVISOR should look at |
| SSE through an SSH forward drops silently | `ping` every 25 s; treat 60 s without a ping as a drop and reconnect with backoff; show the grey light while down |
| Unsigned app blocked by Gatekeeper | Build locally (no quarantine). If a download is ever wanted, that is D2 (Developer ID and notarization) |
| Notification permission for an ad-hoc signed app | N0 checks it on the SUPERVISOR's macOS before any feature work |
| A write path grows without auth | Principle 2; N5 is design only and needs `Risk: Security` |
| Two clients drift (plugin vs app) | Both read `/api/supervisor-summary`; the plugin is retired or frozen after the app matches it (D5) |
| Reused code without its notices | `CLAUDE.md` requires the notice and source on every reused file; reviewers check new files for an SPDX line and, if reused, the source |
| macOS UI churn (for example Liquid Glass on macOS 26) | Target macOS 14 APIs, with no private APIs (unlike Vorssaint's HID and MediaRemote use) |
| The atc window becomes a second write client without anyone deciding it (N7) | D9 states it; the app adds no script bridge and no Swift write calls; navigation is locked to the atc origin (section 10.3) |
| Alerts sound twice: the app (N4) and the web page in the atc window, or a browser tab as well | N7a mutes the web page's alert audio inside the app; a browser tab keeps its own switch (section 10.4) |
| A GitHub or Linear token leaks, or a write path reaches merge | Section 11 (D12): Keychain only, read only first, no merge, `WritePolicy`, `Redact` |
| The window keeps a second full SSE stream (340 KB snapshots) open over the SSH forward when nobody looks | The web view is released when the window closes; reopening reloads it (section 10.2) |

## 9. Decisions (SUPERVISOR)

| # | Question | Proposal |
|---|---|---|
| D1 | App name | ANNUNCIATOR (the cockpit's MASTER WARNING/CAUTION panel) |
| D2 | Distribution | Build on the Mac with `Tools/build-app.sh`; no signed download for now |
| D3 | Writes from the app | Not in v1. Revisit after a week of use with a separate auth design (N5). *(Section 11: stays for atc; GitHub and Linear writes are D12c and D12d.)* |
| D4 | macOS CI compile job | Built (ATC-205): `mac` and `linux` jobs in `.github/workflows/ci.yml`; no signing, no artifacts |
| D5 | SwiftBar plugin after the app | Keep it as the documented fallback, frozen, reading the same summary |
| D6 | Minimum macOS | 14, unless the SUPERVISOR's Mac is newer and a newer API saves real work |
| D7 | Voice in the app | Yes (N4): play the host-rendered WAV; the radio effect stays in the browser for now |
| D8 | Repository and licence | **Decided 2026-09-29:** a separate public repository `atc-app`, GPL-3.0-or-later. atc stays MIT. **Changed 2026-09-30:** both atc and atc-app are Apache-2.0 from their next versions (ATC-214, ATC-215); earlier versions stay GPL-3.0-or-later / MIT for whoever received them |
| D9 | Writes through the atc window | The web UI in the atc window may write exactly as it does in a browser tab (localhost plus the Origin check). The app's Swift code still sends no writes, and it adds no JavaScript bridge. A token (N5) is still what native writes would need |
| D10 | Where click-throughs open after N7 | The atc window by default; a Settings switch goes back to the browser; ⌥-click always opens the browser |
| D11 | Order against N4 | **Decided 2026-09-30:** N4 ships first and opens the browser, but routes every click-through through one link opener; N7 swaps that opener for the window |
| D12 | GitHub and Linear inside the app | **Decided 2026-09-30 (direction)** and **2026-10-01 (details, D12a to D12j in 11.9):** the app calls both APIs itself with its own tokens in the Keychain |

## 10. The atc window (N7, N7a, N8)

> Status (2026-09-30): proposed by the SUPERVISOR. Nothing is built. Today every click-through (the MASTER light, a lamp, "Open atc ↗") calls `NSWorkspace.shared.open` in `PopoverView.swift` and opens a browser tab. The goal is an atc window inside the app that feels like a real Mac app. Milestone "M5 · atc window".

### 10.1 Current facts

- Click-through URLs come from ATCCore. `ATCLink.url(base:link:)` builds `http://localhost:7700/#<tab>` from the alert's `link` (a screen hash). `Panel` does the same for pending rows (`#dispatch`) and NEEDS YOU chips (`#strips`). The app target only calls `NSWorkspace.shared.open(url)`.
- The app is `LSUIElement` (set in `Tools/build-app.sh`). It has no Dock icon, no main menu and no windows except Settings.
- The atc web UI routes by `location.hash`. Tabs listen for `hashchange`, and the web's own alert click sets `location.hash = a.link` (`web/src/alerts-runtime.ts`). Changing the hash on an open page switches tabs without a reload.
- The web UI's alert runtime uses `localStorage`, `Notification`, `BroadcastChannel`, Web Locks and Web Audio. It treats a missing `Notification` as `unsupported`. Alert tone and voice are off by default and switched on per browser (`sound`, `voice.on`).
- The atc server accepts SUPERVISOR writes from any page whose `Origin` host is `localhost`, `127.0.0.1` or `[::1]` (`server/origin.ts`). A page loaded from `http://localhost:7700` in a `WKWebView` sends that `Origin`, so its writes pass exactly as in a browser.
- The Mac reaches atc only through the SSH local forward (`dev.atc.forward`). The popover already has an unreachable state: a grey light and "atc 연결 안 됨 — SSH 포워딩", with automatic reconnect.
- WebKit ships with macOS and the Command Line Tools SDK, so a `WKWebView` needs no dependency and no Xcode. The app target stays free of SwiftUI macros (ATC-163).

### 10.2 N7: the window

**Shape**

- **One window, not tabs or documents.** `AtcWindowController` owns a single `NSWindow` with a `WKWebView` filling it. AppKit only, with no SwiftUI (nothing here needs it, and it keeps the macro rule trivially).
- **Frame remembered:** `setFrameAutosaveName("atc")`, with a minimum size of about 900×600 and a first-open size of about 1280×820, centred.
- **The title** follows the page's `document.title` (KVO on `title`), falling back to "atc".
- **Dock icon and Cmd-Tab only while the window is open.**
  - Opening the window calls `NSApp.setActivationPolicy(.regular)` and then activates the app.
  - Closing it calls `.accessory` again, so the app is back to a menu bar item.
  - While the window is open, the Dock icon's badge shows the MASTER count (`dockTile.badgeLabel`, the same number as the title).
  - `build-app.sh` gains an app icon (`.icns`, drawn by a script in the repo; no third-party art).
- **A main menu**, needed once the app can be frontmost:
  - app menu: About, Settings…, Quit;
  - **Edit** (Undo, Redo, Cut, Copy, Paste, Select All). Without it, Cmd-C and Cmd-V don't work in the web UI's fields;
  - View: Reload (Cmd-R), Actual Size, Zoom In, Zoom Out;
  - Window: Close (Cmd-W), Minimize.
- **Close releases the web view.** The window can be reopened at once, but the page (and its full `/api/events` stream, 340 KB per snapshot) is not kept alive in the background. Reopening loads the page again, in about a second over the forward.

**Click-through**

- N4 introduces one `LinkOpener` in the app target, and every click-through goes through it:
  - the MASTER light;
  - lamps, pending rows and NEEDS YOU chips;
  - "Open atc ↗";
  - notification clicks.

  N7 replaces its body. No call site changes.
- **The decision is a pure function in ATCCore**, `LinkRoute.decide(url:base:preference:modifier:)`. It returns one of:
  - `.window(fragment)` for the atc origin (same scheme, host and port as the configured base);
  - `.browser(url)` for anything else, or when the Settings switch says browser (D10) or ⌥ is held.

  It is tested on Linux: the same origin, a different port, a different host, a missing fragment, and the preference and modifier paths.
- **In the window:**
  - if the page is loaded, set the hash on it without a reload, the same way the web's own alert click does;
  - if not, load `base/#fragment`;
  - then bring the window forward. The popover closes as it does today.

**Navigation policy** (`WKNavigationDelegate`, `WKUIDelegate`)

- Only the configured atc origin loads in the window.
- Links to GitHub, Linear or anything else, `target=_blank` and `window.open` go to the default browser. *(Section 11: this stays. The Work window's own rows also open the browser, and `LinkRoute.decide` gains `github.com` and `linear.app` as the only extra hosts allowed to open.)*
- No `WKScriptMessageHandler` and no injected scripts: the page cannot call Swift, and Swift only sets `location.hash`.
- The data store is the persistent default one, so the web UI's settings (theme, tabs, RADIO frequency) survive restarts. They are separate from the browser's.
- Media may play without a click (`mediaTypesRequiringUserActionForPlayback = []`), so RADIO audio (R3) works in the window without the browser's audio lock (ATC-162).

### 10.3 Access model (D9)

The window is the atc web UI, not new app code. Its writes (approve, reject, ACK, settings) go from the page to atc with `Origin: http://localhost:7700`, exactly like a browser tab on the same Mac.

- The access control stays what it is today: atc listens on the host's localhost, and the Mac reaches it only through the SSH forward.
- The app's Swift code still sends only GET and SSE. `CLAUDE.md`'s "read only" rule is reworded in the N7 PR to say "the app's own code" and to point here.
- N5 (a SUPERVISOR token) remains the design for any native write, such as a notification action button.

### 10.4 N7a: sound and notifications in the window (atc side)

With N4, the app plays the tone and the voice callout itself. If the web page inside the window also had `sound` or `voice.on` switched on, every WARNING would sound twice.

- **N7:** the app sets `applicationNameForUserAgent` to `ANNUNCIATOR/<version>`.
- **N7a** (atc, tier auto): when the web UI sees that suffix, it plays no alert tone or voice and raises no browser notification. Its settings panel says the app does this (for example "알림 소리와 음성은 ANNUNCIATOR가 냅니다").
  - The bell list, the RADIO tab and RADIO audio are unchanged.
  - Pure test: the host detection and the resulting alert prefs.
- **A browser tab elsewhere** keeps its own switches. If it has sound on, the SUPERVISOR hears the browser and the app. The N4 settings text says so; the app does not try to coordinate with the browser.

### 10.5 Reachability

- **Before loading:**
  - if the feed is already unreachable, the window shows a native overlay with the same text as the popover ("atc 연결 안 됨 — SSH 포워딩") and reconnect state, instead of WebKit's error page;
  - a failed first navigation (`didFailProvisionalNavigation`) shows the same overlay.
- **While open:** when the feed drops, the overlay covers the page. When it comes back, the overlay goes away and the page reloads once, because the page's own SSE has dropped too.
- The overlay's wording and state come from the same ATCCore values as the popover, so the two never disagree.

### 10.6 N8: native screens later (design only)

The first step hosts the whole web UI and adds no native screens. Principle 1 (the server decides, the app shows) and the testing facts in section 1 argue against re-building atc tabs in SwiftUI:

- every native screen is a second client that can drift from the web;
- team sessions cannot see or compile the app target;
- the macro rule makes SwiftUI state clumsier.

A screen becomes native only if it passes at least one of these tests, and the SUPERVISOR picks it after two weeks of using N7:

| Test | Example candidates |
|---|---|
| It needs the OS, which the web cannot do | a global hotkey to show the window; notification action buttons (needs N5 for writes); Touch ID to confirm an approve (N5) |
| It must stay visible while the SUPERVISOR works elsewhere | a small always-on-top strip (MASTER light, pending decisions, the open RADIO call); the notch view already listed in N6 |
| It is small, read-only and already modelled in ATCCore | the popover itself (already native) |

Full tabs (FLEET, DISPATCH, RADIO, METRICS, DOCS) stay web. If a candidate is picked, it gets its own issue with the data it reads (an existing endpoint or `supervisor-summary`) and no new server state.

### 10.7 Not built yet

N7 (window), N7a (atc: sound handed to the app), N8 (native screen candidates, design only).

### 10.8 D6 as built: the DUTY entry (ATC-234)

DUTY (chat with atc, decide in the same window) lives in the atc web UI drawer at `#duty`. The window already hosts it and its writes carry the localhost Origin (D9), so the app has no chat code. D6 adds a way in and DUTY's state at a glance.

- **Popover row:** `DUTY ● ↗` under the status line (and the RADIO hint). Click → `LinkOpener` with `ATCLink.url(base, "#duty")`, so `LinkRoute.decide` sends it to the window (hash set on a loaded page, else `base/#duty`), or to the browser under the D10 preference or ⌥. No new route type.
- **Menu:** Window > DUTY (⌘D), the same call.
- **Status source:** `GET /api/duty/status`, read only. `AppModel` polls it every 5 s only while the popover is open (`NSPopoverDelegate`), and reads it once when the feed comes back to live. It does **not** subscribe to the `duty` SSE topic (chat text), sends nothing, holds no token. DUTY has no sound and no notification (atc `docs/duty.md` 7).
- **Shaping (ATCCore, `DutyLamp.of`, tested on Linux):**
  - hidden while `enabled` is false, before the first read, or when the read fails (older atc without the endpoint, unreachable);
  - dot: `idle` green, `answering` amber, `down` or `blocked` red, and `blocked: true` in the body is red whatever `state` says; an unknown `state` shows a grey dot (PILOT'S DISCRETION);
  - tooltip `DUTY · <account> · context <k>/<cap>k` (thousands, rounded); parts atc did not send are left out.
- The popover height grows by one row while DUTY shows (`PanelLayout`, `dutyLine`).
- Not done: a DUTY badge on the menu bar title (the title stays the MASTER light); atc's `docs/duty.md` is linked to this section by ENGINEERING after the merge.

## 11. GitHub and Linear in the app (ATC-240, D12)

> Status (2026-10-01): **decided**, not built. The SUPERVISOR chose the direction on 2026-09-30 (D12): the app calls the GitHub and Linear APIs itself, with its own tokens in the Keychain. Not in-app web tabs, and not native lists fed by atc's data. On 2026-10-01 the SUPERVISOR answered 11.9: every recommendation was taken except D12d, which adds Linear state moves (Backlog, Todo, Canceled) to the Linear comment in GL2 (11.4, 11.5). No Swift, no tokens, no OAuth app yet: nothing here has been created or called. Build issues: GL0 to GL2 in 11.8.

### 11.1 Current facts

Facts about atc come from ATC-240 and the atc repository; verify them before building on them.

- **atc already reads both.** The atc server polls GitHub every 90 s through `gh` with the SUPERVISOR's token (`server/sources/github.ts`) and Linear with `LINEAR_API_KEY` (`server/sources/linear.ts`, two teams). The atc web UI has read-only FLIGHT and PR drawers (ATC-206), and they already show in the atc window (N7).
- **atc already writes, with guards.**
  - MCC lands `auto` and `flagged` atc PRs; AUTOLAND merges delegated PRs elsewhere; the MERGE button (DUTY G2) merges `user`-tier PRs at an exact head. **LANDING tiers** (`deploy/landing-tier.mjs`) decide who merges.
  - Linear writes go only through `server/sources/linear-write.ts` (G3 state moves, DUTY D7a), within fixed limits.
- **The GitHub budget is per user.** atc's LOGBOOK already spends about 1,300 GraphQL points an hour (atc issue 237). A second client on the same user's token draws from the same budget.
- **The app today talks only to atc** (GET and SSE, section 5). Links to GitHub and Linear open in the default browser (10.2).
- **Team sessions cannot compile the app target.** Only ATCCore (Foundation only) is tested on Linux (section 6).

Facts from the public API docs (read 2026-09-30; re-read before each build issue):

| Topic | What the docs say |
|---|---|
| GitHub App device flow | `POST github.com/login/device/code` and `…/login/oauth/access_token` with the `client_id` only, no client secret. Device flow must be enabled in the app's settings |
| GitHub App user token | Expires after 8 hours; the refresh token lasts 6 months. Permissions are fine-grained, not scopes: the token has what both the user and the app have, on the repositories where the app is installed |
| GitHub primary limit | User tokens (PAT, App user token, OAuth App token): 5,000 requests an hour. The page read said these share one bucket per user. **Design for the worst case: shared** (confirmed in the rate-limit docs on 2026-10-01, see 11.5) |
| GitHub secondary limits | 100 concurrent requests; 900 points a minute per REST endpoint group (GET = 1, write = 5); content creation 80 a minute and 500 an hour. On 403 or 429, honour `retry-after` |
| GitHub conditional requests | `ETag` with `If-None-Match`. GitHub is known to not count a `304` against the primary limit, but the pages read did not say so. **Verified 2026-10-01 (GL1a, see 11.5):** the REST best-practices page says a `304` on an authorized conditional request does not count against the primary limit |
| Linear OAuth 2 | Authorization code with PKCE and no client secret is supported. Access token lasts 24 hours, with a refresh token. Scopes: `read`, `write`, `issues:create`, `comments:create`, `admin`. There is a revoke endpoint. Always send `state` |
| Linear limits | API key: 2,500 requests and 3,000,000 complexity points an hour; OAuth app: 5,000 and 2,000,000. One query may cost at most 10,000 points. Exceeded = HTTP 400 with `RATELIMITED`. Linear recommends webhooks over polling, and the app has no public endpoint to receive them |

### 11.2 Principles (for this section)

1. **Principle 1 still holds.** The app shows raw GitHub and Linear facts (title, state, CI rollup, review state, mergeability as GitHub reports it). It does not compute CLEARED TO LAND, a LANDING tier, STRANDED or any other atc verdict. Next to a PR it offers a link to the atc view for the decision.
2. **No merge from the app, ever.** A merge goes through LANDING: MCC, AUTOLAND, or atc's MERGE button at an exact head. An app merge would bypass tiers and INSPECTION. The app does not ask for any permission that would allow it.
3. **Read first, write later, and each write is a separate decision.** GL1 is read only with read-only credentials. A write needs its own step (GL2), its own permission on the token, an explicit click with the target shown, and an entry in the pure `WritePolicy` (11.4). No write happens from a notification, a timer or a background refresh.
4. **Tokens are the app's own.** Not atc's `gh` token, not `LINEAR_API_KEY`, not a token copied from the host. The Keychain is the only place a token rests.
5. **The app stays polite to atc's budget.** It polls only while someone looks, uses conditional requests, and stops at a cap (11.5).
6. **The public repo stays clean.** No org names, emails, repository lists, client IDs or tokens in code, docs, fixtures, tests or the bundle. Client IDs and the repository list are entered in Settings and live in UserDefaults (they are not secrets, but they identify the SUPERVISOR's setup).

### 11.3 What the app shows

| Candidate | Source | Recommendation |
|---|---|---|
| Open PRs of the configured repositories: title, author, draft, CI rollup, review state, mergeability as GitHub reports it, updated | GitHub REST or one GraphQL query | **GL1.** The core of the feature |
| PRs waiting for the SUPERVISOR's review | a PR search for `review-requested:@me` | **GL1**, as a filter of the same list |
| GitHub notifications | `GET /notifications` (a classic-scope feature; a GitHub App user token can't reach it) | **Defer** |
| Linear issues by state for the configured teams | GraphQL, filtered and paginated small | **GL1.** Counts by state in the popover, the list in the window |
| Linear inbox (notifications) | GraphQL `notifications` | **Defer.** Add only if asked |

**Where.**
- **Popover:** one line per source ("GitHub: 3 open · 1 CI failing", "Linear: 4 Todo · 2 Started"), each opening the window. Counts are the raw numbers GitHub and Linear give, not atc severities, and they never light the MASTER light.
- **Window:** a new native "Work" window (AppKit list, no SwiftUI macros), beside the atc window, reached from Window > Work. A row click opens the PR or issue in the default browser (10.2 stays). Each PR row has a second action "Decide in atc ↗" that opens the atc window at the matching tab.
- **Against the N8 tests (10.6).** N8 said a screen becomes native only if it needs the OS, must stay visible while working elsewhere, or is small, read only and already modelled in ATCCore. Lists of PRs and issues mostly fail all three, and atc's web drawers already show them (ATC-206). D12 supersedes that default, so this is an explicit exception, not a pass. **Recommendation:** keep it small to limit drift: two lists, no editor, no detail pane, no search. Anything deeper opens the browser or atc.
- If the SUPERVISOR finds the Work window duplicates the atc drawers, the fallback is D12b (hybrid, 11.5).

### 11.4 What the app writes, and the guard for each

**A write is a typed value, not a free request.** ATCCore has a `WritePolicy` with a closed list of `WriteAction` cases. The app target has no generic "send this" path to GitHub or Linear. Anything not in the list cannot be sent, and there is a Linux test for each forbidden case.

| Write | Recommendation | Guard |
|---|---|---|
| **GitHub merge** (also enabling auto-merge, pushing a branch) | **Never.** Not in `WriteAction`, and not granted on the token | LANDING only. A test asserts `WriteAction` has no merge case |
| Linear issue delete, archive, bulk edit | **Never** | Same |
| Linear state move | **Yes, GL2, off by default (D12d, decided 2026-10-01).** atc's G3 button stays; the app is a second writer within the same limits | Only to Backlog, Todo and Canceled, atc's own limits; Started and Done stay with PRs and `Fixes`. The confirm sheet names the issue, its current state and the target state. The app re-reads the issue right before sending and refuses if the state changed since the list was drawn |
| Linear comment | **Yes, GL2, off by default (D12d).** A quick note from the Work window | Text typed by the SUPERVISOR; the confirm sheet names the issue; no templates and no text from atc. Scope: see the state move note in 11.5 |
| GitHub PR comment | **Not in the first build** | Needs "Pull requests: write" on the App, which also allows merging. A GitHub App cannot grant "comment but not merge", so this waits for a permission that can |
| GitHub request review | **No** | Same permission problem |
| GitHub re-run CI | **No** in GL2; revisit | Needs "Actions: write", and a re-run can change deployment state. atc's own CI handling is the place |

**Guards common to every write, if GL2 is adopted:**
- a Settings switch "Allow writes", off by default, and a separate sign-in consent (write permission is requested only after the switch is on; turning it off deletes that token and asks for a read-only one);
- one click shows the exact target (repository and number, or issue key) and the exact text, and a second click sends. "Send" is never the keyboard default;
- one request per confirmation, no automatic retry of a write; a failed write shows the error;
- a local line "sent comment on <issue key>" with no body and no token, for the SUPERVISOR's own reference;
- atc is unchanged: the app still sends only GET and SSE to atc.

### 11.5 Auth, tokens and the budget

**GitHub: a GitHub App with device flow (recommended), not a PAT, not an OAuth App.**
- **Why:** device flow needs no client secret and no redirect handler, so the bundle holds nothing that could be copied out. The user token expires in 8 hours and is refreshed, so a stolen token is short-lived. Permissions are fine-grained and limited to the repositories where the SUPERVISOR installs the App, unlike an OAuth App's broad `repo` scope.
- **Permissions for GL1, all read only:** Metadata, Pull requests (read), Commit statuses (read), Checks (read). No write permission in GL1.
- **Separate from atc's token.** The App has its own identity. The docs read do not show that this gives a separate rate bucket, so the budget below assumes it does not.
- **Fallback:** a fine-grained PAT typed into Settings and stored by the same Keychain code. Not recommended: it lives for weeks or months.

**Linear: OAuth 2 with PKCE (recommended), not a personal API key.**
- **Why:** PKCE needs no client secret; scope `read` is enough for GL1 (a personal API key is full access by design); tokens are revocable and expire in 24 hours.
- **Flow:** `ASWebAuthenticationSession` (public API) for the authorization, a custom URL scheme for the redirect. The SUPERVISOR registers the Linear OAuth application and puts its client ID in Settings.
- **Fallback:** a personal API key in the Keychain. Not recommended: it cannot be limited to read, and its limits are lower.
- **GL2 scope (D12d).** A comment alone needs only `comments:create`. A state move is an issue update, and the documented scopes (`read`, `write`, `issues:create`, `comments:create`, `admin`) have no narrower one for it, so GL2 asks for `write`. **Verify in the scope docs at GL2 start.** `write` would also allow deleting, archiving and editing issues; the app never sends those, because `WritePolicy` has no such case (tested), but the token could. So the `write` token is requested only after "Allow writes" is turned on, it is a separate Keychain item from the `read` token, and turning the switch off revokes it through Linear's revoke endpoint and deletes it. Reads keep using the `read` token.

**Keychain.**
- Generic password items, services `dev.atc.annunciator.github` and `dev.atc.annunciator.linear`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable` false. Access and refresh tokens are separate items.
- Never in a file, `UserDefaults`, the plist, the repository, a log, a crash report, a notification or an environment variable. The `SecretStore` protocol in ATCCore has an in-memory fake for tests; the app's Keychain implementation is small.
- **A locally built, ad-hoc signed app changes its code signature on every rebuild.** macOS may then ask for the login password before the new build reads the old items. That is a nuisance, not a hole; the alternative (a shared access group) needs a real Developer ID (D2). **PILOT'S DISCRETION:** accept the prompt, document it in the checklist, revisit if it gets in the way (D12i).

**Sign out and revoke.**
- **Sign out** deletes both Keychain items and the in-memory ETags and lists, and stops all polling. It is always available in Settings and needs no network.
- **Revoke:** Linear has a revoke endpoint, and sign-out calls it. For GitHub, revoking a token through the API is believed to need the client secret, which the app must not hold, so the app can't revoke GitHub tokens itself: Settings links to the page where the SUPERVISOR revokes or uninstalls the App in the browser. The 8-hour token life is the compensating control. **GL0 check (2026-10-01):** the GitHub docs pages read confirm that a device-flow user token refreshes with `client_id` and the refresh token only (no `client_secret`), and that device flow needs no secret. They do not say how `DELETE /applications/{client_id}/token` is authenticated; it is believed to need the client secret, so the app does not call it and Settings links to the revoke page. Linear's docs confirm PKCE with an optional secret, refresh by `refresh_token`, and `POST /oauth/revoke` with a `token` field (the app uses it on sign-out). Still open for GL1: the shared rate bucket and `304` not counting.
- **GL1a check (2026-10-01), the two open points, read in the GitHub docs.**
  - *Shared bucket: confirmed.* "Primary rate limits for GitHub App user access tokens (as opposed to installation access tokens) are dictated by the primary rate limits for the authenticated user. This rate limit is combined with any requests that another GitHub App or OAuth app makes on that user's behalf and any requests that the user makes with a personal access token." The limit is per user (5,000 an hour), not per token. So the 1,000 an hour cap stays at 20 percent of the user's budget, shared with atc's `gh` and LOGBOOK.
  - *`304`: documented as free.* The REST best-practices page says a conditional request "does not count against your primary rate limit if a `304` response is returned and the request was made while correctly authorized with an `Authorization` header". `RateBudget` therefore counts a `304` as zero; every other status counts one. The docs say nothing about secondary limits for a `304`, and the secondary limits are far above the app's rate. The first Mac check confirms it on the wire: `x-ratelimit-remaining` before and after a `304`.
- **GL1a choices (ATC-247, PILOT'S DISCRETION where marked).**
  - *REST, not one GraphQL query.* Per refresh and repository: one list request, `GET /repos/{o}/{r}/pulls?state=open&per_page=50` (up to 5 pages), free when it answers `304`. A CI rollup (`GET …/commits/{sha}/check-runs` and `…/status`, two requests) only for a PR whose `updated_at` or head SHA changed, that has none yet, or whose last rollup still had an unfinished run (PILOT'S DISCRETION: CI usually finishes without moving the PR's `updated_at`, so a rollup that was pending is asked again, and only then). `GET /user` once per sign-in, for the review-requested filter. GraphQL would need one query with `statusCheckRollup` per PR; its points are not documented to be cheaper than the REST requests above, and REST has free `304`s.
  - *Cost.* With the window open and nothing changing, a repository costs 0 counted requests per minute (a `304`), at most 60 an hour when its list changes every poll. A PR with a check still running costs 2 a minute (check runs and status, both with `If-None-Match`, free only while the answer is unchanged). Idle repositories cost nothing but their `304`s; the worst case is many PRs with long-running checks open at once, where about ten of them would use the 1,000 in under an hour. The cap then stops the app and the popover says so, instead of spending atc's share. The first Mac check measures what an open window really costs per hour and records it in the PR.
  - *Review state* is only "who is asked to review" (`requested_reviewers`), which is on the list for free. Submitted reviews and mergeability are not on the list response and would be one more request per PR; they are left out of GL1a.
  - *Token refresh is wired here.* The access token's expiry is stored beside the tokens (Keychain item `expiry`, so sign-out deletes it). The token is refreshed 5 minutes before it expires and once after a 401, with `client_id` and the refresh token only; the new refresh token replaces the old one (they are single use, so one actor does it). A failed refresh shows "다시 로그인이 필요합니다" and stops all requests until the sign-in changes.
  - *"Decide in atc ↗"* opens the atc window at `#strips`, where atc lists PRs per team. atc's PR drawer (`#pr/<AIRPORT>/<n>`) needs atc's airport name, which the app does not have (PILOT'S DISCRETION).
  - *`LinkRoute.workLink`* (new) lets a Work row open only `https` on `github.com` or `linear.app` without user info or a port other than 443; anything else is dropped. `LinkRoute.decide` itself is unchanged.
- **Shared Mac, or a copied app:** items are this-device only and bound to the login keychain and the code signature, so another macOS user or a copied bundle can't read them without the SUPERVISOR's login password. A copy of the app contains code and no secret. For a shared login session, locking the screen is the real control, and the checklist says so.

**Polling and budget** (both sources):
- **Only while looked at.** Fetch when the popover or the Work window opens and poll while either is open. No background polling. So there are no GitHub or Linear notifications, which is why they are deferred in 11.3.
- **Interval:** 60 s for each source while open (PILOT'S DISCRETION), plus a manual Refresh.
- **Conditional requests:** GitHub list calls send `If-None-Match`. ETag and body stay in memory, not on disk.
- **Cost rules:** one REST list per repository (open PRs), plus a CI rollup per PR only when its `updated_at` changed. One GraphQL query for the lot is an alternative that GL0 prices against the points budget. Linear queries are filtered to the configured teams, ask only for the fields shown, and page with `first` of 50 or less, far under 10,000 points.
- **Cap:** the app stops itself at 1,000 GitHub requests an hour (20 percent of 5,000), so atc's LOGBOOK spend keeps its room. The cap is a value in ATCCore (`RateBudget`) and is shown in Settings.
- **Back-off:** on 403 or 429 wait for `retry-after`, or until `x-ratelimit-reset` when `x-ratelimit-remaining` is 0; with no header, 60 s doubling to 15 minutes with jitter (the `Reconnect` schedule can be reused). Linear signals its limit as HTTP 400 with `RATELIMITED`: treat it the same. The popover says "GitHub rate limited, retrying at <time>".
- **Hybrid, for comparison (D12b).** Read the lists from atc and call GitHub or Linear only for actions.
  - *For:* one rate budget; no read tokens in the app; atc's decisions and the lists never disagree.
  - *Against:* atc's snapshot carries only what atc tracks, so each new field is a server change; and it does not give the app a view of its own.
  - **Recommendation:** direct, as chosen, with the list models in ATCCore so the source can be swapped.

### 11.6 Code layout and tests

```
Sources/ATCCore/Work/
  GitHubModels.swift     Codable: PullRequest, CheckRollup, ReviewState (raw GitHub values)
  GitHubRequests.swift   request building: URLs, headers, query, If-None-Match; no networking
  GitHubParse.swift      response parsing, Link header paging, rate-limit headers
  LinearModels.swift     Codable: Issue, WorkflowState, Team
  LinearRequests.swift   GraphQL query strings and variables, PKCE verifier and challenge
  RateBudget.swift       the hourly cap, back-off schedule, retry-after parsing
  ETagCache.swift        in-memory, keyed by URL
  WritePolicy.swift      WriteAction (closed list), the forbidden cases, confirm text
  SecretStore.swift      protocol, in-memory fake, key names
  Redact.swift           strips tokens and Authorization values from any string
  WorkPanel.swift        popover lines and window rows from the models (counts, labels)
Sources/Annunciator/Work/
  KeychainStore.swift    SecretStore on the Keychain
  AuthSession.swift      GitHub device-flow screen; Linear ASWebAuthenticationSession
  WorkTransport.swift    URLSession calls: the app's only GitHub and Linear network code
  WorkWindow.swift       AppKit list window
Tests/ATCCoreTests/Fixtures/   scrubbed JSON (GitHub and Linear responses)
```

- **Fixtures** are real-shaped responses with names, emails, org and repository names, URLs and IDs replaced by neutral values (`octo`, `repo-a`, `ISS-1`, `user-1`), and no token or `Authorization` header. A Linux test scans every fixture for `@`, `ghp_`, `github_pat_`, `lin_` and `Bearer`.
- **Tests on Linux:** request building (URL, headers, `If-None-Match`), parsing every fixture, paging, rate-limit headers, back-off, the cap, PKCE (verifier length and characters; challenge is the base64url of the SHA-256), `WritePolicy` (no merge case, no delete, the confirm text), `Redact`, `WorkPanel` counts.
- **`FORBIDDEN_MACROS`** is unchanged: the Work window is AppKit only.
- **A new Mac checklist** (`docs/mac-checklist-gl.md`, written in GL0) covers what CI can't see: the device-flow code screen, the browser round trip for Linear, the Keychain prompt after a rebuild, sign-out leaving no item (`security find-generic-password` finds none), the window, and a forced rate limit.

### 11.7 Security review items (`Risk: Security`)

Each item is a check for the reviews of GL0, GL1 and GL2.

| Item | Check |
|---|---|
| Token storage | Only the Keychain, this-device-only, no sync. A grep of the app source for `UserDefaults`, `write(to:`, `print`, `NSLog` and `os_log` finds no token |
| Scope creep | GL1 permissions are the read-only list in 11.5. A new permission or scope needs a PR that changes this section and a SUPERVISOR decision |
| Logging | Every logged string and every error shown in the UI goes through `Redact`; response bodies are never logged; URLs are logged without query strings; the ETag cache is memory only |
| A shared Mac or a copied app | See 11.5. The bundle holds no secret, and there is no client secret anywhere |
| Write guard | `WritePolicy` is the only path to a write; the tests in 11.6 fail if a merge, delete or bulk case appears |
| New trust boundary | The app gains outbound TLS connections to two third parties. It accepts no inbound connection (device flow polls; Linear's redirect is a URL scheme that accepts only a `code` with a matching pending `state`) |
| URL scheme | The handler ignores a callback without a pending `state` and never opens a URL taken from it |
| Web content | Titles and names from GitHub and Linear are untrusted: shown as plain text, never as HTML or markdown, and a link opens only if its host is `github.com` or `linear.app` (`LinkRoute.decide` gains these two hosts, in ATCCore with tests) |
| Public repo | No org names, emails, repository names or client IDs in code, docs, fixtures, the bundle or the bundle ID |
| atc's budget | The cap and back-off in 11.5: the app can't push atc's LOGBOOK into a rate limit |
| Network outside atc | The non-goal "no network use beyond the configured atc URL" would become "atc, and the two API hosts once signed in". Nothing is contacted before sign-in, and there is no telemetry |

### 11.8 Implementation order

| Step | What | Needs | Size |
|---|---|---|---|
| GL0 | **Auth and Keychain, no data.** `SecretStore`, `Redact`, PKCE and device-flow helpers in ATCCore with tests. In the app: the Keychain store, Settings sections for GitHub and Linear (client ID, sign in, sign out), the GL Mac checklist. The SUPERVISOR registers the GitHub App and the Linear OAuth application and enters the client IDs in Settings; team sessions do not create them. The three "verify" points in 11.1 and 11.5 are checked here | D12 answered (11.9) | M |
| GL1 | **Read-only lists.** Models, requests, parsing, `RateBudget`, `ETagCache`, `WorkPanel`; the popover lines; the Work window; `LinkRoute` hosts | GL0 | L (split: GitHub, then Linear) |
| GL2 | **Linear writes.** A comment and a state move (Backlog, Todo, Canceled) behind `WritePolicy` and "Allow writes", with the separate `write` token (11.5). GitHub writes only after a separate decision | GL1 | M |
| GL3 | Later, by use: review and inbox views, a notification, a Work badge | GL1, two weeks of use | — |

### 11.9 Decisions (SUPERVISOR)

| # | Question | Decision |
|---|---|---|
| **D12** | **Decided 2026-09-30 (by the SUPERVISOR):** the app calls the GitHub and Linear APIs directly with its own tokens in the Keychain. This reverses the non-goal "no network use beyond the atc URL", Principle 2 and D3 for these two hosts only. atc stays read only (N5 unchanged) | — |
| D12a | What is shown | **Decided 2026-10-01:** PRs and Linear issues by state: counts in the popover, two lists in a Work window. Notifications and the Linear inbox later (11.3) |
| D12b | Direct or hybrid | **Decided 2026-10-01:** Direct, with swappable models (11.5) |
| D12c | Merge from the app | **Decided 2026-10-01:** Never. LANDING only (11.2, 11.4) |
| D12d | Other writes | **Decided 2026-10-01, differs from the recommendation:** none in GL1. In GL2 a Linear comment **and a Linear state move** (Backlog, Todo, Canceled only), both off by default behind "Allow writes", with a separate `write` token (11.4, 11.5). No GitHub writes until there is a permission that can't merge |
| D12e | GitHub auth | **Decided 2026-10-01:** A GitHub App with device flow, read-only permissions, installed on the AIRPORT repos only; not a PAT |
| D12f | Linear auth | **Decided 2026-10-01:** OAuth 2 with PKCE, scope `read`; not a personal API key. GL2 adds a separate `write` token only while "Allow writes" is on (D12d, 11.5) |
| D12g | Budget | **Decided 2026-10-01:** Only while the popover or window is open; 60 s; ETags; stop at 1,000 GitHub requests an hour |
| D12h | Who creates the GitHub App and the Linear OAuth application | **Decided 2026-10-01:** The SUPERVISOR, by hand; client IDs entered in Settings, never committed |
| D12i | Keychain prompt after each local rebuild | **Decided 2026-10-01:** Accept and document it, unless it gets in the way (11.5) |
| D12j | Work window name and shortcut | **Decided 2026-10-01:** "Work", ⌘⇧W (PILOT'S DISCRETION) |

### 11.10 Risks

| Risk | Mitigation |
|---|---|
| A second client eats atc's GitHub budget and slows LOGBOOK and MCC | The 20 percent cap, ETags, poll only while open, back-off (11.5); the first GL1 check measures what a session costs |
| The app becomes a way to merge around LANDING | 11.2 and the `WritePolicy` test |
| Tokens leak through logs, crash reports, a screenshot or the repo | Keychain only, `Redact`, no screenshots (`CLAUDE.md`), the fixture scan |
| The Work window drifts from atc's FLIGHT and PR drawers | Raw facts only, small lists, a link to atc for decisions; hybrid stays as a fallback |
| The GL2 Linear `write` token can do more than the app's two writes (delete, archive, edit) | `WritePolicy` is the only write path (tested); the `write` token exists only while "Allow writes" is on and is revoked when it goes off; reads use the `read` token (11.5) |
| The app ends up with more power than the SUPERVISOR expects | Read only first, each scope a separate decision, a review item per permission |
| Team sessions can't compile or see the app | As elsewhere: logic in ATCCore with Linux tests, the GL checklist for the Mac |
| Claims from the docs turn out wrong (shared bucket, `304` not counted, revoke needs a secret) | Each is marked "verify" in 11.1 and 11.5; GL0 checks them before GL1 |
