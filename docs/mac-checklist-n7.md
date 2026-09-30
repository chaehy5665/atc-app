<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (N7)

Run after the N7 PR is merged. The app target (AppKit, WebKit) was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots.

1. `Tools/build-app.sh` succeeds, including the icon step (`swift Tools/make-icon.swift`, `iconutil`). Paste errors if not. The Finder and the Dock show a lamp icon (dark panel, amber lamp, plane), not the generic one.
2. Click a lamp in the popover: the popover closes and the atc window opens on the right tab. Click a second lamp with another tab: the tab switches without a page reload (the page does not flash, scroll or filters stay).
3. Quit and relaunch, open the window: the frame (size and place) is the same. First ever open is about 1280×820, centred, and it will not shrink below about 900×600.
4. The Dock icon and Cmd-Tab entry exist only while the window is open, and go away when it is closed. The Dock badge shows the same number as the menu bar title while open.
5. Window title follows the page (`document.title`), "atc" when it has none.
6. Close the window, then check the atc side (or Activity Monitor): no second `/api/events` stream stays open and no web content process is left. Reopen: the page loads again.
7. Menu bar (while the window is key): app menu (About, Settings…, Quit); Edit; View: Reload ⌘R, Actual Size ⌘0, Zoom In ⌘+, Zoom Out ⌘-; Window: Close ⌘W, Minimize ⌘M. Cmd-C and Cmd-V work in a web field (for example a DISPATCH text box). With only the popover open (no atc window), ⌘R in the popover still refreshes and does not reload the page.
8. A GitHub or Linear link inside the atc page opens the default browser, not the window. A link that has `target=_blank` too.
9. Stop the SSH forward: within about a minute the window shows the overlay with `atc 연결 안 됨 — SSH 포워딩을 확인하세요` (no WebKit error page). Start it again: the overlay goes and the page reloads once. Open the window while the forward is down: the overlay shows at once.
10. Approve something in DISPATCH from the window: it works (the page sends `Origin: http://localhost:7700`), including any confirm or alert box the page raises.
11. RADIO audio plays in the window without a click first.
12. Settings → **atc 열기** = 브라우저: a lamp opens the browser. Back to 앱 창: it opens the window. With 앱 창, ⌥-click on a lamp opens the browser once.
13. A notification click opens the tab in the window.
14. Settings the web UI keeps (theme, tab) survive quitting the app.
