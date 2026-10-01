<!-- SPDX-License-Identifier: Apache-2.0 -->
# Mac checklist (N3)

The SUPERVISOR runs this on the Mac after the N3 PR is merged. The app target (AppKit, SwiftUI) was written on Linux and **has not been built or run on a Mac**. Expect a compile error or two; report the lines.

Report in words. No screenshots (public repository).

Prerequisites: the SSH forward is up, and the atc on the other end serves `/api/supervisor-summary` (`curl -s localhost:7700/api/supervisor-summary` returns JSON with `"v":1`).

1. `git pull && Tools/build-app.sh` succeeds, twice in a row. If it fails, paste the compiler errors.
2. `open ~/Applications/Annunciator.app`: an item appears in the menu bar, no Dock icon.
3. Title: a filled circle, red when atc has a WARNING and amber for a CAUTION (the colour follows atc's MASTER light), then the count, then `5h NN% · 7d NN%` with one space between the parts. The count is WARNING + CAUTION, the same as the number at the top of the atc screen, followed by ` +N` when there are ADVISORY items (for example `23 +13 5h 16% · 7d 66%`). With the light off: a plain airplane, `0` (or `0 +N`) and the FUEL text. Compare the numbers with the browser and the SwiftBar plugin: they must be equal. Say how the red and amber circle looks in a light and in a dark menu bar, and that the plain airplane turns white or black with the menu bar.
4. Live: cause a change in atc (or wait) and see the title change without a click and without waiting 15 s.
5. Popover opens on click and closes on a click outside. The top strip stays put while the lamp list scrolls: three tiles (MASTER WARNING, MASTER CAUTION, ADVISORY) with the same counts as the summary, lit in red, amber and grey; PENDING chips (non-zero only) and NEEDS YOU names as chips in their own accent style (not amber); FUEL bars with `NN% · HH:MMZ`; one mono line `RTS … · AIRCRAFT n · CONTROL n`. Say how each looks in a light and a dark appearance.
5a. Lamp list: WARNING is always fully shown. CAUTION shows its first 5 and `CAUTION n개 더` opens the rest (`접기` folds it). ADVISORY is folded behind `ADVISORY n`. Quit and reopen the app: the open or folded state is remembered.
5b. One-line lamp rows: a `W`/`C`/`A` chip, the place in mono, the server text on at most two lines (the full text is the tooltip), the age on the right (`4m`, `3h`, `2d`; it moves without a click within a minute). The `next` step shows on hover or after the chevron. Hover gives the row a background, `↗` and a pointing hand; VoiceOver reads level, place, text, age and says it opens atc.
6. Click a LAMP: the default browser opens `http://localhost:7700/<link>` (for example `/#strips`) on the right tab.
7. PENDING chips list only non-zero DISPATCH, HUMAN CHECK, TOOL APPROVAL and SCHEDULE and each opens `#dispatch` (or that alert's own tab). A NEEDS YOU chip opens `#strips`.
8. RTS shows `RTS OK <from> → <to> · HH:MMZ` in UTC on the mono line, with `AIRCRAFT n · CONTROL n`. FUEL shows both windows as bars with `NN% · HH:MMZ`.
9. Footer: **Open atc ↗** is the one emphasised button and opens the base URL. Refresh (⌘R) and Settings (⌘,) are icon buttons with tooltips; Settings opens a window and the popover closes. The `⋯` menu holds **Quit** (⌘Q). Say if the shortcuts work with the popover open.
10. Settings: change the URL to a wrong port and Apply: the title turns grey `✈ —` and the popover says `atc 연결 안 됨`. Put the URL back: it reconnects within about 30 s. Try `ftp://x` and an empty field: the red hint shows and the old URL stays. Quit and reopen: the URL is remembered.
11. Stop the SSH forward: grey `✈ —` within about a minute (60 s watchdog) and no stale numbers in the popover. Start it again: the light comes back by itself.
12. Launch at login: turn it on; the state matches System Settings → General → Login Items (a `requires approval` note shows if it needs approving). Log out and in: the app starts. Turn it off again.
13. The status item stays legible in dark and light menu bars, and isn't hidden behind the notch (note if it is).
14. The popover is 420 pt wide and its height fits the content between about 240 and 640 pt, then the list scrolls. Say if the height jumps or clips when a section is opened, or if it is too big or small.
