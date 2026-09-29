// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ATCCore
import ServiceManagement
import UserNotifications

/// N0 hello app: a status item plus two debug items for the Mac checklist.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let loginItem = NSMenuItem(
        title: "Launch at login (debug)", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = StatusTitle.text()

        let menu = NSMenu()
        menu.delegate = self
        let test = NSMenuItem(
            title: "Test notification (debug)", action: #selector(testNotification), keyEquivalent: "")
        test.target = self
        menu.addItem(test)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        refreshLoginItem()
    }

    // Show banners even while the app counts as active.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshLoginItem() }

    @objc private func testNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog("ANNUNCIATOR notification authorization granted=%d error=%@",
                  granted ? 1 : 0, String(describing: error))
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "ANNUNCIATOR"
            content.body = "Test notification"
            let request = UNNotificationRequest(identifier: "n0-test", content: content, trigger: nil)
            center.add(request) { error in
                NSLog("ANNUNCIATOR notification add error=%@", String(describing: error))
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("ANNUNCIATOR launch at login error: %@", String(describing: error))
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : .off
        loginItem.title = "Launch at login (debug): \(Self.describe(status))"
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "requires approval"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }
}
