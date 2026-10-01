<!-- SPDX-License-Identifier: Apache-2.0 -->
# Mac checklist (menu bar title and calm popover, ATC-222)

Run after the PR is merged (`Tools/build-app.sh`). The app target was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots. Do each check in light **and** dark mode, and once on a Mac with a notch.

1. `Tools/build-app.sh` succeeds. Paste errors if not (the title images use `NSImage.SymbolConfiguration.applying` and `NSTextAttachment`; the hidden ⌘R/⌘Q buttons use `keyboardShortcut`).

## Title item (five states)

2. **Idle** (nothing WARNING or CAUTION; ADVISORY alone counts as idle): a small aircraft, nothing else, in the menu bar's own colour (dark in a light bar, light in a dark bar). No number.
3. **CAUTION**: the aircraft, an amber dot and the count (`CAUTION + WARNING`), vertically centred with the aircraft.
4. **WARNING**: a heavier aircraft, a red triangle and the WARNING count. The triangle is a different shape from the CAUTION dot.
5. **NEEDS YOU** (a name in atc's NEEDS YOU, with and without a CAUTION or WARNING): a separate small blue dot after the rest. It is not mistaken for the amber dot.
6. **Unreachable** (stop the SSH forward): a grey aircraft with a slash, no number, no blue dot. It goes back to the right state when atc returns, with no flicker of old numbers.
7. **FUEL**: Settings → "메뉴 막대에 FUEL 표시" is off at first. Turn it on: `5h 6% · 7d 65%`-style text follows the badge, also when idle. On the notch Mac, say whether the item still fits or macOS hides it. Turn it off: the text goes at once, no restart.
8. **VoiceOver**: the item reads like `CAUTION 21, advisory 9, needs you 1` (and `atc unreachable`). The hover tooltip says the same.
9. **Left click** opens the popover. **Right click** (and control-click) opens a menu: Settings…, Refresh ⌘R, Quit ⌘Q; Settings… opens the settings window, Refresh reloads. After the menu, a left click still opens the popover (not the menu).

## Popover

10. Nothing WARNING or CAUTION: the tiles are gone and one line `✓ all normal` shows; the popover is shorter than with tiles. With one CAUTION the three tiles are back.
11. LAMP rows are one line each: letter chip, place, one-line reason (the full text is the hover tooltip), age. WARNING is open, CAUTION shows 5 and a `n개 더` control, ADVISORY is folded.
12. Header rows under the LAMP list: `PENDING n`, `NEEDS YOU n` (accent colour), the RTS line, `AIRCRAFT n · CONTROL n`. They are collapsed; PENDING and NEEDS YOU have a chevron and open to their rows (a click on a row opens that atc tab); the RTS and AIRCRAFT lines have no chevron. A header with nothing to show is not there.
13. Status group: with DUTY idle, GitHub counts without a failing CI and RADIO on and connected, one folded line `DUTY · GitHub 3 · RADIO TOWER` shows. Its chevron opens the three rows; DUTY opens the atc window at `#duty`, GitHub opens the Work window.
14. The group opens by itself when: DUTY answers or is down (a coloured dot, row in orange), a PR has CI failing (`1 CI failing` row in orange), or RADIO is on but the stream is down. A GitHub rate-limit or signed-out notice alone does not open it.
15. With DUTY disabled, GitHub signed out and RADIO off, the group is not there at all.
16. FUEL is one thin bar with its number at the bottom (the window nearest its limit); nothing without a number.
17. Footer: only `Open atc ↗` and the gear. With the popover open ⌘R refreshes, ⌘, opens settings, ⌘Q quits. (Quit also from the right-click menu.)
18. Stop the SSH forward: the notice and the FORWARD line are the main content as before; the popover is the minimum height.
19. The popover's height follows the content (240 to 640 pt) when a header row or the status group opens and closes; the LAMP list scrolls when it is long.
20. Light and dark: nothing is unreadable (orange text, accent-coloured NEEDS YOU, grey summary line). Tab through with VoiceOver: header rows say whether they fold, rows say they open atc.
