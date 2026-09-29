<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Changelog

## [Unreleased]

### Added

- N0 toolchain: `Package.swift` (swift-tools 5.9, macOS 14, no dependencies) with `ATCCore` (Foundation only, one pure function and tests) and a hello `Annunciator` status item app (`LSUIElement`, Quit, debug items "Test notification" and "Launch at login").
- `Tools/test-linux.sh`: builds and tests `ATCCore` in the official `swift` Docker image, pinned by tag and digest.
- `Tools/build-app.sh`: builds `Annunciator.app` on the Mac, ad-hoc signs it and installs it to `~/Applications`.
- `docs/mac-checklist.md`: what the SUPERVISOR checks on the Mac after N0 merges.
