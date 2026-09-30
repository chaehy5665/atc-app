// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ATCCore
import SwiftUI

/// Status item (AppKit) plus a SwiftUI popover. Layout and system calls only.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model, openSettings: { [weak self] in self?.showSettings() }))

        model.onFeedChange = { [weak self] in self?.render() }
        render()
        model.start()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let title = model.title
        button.setAccessibilityLabel(title.plain)
        switch title.symbol {
        case .unreachable:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "✈ —", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        case .light(let light):
            let name = light == .off ? "airplane" : "circle.fill"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = tint(light)
            button.attributedTitle = NSAttributedString(string: title.text.isEmpty ? "" : " " + title.text)
        }
    }

    private func tint(_ light: MasterLight) -> NSColor? {
        switch light {
        case .warning: return .systemRed
        case .caution: return .systemOrange
        case .off: return nil
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "ANNUNCIATOR Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
