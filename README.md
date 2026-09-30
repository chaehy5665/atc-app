# atc-app

**English** · [한국어](README.ko.md)

A native macOS menu bar app for [atc](https://github.com/chaehy5665/atc), the air-traffic-control board for AI coding sessions. Working name: **ANNUNCIATOR**, after the cockpit's MASTER WARNING / MASTER CAUTION panel.

It sits in the menu bar and lights up when atc needs the SUPERVISOR:

- a MASTER WARNING (red) or MASTER CAUTION (amber) light with a count, and the busiest ACCOUNT's FUEL used;
- one click shows the lit items (LAMPS) with their AIRCRAFT, FLIGHT or STAND, pending DISPATCH decisions, the last RTS, and working sessions;
- each item opens the right atc tab in the browser;
- a macOS notification, the tone and the voice callout for a new WARNING or CALL.

It only reads from atc. Approvals and switches stay in the atc screen.

> Status (2026-09-30): v1 app (N3) written: MASTER light, popover, settings. Notifications and sound (N4) are not built yet. Design: [docs/design.md](docs/design.md). The app target has not been built on a Mac yet; see [docs/mac-checklist-n3.md](docs/mac-checklist-n3.md).

## How it connects

atc listens on `127.0.0.1:7700` on the machine it runs on. From a Mac, keep an SSH local forward up (`ssh -N -L 7700:127.0.0.1:7700 <host>`, or the launchd agent in atc's `docs/guide/menubar.md`). The app talks to `http://localhost:7700` and never opens a port. Don't make atc listen on the LAN: atc has no login.

## Build and run (on the Mac)

```sh
Tools/build-app.sh      # swift build -c release, bundle Annunciator.app, ad-hoc sign, copy to ~/Applications
```

```sh
open ~/Applications/Annunciator.app
```

1. Keep the SSH forward to atc up (see above). The atc that serves `/api/supervisor-summary` (ATC-153) must be deployed.
2. Run `Tools/build-app.sh` (needs the Xcode command line tools).
3. Open the app. `✈ —` in grey means atc is unreachable; it reconnects by itself (1 s backoff, doubling to 30 s).
4. Click the item for the popover. **Settings…** sets the atc URL (default `http://localhost:7700`) and launch at login.

A locally built app carries no quarantine flag, so it opens without a Developer ID.

Core tests run on Linux with `Tools/test-linux.sh` (Docker).

## Licence

GPL-3.0-or-later, see [LICENSE](LICENSE). atc itself is a separate program with its own licence; the app talks to it only over HTTP. Code reused from other GPL-3.0 projects keeps its copyright notice, and the source file names where it came from.
