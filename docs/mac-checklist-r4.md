<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (R4, RADIO monitor)

Run after the R4 PR is merged and `Tools/build-app.sh` builds. The app target (AppKit, AVFoundation) was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots. The atc you point at must have RADIO R1 and R3 (`GET /api/radio`, `GET /api/radio/<id>.wav`, SSE topic `radio`).

1. `Tools/build-app.sh` succeeds. Paste compiler errors if not.
2. Settings shows **RADIO monitor** off, the frequency at TOWER and the noise at 호출만. Both pickers are greyed out while it is off. Quit and reopen: the choices are kept.
3. Turn it on. The popover gets a `RADIO ● TOWER` line under the status line with `대기 중` or the last TOWER transmission's head, and the popover height still fits (no clipped footer). The menu bar title is unchanged. Nothing plays for traffic that was already recorded.
4. Make TOWER speak (a CLEARANCE from atc, or wait for one): a short phrase plays through the speakers with no browser open. The line's head updates to that transmission.
5. Several TOWER calls at once: they play one after another, never over each other. With more than 5 waiting, only the newest 5 play.
6. Noise: 답 없는 호출만 skips replies and calls that are already answered; 전부 also plays READBACK, ROGER and UNABLE replies.
7. Change the frequency to GROUND: the line says `RADIO ● GROUND`, TOWER traffic no longer plays, and the last-head resets.
8. An alert wins: while a RADIO phrase plays, raise a new WARNING or CALL. RADIO stops at once, the tone (and voice, if on) plays, and then RADIO goes on with what is queued.
9. Quiet hours on with a window around now: TOWER calls do not play, and one that arrived inside the window is not played after it. After the window it plays new traffic again.
10. atc unreachable (stop the SSH forward): the popover says `RADIO ● TOWER (연결 안 됨)` (and the title shows `✈ —`), nothing plays. Bring it back and let TOWER speak while it was down: nothing from the gap plays after the reconnect, and only new calls do.
11. Sleep and wake, or a network change: RADIO reconnects with the alert feed; no old call is replayed.
12. Turn the monitor off: audio stops, the popover line goes away. Nothing new plays.
13. Alerts are unchanged: banners, tone, voice, quiet hours and every click-through (N4 checklist steps 2 to 12) still work with the monitor on and off.
