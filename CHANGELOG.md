<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog

## [Unreleased]

### Added

- N2 `ATCCore`: Codable models for supervisor alerts, the `alert` SSE event and the `/api/supervisor-summary` `v: 1` body (an unknown `v` is a typed error); an incremental SSE parser; reconnect backoff (1 s to 30 s, ±20 % jitter) and a 60 s dead-connection watchdog; MASTER light state, lamps grouped by level, the seen-key diff for new WARNING and CALL alerts, and `HH:MMZ` formatting; a thin read-only URLSession client (GET and the SSE stream). 47 tests, run by `Tools/test-linux.sh`.
- N0 toolchain: `Package.swift` (swift-tools 5.9, macOS 14, no dependencies) with `ATCCore` (Foundation only, one pure function and tests) and a hello `Annunciator` status item app (`LSUIElement`, Quit, debug items "Test notification" and "Launch at login").
- `Tools/test-linux.sh`: builds and tests `ATCCore` in the official `swift` Docker image, pinned by tag and digest.
- `Tools/build-app.sh`: builds `Annunciator.app` on the Mac, ad-hoc signs it and installs it to `~/Applications`.
- `docs/mac-checklist.md`: what the SUPERVISOR checks on the Mac after N0 merges.
