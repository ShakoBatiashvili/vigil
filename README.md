# Vigil

Keep your Mac awake, safely. A small menu-bar app and command-line tool that holds your Mac awake
on your terms, shows what is draining the battery, and shows who else is keeping it awake.

Vigil is built to be **easy to trust**: no root, no helper daemon, no network, no auto-update, no
third-party code, a few thousand lines you can read in an afternoon, and a script
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

## Install (from source)

Requirements: macOS 14 or later and the Swift toolchain that ships with Xcode (developed with Swift 6.4 on
macOS 27; the package targets Swift 5.9).

```sh
git clone <your repo> vigil && cd vigil
make test        # optional: 186 tests, including real-system ones
make app         # builds dist/Vigil.app, ad-hoc signed with hardened runtime
make audit       # verifies the safety claims (see SECURITY.md)
make install     # copies to ~/Applications. No sudo.
open ~/Applications/Vigil.app
```

Build it on each machine rather than copying a built app around: a locally built app has no download
quarantine, so it opens without Gatekeeper prompts, and nobody has to trust a binary they didn't build.

Optional command-line access:

```sh
ln -s ~/Applications/Vigil.app/Contents/Helpers/vigil ~/bin/vigil   # or any folder on your PATH
vigil help
```

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

## Lid closed

Vigil does not (and cannot, without root) override lid-close sleep. macOS already keeps running with the lid
shut in **clamshell mode**: external display + power adapter + a keyboard or mouse. Vigil's hold stops it from
idle-sleeping in that setup. Closing the lid with nothing connected sleeps the Mac, by design.

## Known limits

- Energy Impact comes from Apple's `/usr/bin/top` (about a 2 s sample), so the drain list refreshes every ~8 s while the panel is open and not at all when it is closed.
- App rules only see **your own** processes. They match the executable name, the app name and the name the process was started as (so `claude` works even though the binary is `.../2.1.322`).
- Manual sessions do not survive quitting the app, on purpose.
- "Launch at login" uses `SMAppService` and may need approval in System Settings; it only works from the installed `Vigil.app`.
- Idle footprint: about 0% CPU; about 85 MB resident (SwiftUI baseline).
- Not verified in the build session: clicking the real menu-bar icon (verified instead: launch, hold, release, no network, idle cost, and rendered screenshots of every state in light and dark).

## Development

```text
Sources/VigilCore     pure logic: engine, battery guard, schedule, parsers, wording. No I/O.
Sources/VigilSystem   thin adapters: IOKit assertions, battery, libproc, /usr/bin/top, settings file.
Sources/vigil         the CLI (parse, dispatch, print).
Sources/VigilApp      the SwiftUI menu-bar app (orchestration + views).
Tests/                 unit tests for the core; real-system tests (no mocks) for the adapters.
assets/AppIcon.icns   the app icon, generated from code by scripts/make-icon.swift (`make icon`).
```

`make test` runs everything. `make snapshot` renders the UI from canned data (light and dark) to `dist/snapshots`.
See `docs/DESIGN.md` for the decisions behind it and `SECURITY.md` for the threat model.

## License

MIT. See [LICENSE](LICENSE). Vigil is written from scratch against Apple's public APIs; no code from other
keep-awake apps is included.
