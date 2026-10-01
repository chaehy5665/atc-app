// SPDX-License-Identifier: Apache-2.0
import AppKit
import ATCCore
import Network
import SwiftUI

/// Status item (AppKit) plus a SwiftUI popover. Layout and system calls only.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popoverState = PopoverState()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private lazy var atcWindow = AtcWindowController(model: model)
    private lazy var work = WorkModel(signIn: model.signIn)
    private lazy var workWindow = WorkWindowController(work: work, model: model)
    private var activity: NSObjectProtocol?
    private let pathMonitor = NWPathMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(
            rootView: PopoverView(
                model: model, state: popoverState, work: work,
                openSettings: { [weak self] in self?.showSettings() }, openWork: { [weak self] in self?.showWork() }))
        // The popover follows the content height (PanelLayout: 240...640 pt).
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        atcWindow.onWillShow = { [weak self] in self?.popover.performClose(nil) }
        atcWindow.keepsAppRegular = { [weak self] in self?.workWindow.isOpen ?? false }
        workWindow.onWillShow = { [weak self] in self?.popover.performClose(nil) }
        workWindow.isAtcOpen = { [weak self] in self?.atcWindow.isOpen ?? false }
        LinkOpener.model = model
        LinkOpener.window = atcWindow
        NSApp.mainMenu = MainMenu.build(
            settings: #selector(openSettings), duty: #selector(openDuty), work: #selector(openWork), target: self, window: atcWindow)

        model.onFeedChange = { [weak self] in
            self?.render()
            if let self { self.atcWindow.feedChanged(self.model.feed) }
        }
        render()
        model.start()
        keepAwakeForAlerts()
    }

    /// The app has no window, so keep App Nap from pausing the feed, and reconnect after wake or a network change.
    /// The activity still lets the Mac sleep.
    private func keepAwakeForAlerts() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Listening for atc alerts")
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.reconnectNow() }
        }
        var first = true  // the monitor reports the current path once at start; that is not a change
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if first { first = false; return }
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.reconnectNow() } }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dev.atc.annunciator.path"))
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let title = model.title
        button.setAccessibilityLabel(title.accessibility)
        switch title.symbol {
        case .unreachable:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "✈ —", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        case .light(let light):
            button.image = lightImage(light)
            button.contentTintColor = nil
            button.attributedTitle = NSAttributedString(string: title.text.isEmpty ? "" : " " + title.text)
        }
    }

    /// Lit: a coloured circle that is not a template, so the menu bar keeps its colour.
    /// Off: the plain airplane as a template, so it follows the light or dark menu bar.
    private func lightImage(_ light: MasterLight) -> NSImage? {
        let color: NSColor
        switch light {
        case .warning: color = .systemRed
        case .caution: color = .systemOrange
        case .off:
            let plane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)
            plane?.isTemplate = true
            return plane
        }
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        let circle = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        circle?.isTemplate = false
        return circle
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

    /// The DUTY row is read only while the popover is open (D6).
    /// The PR list is read on the same terms (ATC-247): while the popover or the Work window is open.
    func popoverWillShow(_ notification: Notification) {
        model.setDutyPolling(true)
        work.setViewing("popover", true)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setDutyPolling(false)
        work.setViewing("popover", false)
    }

    /// Closing the atc window leaves the menu bar item running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openSettings() { showSettings() }

    /// Window > DUTY (⌘D): the atc window at `#duty`.
    @objc private func openDuty() {
        LinkOpener.open(ATCLink.url(base: model.baseURL, link: "#" + DutyLamp.fragment))
    }

    /// Window > Work (⌘⇧W) and the popover's GitHub line.
    @objc private func openWork() { showWork() }

    private func showWork() { workWindow.show() }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, form: SettingsForm(), forward: model.forward, signIn: model.signIn, work: work)))
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
