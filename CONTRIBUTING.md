# Contributing

Thanks for taking a look. Vigil is deliberately small, and its main feature is that it is **easy to trust**.
Contributions are welcome as long as they keep that property.

## Ground rules

These are enforced by `make audit` (and CI), so a pull request that breaks one will fail:

- **No network access**, no URL scheme, no IPC.
- **No root, no helpers, no privileged anything.**
- **No third-party dependencies** and no private APIs.
- **No shell invocation.** The only subprocess is `/usr/bin/top` in `EnergyReader`.
- Built binaries must not contain build-machine paths.

Features that need any of the above (for example closed-lid without a display, which needs root, or update
checks) are out of scope by design. See `docs/DESIGN.md` for the reasoning.

## Workflow

Tests come first:

1. Write a failing test for the behaviour you want. Pure logic goes in `Sources/VigilCore` with unit tests in
   `Tests/VigilCoreTests`; OS access goes behind a thin adapter in `Sources/VigilSystem` and is tested against the
   real system (no mocks; see the existing tests for the pattern).
2. Watch it fail for the right reason, then write the minimum code to pass.
3. Tests that start processes must **poll** for the expected state rather than sleeping a fixed time.
4. Run `make test` and `make app && make audit` before opening a pull request.

```sh
make test        # unit tests + real-system tests
make app         # build dist/Vigil.app
make audit       # verify the safety claims against source and binary
make snapshot    # render the UI to PNGs (light and dark) from canned data
```

UI changes: include before/after screenshots from `make snapshot`, and keep to the existing spacing and
radius scale (`Theme` in `Sources/VigilApp/Support.swift`).

## Releasing (maintainer notes)

1. Bump `VERSION` in `scripts/build-app.sh` and `CLIHelp.version` in `Sources/VigilCore/CLIParser.swift`
   (the audit checks they agree).
2. `make test && make app && make audit`, then tag `vX.Y.Z`.
3. Create the release with a source tarball made by `git archive`, and update the formula in
   [homebrew-vigil](https://github.com/ShakoBatiashvili/homebrew-vigil) with the new URL and SHA-256.

## Reporting bugs and vulnerabilities

Bugs: open an issue using the template. Security problems: use GitHub's private reporting (see `SECURITY.md`),
not a public issue.
