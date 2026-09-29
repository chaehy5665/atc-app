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
  - Each item opens the right atc tab in the browser.
- **macOS notifications** for new WARNING and CALL alerts, with the tone and, if VOICE is on, the voice callout WAV from the host.
- Graceful when atc is unreachable: a grey light, "atc 연결 안 됨 — SSH 포워딩", and it reconnects by itself.
- Launch at login. No Dock icon.

**Non-goals for v1**

- No writes: no ACK, approve, reject or switch from the app. That needs an auth design first (section 7, N5).
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
| N5 | **Design only:** a SUPERVISOR token for write routes (ACK, approve, reject) that the app would hold in the Keychain; what it protects, how it rotates, how it is revoked. Not built until adopted | D3 | — | — |
| N6 | Later, by use: a notch view, a separate FUEL status item, an update check against GitHub Releases, a macOS CI compile job | N3 | varies | — |

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
