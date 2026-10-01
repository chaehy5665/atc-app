// SPDX-License-Identifier: Apache-2.0
import AppKit

/// The main menu. It only shows while the atc window is open (the app is then a regular app),
/// but it must exist so the web UI's fields get Cmd-C, Cmd-V and the rest.
enum MainMenu {
    @MainActor
    static func build(settings: Selector, duty: Selector, work: Selector, target: AnyObject, window: AtcWindowController) -> NSMenu {
        let main = NSMenu()

        // App menu: About, Settings…, Quit.
        let app = submenu(main, title: "ANNUNCIATOR")
        app.addItem(item("About ANNUNCIATOR", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", target: NSApp))
        app.addItem(.separator())
        app.addItem(item("Settings…", settings, ",", target: target))
        app.addItem(.separator())
        app.addItem(item("Quit ANNUNCIATOR", #selector(NSApplication.terminate(_:)), "q", target: NSApp))

        // Edit: nil targets go up the responder chain to the web view.
        let edit = submenu(main, title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        let redo = item("Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))

        // View: handled by the window controller, enabled only while the atc window is key.
        let view = submenu(main, title: "View")
        view.addItem(item("Reload", #selector(AtcWindowController.reloadPage), "r", target: window))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(AtcWindowController.actualSize), "0", target: window))
        view.addItem(item("Zoom In", #selector(AtcWindowController.zoomIn), "+", target: window))
        view.addItem(item("Zoom Out", #selector(AtcWindowController.zoomOut), "-", target: window))

        // Window: Close (Cmd-W), Minimize.
        let win = submenu(main, title: "Window")
        win.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        win.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        // D6: the same route as the popover's DUTY row.
        win.addItem(.separator())
        win.addItem(item("DUTY", duty, "d", target: target))
        // ATC-247: the PR list window.
        let workItem = item("Work", work, "w", target: target)
        workItem.keyEquivalentModifierMask = [.command, .shift]
        win.addItem(workItem)
        NSApp.windowsMenu = win

        return main
    }

    @MainActor
    private static func submenu(_ main: NSMenu, title: String) -> NSMenu {
        let holder = NSMenuItem()
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    @MainActor
    private static func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target
        return i
    }
}
