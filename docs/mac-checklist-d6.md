<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (D6, DUTY entry)

Run after the D6 PR is merged (`Tools/build-app.sh`). The app target was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots.

1. `Tools/build-app.sh` succeeds. Paste errors if not.
2. With atc's DUTY enabled and idle: open the popover. A `DUTY` row with a **green** dot shows under the status line, and the popover is one row taller than with DUTY off. Hover: tooltip `DUTY · <account> · context <k>/<cap>k`.
3. Click the row: the popover closes and the atc window opens with the DUTY drawer. With the window already open on another tab: the drawer opens without a page reload.
4. Settings → **atc 열기** = 브라우저, or ⌥-click on the row: it opens the browser at `…/#duty`.
5. Window menu (window open): **DUTY ⌘D** opens the drawer the same way. ⌘D does not clash with anything in the page.
6. While DUTY answers a message, keep the popover open: within about 5 s the dot turns **amber**, then back to green. A blocked or down DUTY shows **red** (or stop it, if you can).
7. Turn DUTY off in atc: with the popover open, the row goes away within about 5 s and the popover shrinks by one row.
8. Close the popover and watch atc's access log (or the SSH forward's traffic): `GET /api/duty/status` stops. The app never opens the `duty` SSE topic (`/api/events?topics=` has only `alert,summary,version`, plus `radio` if RADIO is on).
9. No sound and no notification for anything DUTY does, including a DUTY reply.
10. Stop the SSH forward, then start it: the row is gone while unreachable (the popover shows the notice) and comes back when atc does.
