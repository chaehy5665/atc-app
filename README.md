# atc-app

**English** · [한국어](README.ko.md)

A native macOS menu bar app for [atc](https://github.com/chaehy5665/atc), the air-traffic-control board for AI coding sessions. Working name: **ANNUNCIATOR**, after the cockpit's MASTER WARNING / MASTER CAUTION panel.

It sits in the menu bar and lights up when atc needs the SUPERVISOR:

- a MASTER WARNING (red) or MASTER CAUTION (amber) light with a count, and the busiest ACCOUNT's FUEL used;
- one click shows the lit items (LAMPS) with their AIRCRAFT, FLIGHT or STAND, pending DISPATCH decisions, the last RTS, and working sessions;
- each item opens the right atc tab in the browser;
- a macOS notification, the tone and the voice callout for a new WARNING or CALL.

It only reads from atc. Approvals and switches stay in the atc screen.

> Status (2026-09-29): design only. See [docs/design.md](docs/design.md). Nothing is built yet.

## How it connects

atc listens on `127.0.0.1:7700` on the machine it runs on. From a Mac, keep an SSH local forward up (`ssh -N -L 7700:127.0.0.1:7700 <host>`, or the launchd agent in atc's `docs/guide/menubar.md`). The app talks to `http://localhost:7700` and never opens a port. Don't make atc listen on the LAN: atc has no login.

## Build (planned)

```sh
Tools/build-app.sh      # swift build -c release, bundle Annunciator.app, ad-hoc sign, copy to ~/Applications
```

A locally built app carries no quarantine flag, so it opens without a Developer ID.

## Licence

GPL-3.0-or-later, see [LICENSE](LICENSE). atc itself is a separate program with its own licence; the app talks to it only over HTTP. Code reused from other GPL-3.0 projects keeps its copyright notice, and the source file names where it came from.
