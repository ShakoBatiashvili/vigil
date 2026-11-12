# Design notes

## Origin

Vigil replaces the *keep-awake core* of a third-party menu-bar app that was reviewed and rejected for
installation. The review found the real core is about 90 lines (an IOKit power assertion) wrapped in 40k+ lines
of triggers, UI, a persistent root helper, auto-update and integrations. macOS also already ships `caffeinate`.
Vigil keeps what is worth having beyond that (visibility, timers, rules, a battery guard) and drops the trust
surface. It is written from scratch against Apple's public APIs; no code is derived from the original.

## Decisions (agreed up front, with the reason)

| Decision | Why | Rejected |
|---|---|---|
| **No root, ever.** Closed-lid works only in macOS's native clamshell mode. | Root helper plus auto-update was the main reason the original was rejected. | Narrow sudoers rule; admin-password prompt per toggle; persistent LaunchDaemon over XPC |
| **Source-only distribution.** Public repo; a Homebrew formula builds a tagged release on the user's Mac; no prebuilt binaries. | Nobody has to trust a binary they didn't build, a locally built app has no download quarantine (so no Gatekeeper dialog), and there is no Developer ID or notarization pipeline to maintain. | A prebuilt, notarized cask (needs a paid Developer ID); an un-notarized prebuilt download (blocked by Gatekeeper) |
| **Features:** presets/timers, app and schedule rules, battery guard, battery + drain view, awake-holders view. | The user's list. A foreground-visibility tool beats a feature checklist. | Wi-Fi/Bluetooth/Calendar triggers (each needs a privacy permission), Claude Code hook integration (edits other tools' config; Claude Code already runs its own `caffeinate`), AC-power trigger |
| **Battery guard releases below 20% on battery**; a deliberate restart continues to a 5% floor; rules never override it. | A forgotten hold once ran for 3+ days on battery. | Hard time cap; no guard |
| **No IPC.** CLI and app each hold their own assertion. | Nothing to authenticate or attack. | URL scheme, XPC, sockets |
| **Sample energy only while the panel is open.** | A battery tool must not be a battery drain. | Always-on sampling |

## Architecture

```text
VigilCore (pure)                          VigilSystem (adapters)              Front ends
------------------------------------      --------------------------------    --------------------
SessionMode, TimeWindow, ProcessTrigger   PowerHold (IOKit assertions)        vigil  (CLI)
BatteryGuard, Settings (validated)        BatteryReader (IOPS + registry)     VigilApp (SwiftUI)
Engine.start / stop / tick  ---------->   HolderReader / HolderControl
TopParser, DrainModel, BatteryMath        ProcessLister (libproc, sysctl)
HoldSummary / Notices (all wording)       EnergyReader (/usr/bin/top)
CLIParser                                 SettingsStore (0700/0600, atomic)
```

All policy lives in `Engine` as pure functions: *inputs* (clock, running names, battery reading, settings,
state) in, *decision* (hold or not, display or not, reasons, effects) out. The front ends only gather facts and
apply the answer. That is why the interesting behaviour is unit-tested without touching the system.

### Engine rules

1. Plugging in always clears the battery latch and any override.
2. A timed manual session expires at its end (`sessionEnded` effect).
3. Wanted = manual session OR a watched process is running OR the schedule window is active.
4. Guard: tripped when unplugged and below the threshold; **latched** until the adapter is connected, so a
   jittery gauge cannot re-engage the hold. When it trips it ends the manual session and, if anything was wanted
   or being held, emits `guardReleased` (one notification).
5. Starting a session while unplugged and already below the threshold lifts the latch and sets an override: the
   guard then applies at the hard floor (5%) until the next time the Mac is plugged in.
6. `hold = wanted && !tripped`; the display is held only if requested and only while holding.

## Testing approach

Test-first throughout. Pure logic has table-driven unit tests (calendar logic runs in a fixed UTC calendar).
The system layer is tested against the **real** OS with no mocks: real power assertions appear in
`IOPMCopyAssertionsByProcess` and disappear on release; a real spawned `caffeinate` is listed and stopped; a
forged holder pointing at an unrelated process is refused and the victim process survives; processes started via
symlinks are found by their launch name. The stop-guard test was mutation-checked (made to fail by trusting the
holder's claims) before being relied on.

The UI is reviewed through rendered screenshots (`make snapshot`) of every state in light and dark, and the built
app was run end to end (rule engages the assertion; releases after the watched process exits; no sockets; idle cost).

Tests that start processes poll for the expected state instead of sleeping a fixed time: a brand-new executable can
take a moment to exec while macOS vets it, and a fixed sleep made one test flaky. CI runs the suite on every push.

The audit (`scripts/audit.sh`) is itself mutation-tested: planted network calls, shell strings, home paths and URLs
must make it fail. That caught a real blind spot: scanning binaries with `strings` misses bytes outside the Mach-O
segments, and a raw byte scan found build paths (the author's home folder) embedded in the binaries. The fix: strip
debug symbols before signing and make `#file` module-relative.

## Open items

- Launch-at-login (`SMAppService`) needs a real-world check on a machine where it can be approved.
- macOS 14 and Intel Macs are untested (CI covers macOS 15 on Apple silicon).
- Optional: collapse the Rules tab's Schedule section behind a disclosure if the tab feels long.
- If there is demand: a notarized prebuilt cask (requires a paid Apple Developer ID).
