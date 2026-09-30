// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// The one place every click-through goes: notification click, MASTER light, lamps, pending rows,
/// NEEDS YOU chips and "Open atc ↗". N4 opens the browser; N7 (the atc window) replaces only this body.
enum LinkOpener {
    @MainActor
    static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
