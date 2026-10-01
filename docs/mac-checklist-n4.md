<!-- SPDX-License-Identifier: Apache-2.0 -->
# Mac checklist (N4)

Run after the N4 PR is merged and `Tools/build-app.sh` builds. The app target (AppKit, AVFoundation, UserNotifications) was written on Linux and **has not been built or run on a Mac**. Report in words, no screenshots.

Only steps 1 to 3 of the N3 checklist have been run so far; if a later N3 step changes something here, say so.

1. `Tools/build-app.sh` succeeds. Paste compiler errors if not.
2. Settings: press **테스트**. macOS asks for notification permission once (or press **알림 허용 요청**). Allow. A banner `WARNING` appears and a three-beep tone plays.
3. Click the banner: the browser opens the atc base URL.
4. Cause a new WARNING or CALL in atc (or wait for one): a banner with the lamp text and the next step, the tone (WARNING three beeps, CALL two), no sound for CAUTION or ADVISORY. Click: the browser opens that item's tab (for example `#dispatch`).
5. First start with alerts already lit: nothing sounds or posts.
6. Settings → 음성 on: after the tone the atc callout plays once. With two new alerts at once: one tone and one voice. If atc has no phrase for the alert (404), only the tone plays.
7. Quiet hours on with a window around now (for example `HH:MM` two minutes ago to two minutes ahead): a new alert shows a banner, no tone, no voice. After the window: sounds again.
8. Quit the browser and close every window: sound and voice still play.
9. Turn the atc screen's 소리 off in the browser (README): with it on and the app on, both sound.
10. Sleep and wake: close the lid, raise a WARNING in atc, open it. `✈ —` may show for a moment, then the light returns and one banner and tone come for the alert raised while asleep. An alert raised and cleared during the sleep gives nothing.
11. Switch Wi-Fi off and on, or move networks: the feed reconnects within a few seconds; no repeat banner for alerts already announced.
12. Every click-through (lamp, pending row, NEEDS YOU chip, **Open atc ↗**) still opens the browser.
