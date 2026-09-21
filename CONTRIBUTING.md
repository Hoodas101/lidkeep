# Contributing to LidKeep

Thanks for your interest. LidKeep is a small, dependency-free macOS tool, and the
codebase is meant to stay that way. This guide covers how to build, test, and
propose changes.

## What the project is (and isn't)

- **Goal:** turn the display off *without* sleeping the Mac, and keep it useful
  closed-lid / on battery / headless. Nothing more.
- **Principles that matter in review:**
  - **Zero third-party dependencies.** Pure Swift + system frameworks. Don't add
    a package manager dependency unless it is strictly necessary.
  - **One shared core, two targets.** `Sources/Shared/` is compiled into *both*
    the menu bar app (`Sources/Bar/`) and the CLI (`Sources/CLI/`). Anything
    shared belongs there.
  - **Plans are the source of truth; the three booleans are projections.**
    `planAC` / `planBattery` (each a `PowerPlan`) are what gets persisted.
    `autoNosleep` / `keepAwake` / `lidAwake` are *derived* "what the active
    power source's plan says right now" — they are never persisted on their own.
    If you change a power behavior, change the plan, not just a projection, or a
    periodic re-sync will silently undo your change.

## Development setup

```bash
# 1. Xcode Command Line Tools (provides the Swift toolchain + make)
xcode-select --install

# 2. Build the CLI + app into build/
make            # == make all

# 3. Run the end-to-end smoke test
make test       # skips cases that would interrupt your live session
```

> **Heads-up:** `make all` rewrites `Sources/Info.plist` in place to stamp the
> version from the latest git tag (the `<!--VERSION-->` placeholder). That is
> expected — after a build, `git status` shows `Sources/Info.plist` as modified.
> It is how the version stays in sync with tags; commit it as part of a release.

Build requirements: macOS 13+ (universal binary: Apple Silicon + Intel). No
external packages.

## Testing

`make test` runs `dev-tools/smoke.sh`. It skips cases the current environment
can't safely run (e.g. a real blackout while the menu bar app is live — that
would interrupt your session). To cover everything, run it **twice**:

```bash
# Pass 1 — menu bar app running (covers [13] always-on-display battery release)
SMOKE_FULL=1 ./dev-tools/smoke.sh

# Pass 2 — menu bar app NOT running (covers [8] lid dim, [11] daemon battery
#          self-stop, [5] blackout/restore). Quit the app first:
launchctl bootout gui/$(id -u)/com.lidkeep.bar
pkill -x LidKeep
SMOKE_FULL=1 ./dev-tools/smoke.sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.lidkeep.bar.plist
```

> A menu bar app does **not** respond to `osascript -e 'quit app "LidKeep"'`.
> Use `launchctl bootout` + `pkill` (above), then re-`bootstrap` to restore the
> login item.

**The one rule:** `失败` (failures) must be `0`. Skips are fine (they are
environment-gated). Don't silence a failure by loosening the assertion — fix the
code or the test.

## Localization

All user-facing strings live in `Sources/Shared/L10n.swift` as a `zh → en` table
looked up by `L(_:)`. `dev-tools/check-l10n.py` enforces bidirectional parity
(no missing translation, no dead key) and must pass. Always run it after
touching strings:

```bash
python3 dev-tools/check-l10n.py .
```

## Signing / packaging

- Releases are **ad-hoc signed, not notarized** (no paid Apple Developer cert
  behind this project). See the README "Unsigned" section for the user impact.
- `make all` runs `codesign --deep`. There is a known self-lock: if a leftover
  `*.cstemp*` sits in `Contents/MacOS/`, `--deep` re-fails every time and the
  Makefile's `2>/dev/null` swallows the error. The Makefile now cleans that
  residue before signing; if you see a "linker-signed" build, delete the
  `*.cstemp*` files and rebuild.
- `packaging/make_dmg.sh` / `make_pkg.sh` build the distributables. Notarization
  scaffolding lives in `packaging/notarize.sh` (requires your own Developer ID).

## Pull requests

- Keep PRs focused. One logical change per PR is easier to review and revert.
- Run `make test` and `python3 dev-tools/check-l10n.py .` before pushing.
- The English README (`README.md`) and Chinese README (`README.zh-CN.md`) must
  stay in sync. If you change one, change the other.
- Update `CHANGELOG.md` under the `[Unreleased]` heading for user-visible
  changes.
- If your change touches the privileged helper or `sudoers` scope, call it out
  explicitly in the PR description (security-sensitive by design).

## Where to ask

Open a [Discussion](../../discussions) for questions, ideas, and "how do I…".
Use [Issues](../../issues) for reproducible bugs. For security-sensitive
reports, see [SECURITY.md](SECURITY.md).
