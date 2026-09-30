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
- **Licences.** atc is MIT; this repository is GPL-3.0-or-later (D8), and the two talk only over HTTP. Vorssaint is GPL-3.0, so its code may be reused here, keeping its copyright notice and naming the source file and commit at the top of the file (`CLAUDE.md` "라이선스"). Prefer small, understood pieces over whole files.

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

- No writes from the app's own code: no ACK, approve, reject or switch sent by Swift. That needs an auth design first (section 7, N5). The atc web UI hosted in the atc window (N7) is the browser client in a different frame and keeps the browser's access model (section 10.3, D9).
- No new server state, no telemetry, and no network use beyond the configured atc URL.
- No per-Mac Claude usage reading (the Vorssaint feature). atc FUEL already covers the host.

## 3. Principles

1. **The server decides, the app shows.** Levels, texts, counts, "what is pending" and the title numbers come from the server as data. The app doesn't re-derive atc rules, so the browser, the SwiftBar plugin and the app always agree.
2. **Read only until there is an access model.** Adding writes means adding real authentication for SUPERVISOR routes. That is a separate design with `Risk: Security`, not a side effect of the app.
3. **A pure core tested on Linux.** Everything that isn't AppKit or SwiftUI (decoding, SSE parsing, reconnect backoff, seen-key diff, formatting) lives in a Foundation-only target. Team sessions test it in the `swift` Docker image on the host.
4. **Built on the Mac, not shipped as a binary.** v1 has no signed download. The SUPERVISOR builds from the checkout with one script, which avoids Developer ID, notarization and CI secrets.
5. **The public repo stays clean.** No screenshots, and no real names or emails in code or bundle IDs. Reused GPL-3.0 code keeps its notices.
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
- It never opens a port and never needs the host's LAN address. It doesn't manage the SSH tunnel either: the launchd agent does that, and the app only reports "unreachable".

## 6. Testing and landing

- **ATCCore:** `Tools/test-linux.sh` runs `swift build` and `swift test` in a pinned `swift` Docker image on the atc host, from any team STAND.
- **App target:** team sessions can't compile it. The PR says so and lists what to look at. The SUPERVISOR runs `Tools/build-app.sh` on the Mac after merge.
- An optional macOS CI job (N6) can add a compile check later.
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
| N6 | Later, by use: a notch view, a separate FUEL status item, an update check against GitHub Releases, a macOS CI compile job | N3 | varies | — |
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
| The window keeps a second full SSE stream (340 KB snapshots) open over the SSH forward when nobody looks | The web view is released when the window closes; reopening reloads it (section 10.2) |

## 9. Decisions (SUPERVISOR)

| # | Question | Proposal |
|---|---|---|
| D1 | App name | ANNUNCIATOR (the cockpit's MASTER WARNING/CAUTION panel) |
| D2 | Distribution | Build on the Mac with `Tools/build-app.sh`; no signed download for now |
| D3 | Writes from the app | Not in v1. Revisit after a week of use with a separate auth design (N5) |
| D4 | macOS CI compile job | Later (N6), in this repository |
| D5 | SwiftBar plugin after the app | Keep it as the documented fallback, frozen, reading the same summary |
| D6 | Minimum macOS | 14, unless the SUPERVISOR's Mac is newer and a newer API saves real work |
| D7 | Voice in the app | Yes (N4): play the host-rendered WAV; the radio effect stays in the browser for now |
| D8 | Repository and licence | **Decided 2026-09-29:** a separate public repository `atc-app`, GPL-3.0-or-later. atc stays MIT |
| D9 | Writes through the atc window | The web UI in the atc window may write exactly as it does in a browser tab (localhost plus the Origin check). The app's Swift code still sends no writes, and it adds no JavaScript bridge. A token (N5) is still what native writes would need |
| D10 | Where click-throughs open after N7 | The atc window by default; a Settings switch goes back to the browser; ⌥-click always opens the browser |
| D11 | Order against N4 | **Decided 2026-09-30:** N4 ships first and opens the browser, but routes every click-through through one link opener; N7 swaps that opener for the window |

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
- Links to GitHub, Linear or anything else, `target=_blank` and `window.open` go to the default browser.
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
