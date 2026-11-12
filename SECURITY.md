# Security

Vigil's design goal is a **small, checkable trust footprint**. This document says what it can do, what it
cannot, how to verify that yourself, and how to report a problem.

## Reporting a vulnerability

Please report security issues **privately** through GitHub: on the repository's **Security** tab, choose
**Report a vulnerability** (<https://github.com/ShakoBatiashvili/vigil/security/advisories/new>). Please do not open
a public issue for anything exploitable.

This is a one-person project, so replies are best-effort, but reports are taken seriously. Only the latest
release is supported.

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
- **No third-party code.** `Package.swift` has no dependencies.
- **No private APIs**, no `dlopen`, no Objective-C runtime tricks.
- **No privacy permissions.** No Location, Bluetooth, Calendar, Accessibility or Screen Recording prompts. No entitlements.
- **No shell.** Nothing is ever passed to `/bin/sh`.
- **No auto-start of anything privileged.** "Launch at login" is a standard per-user login item and is off by default.
- **No build-machine details in binaries.** Debug symbols are stripped and `#file` is module-relative, so a build does not embed the builder's home folder or username (`make audit` checks this).

## Threat model

| Threat | Outcome |
|---|---|
| A web page tries to drive it | Nothing to drive: no URL scheme, no listener. |
| Another **user** on the Mac | App rules and `stop` only touch the current user's processes; settings are `0600`. |
| Malware **running as you** edits `settings.json` | It can change the battery threshold, add watched names or a schedule. Worst case: the Mac stays awake more often (the battery guard still applies; threshold is clamped to 5 to 50%). No code execution, no privilege gain. Malware running as you can already do far more through other means. |
| A forged or stale "stop" request | `HolderControl.stop` ignores the description it is given and re-reads the live process's executable path and owner, refusing anything that is not your own `/usr/bin/caffeinate`. Covered by a test that forges a holder pointing at an unrelated process. |
| Malicious update | There is no updater. Homebrew installs build a tagged source release whose SHA-256 is pinned in the formula. |
| A compromised tap or release | The pinned hash detects a swapped tarball, but the tap repository is itself a trust point: read the formula (`brew cat ShakoBatiashvili/vigil/vigil`) before installing, or build from this repository directly. |
| Supply-chain compromise | No dependencies. The build is the Swift toolchain plus Apple SDKs. CI actions are pinned to commit SHAs. |
| A runaway hold drains the battery | The battery guard releases at the threshold (default 20%) and the hard floor is 5%. Holders older than 12 h are flagged in the UI and `vigil status`. |

## Verify it yourself

```sh
make audit
```

checks, from the source and from the built `dist/Vigil.app`: no network APIs, no privilege-escalation or shell
strings, no private APIs, subprocesses only in `EnergyReader`, signals only in `HolderControl`, no dependencies,
a consistent version; and for the app bundle: valid strict signature, hardened runtime, **no entitlements**, no
URL scheme, no privacy usage keys, no bundled frameworks or launchd plists, no WebKit/Network linkage, no
hard-coded URLs and no home-folder paths in the binaries. The checks have been confirmed to fail when violations
are planted, including data hidden after the Mach-O signature, which `strings` alone would miss.

You can also inspect the live process:

```sh
pmset -g assertions | grep -i vigil     # the assertion Vigil holds, and why
lsof -a -p "$(pgrep -x Vigil)" -i       # open network sockets (expect none)
codesign -d --entitlements - ~/Applications/Vigil.app   # expect none
```

## Limits of this review

The app is ad-hoc signed (not notarized) and is deliberately not distributed as a binary: build it yourself.
Review the code you run; `make audit` is a guard-rail, not a proof.
