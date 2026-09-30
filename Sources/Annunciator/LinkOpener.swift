// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ATCCore

/// The one place every click-through goes: notification click, lamps, pending rows, NEEDS YOU chips
/// and "Open atc ↗". Since N7 the atc origin opens in the atc window and everything else, or ⌥-click,
/// or the Settings switch "browser", opens in the default browser. The decision is `LinkRoute` in ATCCore.
enum LinkOpener {
    /// Set once at launch (AppDelegate).
    @MainActor static weak var model: AppModel?
    @MainActor static var window: AtcWindowController?

    @MainActor
    static func open(_ url: URL?) {
        guard let url else { return }
        guard let model, let window else {
            NSWorkspace.shared.open(url)
            return
        }
        let option = NSEvent.modifierFlags.contains(.option)
        switch LinkRoute.decide(url: url, base: model.baseURL, preference: model.linkPreference, modifier: option) {
        case .window(let fragment): window.show(fragment: fragment)
        case .browser(let target): NSWorkspace.shared.open(target)
        }
    }
}
