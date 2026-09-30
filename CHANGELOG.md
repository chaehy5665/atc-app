<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog

## [Unreleased]

### Added

- N3 app v1: menu bar MASTER light (red WARNING, amber CAUTION, count, then `5h 45% · 7d 55%`; grey `✈ —` while atc is unreachable, with automatic reconnect); a SwiftUI popover with LAMPs by level (click opens the atc tab), pending DISPATCH, HUMAN CHECK, tool approvals and SCHEDULE, the last RTS as `HH:MMZ`, ACCOUNT FUEL windows, working AIRCRAFT and control sessions with NEEDS YOU; Settings for the atc URL (UserDefaults) and launch at login. `ATCCore` gains the presentation rules (`StatusBarTitle`, `PanelContent`, `ATCLink`, `ATCSettings`, `FuelFormat`) and `LiveFeed` (SSE with backoff and the 60 s watchdog). `docs/mac-checklist-n3.md` lists what to check on the Mac.

### Fixed

- The MASTER light is drawn as a coloured, non-template circle (`systemRed` WARNING, `systemOrange` CAUTION) instead of a tinted template image, which the menu bar showed black; the light-off airplane stays a template (ATC-164).
- The menu bar count is `warning + caution` then ` +advisory`, as in atc's SwiftBar `titleOf` and the number at the top of the atc screen (it used to add the CAUTION count to WARNING only when the light was amber, and left advisory out). Parts are separated by one space. The accessibility label reads `WARNING 2, CAUTION 23, advisory 13, 5h 16% · 7d 66%` (ATC-164).
- The app target builds with Command Line Tools only (ATC-163): `main.swift` runs inside `MainActor.assumeIsolated`; Settings keeps its form state in an `ObservableObject` (`SettingsForm`) instead of `@State`. `Tools/test-linux.sh` fails if `Sources/Annunciator` uses `@State` or `#Preview`.
- The summary model reads `pending.schedule` (ATC-153 as merged, ATC-162). FUEL window names are atc's `five_hour` and `seven_day`, shown as `5h` and `7d`.

- N2 `ATCCore`: Codable models for supervisor alerts, the `alert` SSE event and the `/api/supervisor-summary` `v: 1` body (an unknown `v` is a typed error); an incremental SSE parser; reconnect backoff (1 s to 30 s, ±20 % jitter) and a 60 s dead-connection watchdog; MASTER light state, lamps grouped by level, the seen-key diff for new WARNING and CALL alerts, and `HH:MMZ` formatting; a thin read-only URLSession client (GET and the SSE stream). 47 tests, run by `Tools/test-linux.sh`.
- N0 toolchain: `Package.swift` (swift-tools 5.9, macOS 14, no dependencies) with `ATCCore` (Foundation only, one pure function and tests) and a hello `Annunciator` status item app (`LSUIElement`, Quit, debug items "Test notification" and "Launch at login").
- `Tools/test-linux.sh`: builds and tests `ATCCore` in the official `swift` Docker image, pinned by tag and digest.
- `Tools/build-app.sh`: builds `Annunciator.app` on the Mac, ad-hoc signs it and installs it to `~/Applications`.
- `docs/mac-checklist.md`: what the SUPERVISOR checks on the Mac after N0 merges.
