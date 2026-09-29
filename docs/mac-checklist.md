<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Mac checklist (N0)

The SUPERVISOR runs this on the Mac after the N0 PR is merged. N2 starts only after the results are reported. Nothing here was built or run on a Mac by the team that wrote it.

Report back in words. Do not attach screenshots (public repository).

## 1. Toolchain

```sh
sw_vers -productVersion
swift --version
```

Report: the macOS version and the `swift --version` output (Xcode command line tools must be installed; `xcode-select --install` if not).

## 2. Build

```sh
git pull
Tools/build-app.sh
```

Expected: `swift build -c release` succeeds, the script prints each step, ends with `done`, and `~/Applications/Annunciator.app` exists. Run it a second time: it must succeed again and replace the app.

Report: pass or fail. On failure, paste the last lines of output.

## 3. Status item

```sh
open ~/Applications/Annunciator.app
```

Expected: `✈` appears in the menu bar, there is no Dock icon, and clicking it shows a menu with `Test notification (debug)`, `Launch at login (debug): …` and `Quit`. Gatekeeper should not block it (locally built, no quarantine flag).

Report: whether it appeared, and whether any Gatekeeper or other dialog showed up. Also note if the item is hidden behind the notch or by another menu bar tool.

## 4. Notification

Click `Test notification (debug)`.

Expected: macOS asks for notification permission. Allow it. A banner titled `ANNUNCIATOR` with `Test notification` appears (click the menu item again if the first click only asked for permission).

Report: whether the permission prompt showed, whether the banner appeared, and the app's row in System Settings → Notifications. If nothing appeared:

```sh
log show --last 2m --predicate 'eventMessage CONTAINS "ANNUNCIATOR"' --style compact
```

## 5. Launch at login

Click `Launch at login (debug): …` (it calls `SMAppService.mainApp.register()`).

Expected: the item reads `enabled` (or `requires approval`, in which case approve it in System Settings → General → Login Items and reopen the menu), and Annunciator is listed in Login Items. Then log out and back in (or restart): `✈` should appear on its own. Click the item again to unregister and confirm it reads `not registered`.

Report: the status text after the first click, whether it started after re-login, and whether unregister worked. Any error is in:

```sh
log show --last 5m --predicate 'eventMessage CONTAINS "ANNUNCIATOR"' --style compact
```

## 6. Clean up (optional)

Quit from the menu. `rm -rf ~/Applications/Annunciator.app` removes the app; make sure launch at login is unregistered first.
