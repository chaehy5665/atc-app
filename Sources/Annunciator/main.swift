// SPDX-License-Identifier: Apache-2.0
import AppKit

// Top-level code is nonisolated in the Command Line Tools toolchain; AppKit needs the main actor.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
