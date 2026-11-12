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
| **Source-only distribution** to a few teammates; each builds locally. | No Developer ID or notarization pipeline to maintain; nobody trusts a binary they didn't build. | Signed + notarized download |
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

## Open items

- Choose a license before sharing beyond the team.
- An app icon (the bundle uses the generic one).
- Launch-at-login (`SMAppService`) needs a real-world check on a machine where it can be approved.
- Optional: collapse the Rules tab's Schedule section behind a disclosure if the tab feels long.
