# Security model

Vigil's design goal is a **small, checkable trust footprint**. This document says what it can do, what it
cannot, and how to verify that yourself.

## What Vigil can do

| Capability | How | Scope |
|---|---|---|
| Keep the Mac from idle-sleeping | IOKit power assertions (`IOPMAssertionCreateWithName`), same as `caffeinate` | Dropped by the kernel when the process exits |
| Read battery state | `IOPS*` and the `AppleSmartBattery` registry entry | Read-only |
| List running processes and who holds power assertions | `libproc`, `IOPMCopyAssertionsByProcess`, `sysctl KERN_PROCARGS2` | Read-only; app rules only consider **your own** processes |
| Measure per-process energy | Runs Apple's `/usr/bin/top` by absolute path, fixed arguments, scrubbed environment, 8 s timeout | The **only** subprocess in the project |
| Ask a stray process to quit | `SIGTERM` | **Only** your own `/usr/bin/caffeinate`, re-verified against the live process (real path and owner) at the moment of the call |
| Save settings | `~/Library/Application Support/Vigil/settings.json`, folder `0700`, file `0600`, atomic write | Values are validated and clamped on every load and save |
| Notify you | Local `UNUserNotificationCenter` notifications | Permission requested lazily, the first time you start a session |

## What Vigil does not do

- **No root and no privileged helper.** No `sudo`, no `osascript`, no LaunchDaemon, no `SMJobBless`, no sudoers rule. Closed-lid-without-a-display needs root and is intentionally not offered.
- **No network access of any kind.** No `URLSession`, no sockets, no WebKit, no update checker, no telemetry, no hard-coded URLs.
- **No inter-process surface.** No custom URL scheme, no XPC, no sockets, no distributed notifications. The CLI and the app are independent processes that each hold their own assertion.
- **No third-party code.** `Package.swift` has no dependencies. There is nothing to update and nothing to be swapped under you.
- **No private APIs**, no `dlopen`, no Objective-C runtime tricks.
- **No privacy permissions.** No Location, Bluetooth, Calendar, Accessibility or Screen Recording prompts. No entitlements.
- **No shell.** Nothing is ever passed to `/bin/sh`.
- **No auto-start of anything privileged.** "Launch at login" is a standard per-user login item and is off by default.

## Threat model

| Threat | Outcome |
|---|---|
| A web page tries to drive it | Nothing to drive: no URL scheme, no listener. |
| Another **user** on the Mac | App rules and `stop` only touch the current user's processes; settings are `0600`. |
| Malware **running as you** edits `settings.json` | It can change the battery threshold, add watched names or a schedule. Worst case: the Mac stays awake more often (the battery guard still applies; threshold is clamped to 5 to 50%). No code execution, no privilege gain. Malware running as you can already do far more through other means. |
| A forged or stale "stop" request | `HolderControl.stop` ignores the description it is given and re-reads the live process's executable path and owner, refusing anything that is not your own `/usr/bin/caffeinate`. Covered by a test that forges a holder pointing at an unrelated process. |
| Malicious update | There is no updater. You rebuild from source you can read. |
| Supply-chain compromise | No dependencies. Build is the Swift toolchain plus Apple SDKs. |
| A runaway hold drains the battery | The battery guard releases at the threshold (default 20%) and the hard floor is 5%. Holders older than 12 h are flagged in the UI and `vigil status`. |

## Verify it yourself

```sh
make audit
```

checks, from the source and from the built `dist/Vigil.app`: no network APIs, no privilege-escalation or shell
strings, no private APIs, subprocesses only in `EnergyReader`, signals only in `HolderControl`, no dependencies;
and for the app bundle: valid strict signature, hardened runtime, **no entitlements**, no URL scheme, no privacy
usage keys, no bundled frameworks or launchd plists, no WebKit/Network linkage, no hard-coded URLs in the
binaries. The script has been checked to fail when violations are planted.

You can also inspect the live process:

```sh
pmset -g assertions | grep -i vigil     # the assertion Vigil holds, and why
lsof -a -p "$(pgrep -x Vigil)" -i       # open network sockets (expect none)
codesign -d --entitlements - ~/Applications/Vigil.app   # expect none
```

## Limits of this review

The app is ad-hoc signed (not notarized): fine for a binary you built yourself, not for redistribution.
Review the code you run; `make audit` is a guard-rail, not a proof.
