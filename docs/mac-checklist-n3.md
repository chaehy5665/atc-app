<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (N3)

The SUPERVISOR runs this on the Mac after the N3 PR is merged. The app target (AppKit, SwiftUI) was written on Linux and **has not been built or run on a Mac**. Expect a compile error or two; report the lines.

Report in words. No screenshots (public repository).

Prerequisites: the SSH forward is up, and the atc on the other end serves `/api/supervisor-summary` (`curl -s localhost:7700/api/supervisor-summary` returns JSON with `"v":1`).

1. `git pull && Tools/build-app.sh` succeeds, twice in a row. If it fails, paste the compiler errors.
2. `open ~/Applications/Annunciator.app`: an item appears in the menu bar, no Dock icon.
3. Title: a filled circle, red when atc has a WARNING and amber for a CAUTION, then the count, then `5h NN% · 7d NN%`. With nothing lit: a plain airplane and the FUEL text only. Compare the numbers with the browser and the SwiftBar plugin.
4. Live: cause a change in atc (or wait) and see the title change without a click and without waiting 15 s.
5. Popover opens on click and closes on a click outside. Sections read WARNING, CAUTION, ADVISORY, highest first. Each LAMP shows its text, `AIRCRAFT …` / `FLIGHT …` when the server names them, and `→ next step`. The list scrolls when it is long.
6. Click a LAMP: the default browser opens `http://localhost:7700/<link>` (for example `/#strips`) on the right tab.
7. PENDING lists only non-zero DISPATCH, HUMAN CHECK, TOOL APPROVAL and SCHEDULE rows and each opens `#dispatch` (or that alert's own tab).
8. RTS shows `RTS OK <from> → <to> · HH:MMZ` in UTC. FUEL shows both windows with `reset HH:MMZ`. WORKING shows the AIRCRAFT and control-session counts, and NEEDS YOU names in orange when there are any.
9. Footer: **Open atc** opens the base URL, **Refresh** works, **Settings…** opens a window (the popover closes), **Quit** quits.
10. Settings: change the URL to a wrong port and Apply: the title turns grey `✈ —` and the popover says `atc 연결 안 됨`. Put the URL back: it reconnects within about 30 s. Try `ftp://x` and an empty field: the red hint shows and the old URL stays. Quit and reopen: the URL is remembered.
11. Stop the SSH forward: grey `✈ —` within about a minute (60 s watchdog) and no stale numbers in the popover. Start it again: the light comes back by itself.
12. Launch at login: turn it on; the state matches System Settings → General → Login Items (a `requires approval` note shows if it needs approving). Log out and in: the app starts. Turn it off again.
13. The status item stays legible in dark and light menu bars, and isn't hidden behind the notch (note if it is).
14. The popover is 420 × 520 pt. Say if it is too big or small.
