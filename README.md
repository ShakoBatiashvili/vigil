# Vigil

[![CI](https://github.com/ShakoBatiashvili/vigil/actions/workflows/ci.yml/badge.svg)](https://github.com/ShakoBatiashvili/vigil/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Keep your Mac awake, safely. A small menu-bar app and command-line tool that holds your Mac awake on your
terms, shows what is draining the battery, and shows who else is keeping it awake.

Vigil is built to be **easy to trust**: no root, no helper daemon, no network, no auto-update, no
third-party code, about three thousand lines you can read in an afternoon, and a script
(`make audit`) that checks those claims against the source and the built app.

## What it does

| | |
|---|---|
| **Hold awake** | One-tap presets (30 min, 1 hr, 4 hr, until a clock time, no limit). Uses the same IOKit power assertion as macOS's own `caffeinate`. |
| **Rules** | Stay awake *while an app is running* (matched by whole name, case-insensitive) and/or *on a weekly schedule* (e.g. weekdays 09:00 to 18:00, overnight windows supported). |
| **Battery guard** | Unplugged and below 20% (adjustable 5 to 50%): the hold is released and you get a notification. Rules cannot re-engage it until you plug in. You can deliberately turn it back on; it then continues down to a hard 5% floor. |
| **Battery view** | Live watts, time left, charge level with the guard threshold marked. |
| **Biggest drains** | Top apps by Energy Impact (the Activity Monitor score), helper processes rolled up into their app. Sampled only while the panel is open. |
| **Awake holders** | Every process currently holding the Mac awake, how long, and who started it. Holds of 1 h+ and 12 h+ are flagged. A stray `caffeinate` of yours can be stopped (two-step). |
| **CLI** | `vigil status`, `holders`, `drain`, `hold --for 2h`, `hold --until 18:00`, `stop <pid>`. |

## Install

Vigil is **not distributed as a prebuilt binary** and is not notarized, on purpose: you build it on your own Mac
from source you can read. A locally built app has no download quarantine, so macOS opens it without Gatekeeper
prompts, and there is nothing to trust except the code.

**Requirements:** macOS 14 or later and Xcode 16 or later (full Xcode, for the Swift toolchain and SDK).

### Homebrew

```sh
brew install ShakoBatiashvili/vigil/vigil
cp -R "$(brew --prefix vigil)/Vigil.app" ~/Applications/
open ~/Applications/Vigil.app
```

This builds from a tagged source release (the formula pins its SHA-256), puts the `vigil` command on your
`PATH`, and builds `Vigil.app`; expect about a minute. After `brew upgrade vigil`, copy the app again to update it.
The formula lives in [ShakoBatiashvili/homebrew-vigil](https://github.com/ShakoBatiashvili/homebrew-vigil).

### From source

```sh
git clone https://github.com/ShakoBatiashvili/vigil.git && cd vigil
make test        # optional: unit tests plus real-system tests
make app         # builds dist/Vigil.app, ad-hoc signed with hardened runtime
make audit       # verifies the safety claims (see SECURITY.md)
make install     # copies to ~/Applications. No sudo.
open ~/Applications/Vigil.app
```

For the command line from a source install:

```sh
ln -s ~/Applications/Vigil.app/Contents/Helpers/vigil ~/bin/vigil   # or any folder on your PATH
```

### Uninstall

```sh
pkill -x Vigil
rm -rf ~/Applications/Vigil.app "$HOME/Library/Application Support/Vigil"
brew uninstall vigil && brew untap ShakoBatiashvili/vigil     # if you used Homebrew
```

If you enabled *Launch at login*, also remove Vigil under System Settings, General, Login Items.

## Using it

**Menu bar:** a cup icon (filled while holding; a countdown appears beside it for timed holds). Click it.

- **Top:** the master switch and presets. Tap an active preset again to stop. *Until…* opens a time picker.
- **Drain / Awake / Rules** tabs. *Awake* shows a warning mark when something has held the Mac awake for 12 h+.
- **Rules** is where the battery threshold, "also keep the display on", watched apps and the schedule live.
  Everything applies immediately and is written to disk about half a second later ("Saved" appears only after the write lands).

**Command line:**

```sh
vigil status                 # battery, power source, what is holding the Mac awake
vigil holders                # who, how long, started by whom; `!!` = 12h+
vigil drain                  # biggest energy users right now (about 2 s)
vigil hold --for 90m         # hold until the timer, Ctrl-C, or the battery guard
vigil hold --until 18:00 --display
vigil stop 44321             # only ever works on your own /usr/bin/caffeinate
```

## Privacy

Vigil stores one small file, `~/Library/Application Support/Vigil/settings.json` (your battery threshold, watched
app names and schedule), readable only by you. It makes **no network connections** and collects no telemetry. It
reads battery state and the list of your own running processes, locally, and nothing leaves your Mac.

## Lid closed

Vigil does not (and cannot, without root) override lid-close sleep. macOS already keeps running with the lid
shut in **clamshell mode**: external display + power adapter + a keyboard or mouse. Vigil's hold stops it from
idle-sleeping in that setup. Closing the lid with nothing connected sleeps the Mac, by design.

## Compatibility and known limits

- **Tested on:** Apple silicon, macOS 27 (development) and macOS 15 (continuous integration runs the test suite there). macOS 14 and Intel Macs are supported by the package settings but untested.
- The UI is covered by rendered snapshots (`make snapshot`), not automated UI tests.
- Energy Impact comes from Apple's `/usr/bin/top` (about a 2 s sample), so the drain list refreshes every ~8 s while the panel is open and not at all when it is closed.
- App rules only see **your own** processes. They match the executable name, the app name and the name the process was started as (so `claude` works even though that binary is named after its version).
- Manual sessions do not survive quitting the app, on purpose.
- "Launch at login" uses `SMAppService` and may need approval in System Settings; it only works from an installed `Vigil.app`.
- Idle footprint: about 0% CPU and 85 MB resident (the SwiftUI baseline).

## Development

```text
Sources/VigilCore     pure logic: engine, battery guard, schedule, parsers, wording. No I/O.
Sources/VigilSystem   thin adapters: IOKit assertions, battery, libproc, /usr/bin/top, settings file.
Sources/vigil         the CLI (parse, dispatch, print).
Sources/VigilApp      the SwiftUI menu-bar app (orchestration + views).
Tests/                unit tests for the core; real-system tests (no mocks) for the adapters.
assets/AppIcon.icns   the app icon, generated from code by scripts/make-icon.swift (`make icon`).
```

`make test` runs everything; `make audit` checks the safety claims; `make snapshot` renders the UI from canned data
(light and dark) to `dist/snapshots`. See [CONTRIBUTING.md](CONTRIBUTING.md), `docs/DESIGN.md` for the decisions
behind it, and [SECURITY.md](SECURITY.md) for the threat model and how to report a vulnerability.

## License

MIT. See [LICENSE](LICENSE). Vigil is written from scratch against Apple's public APIs; no code from other
keep-awake apps is included.
