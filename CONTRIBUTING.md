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
    `autoNosleep` / `keepDisplayOn` / `lidAwake` are *derived* "what the active
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

# 4. Optional: build and install in one step (app + CLI)
./install.sh              # or: ./install.sh --cli-only, to skip the app
```

> **Heads-up:** `make all` rewrites `Sources/Info.plist` in place to stamp the
> version from the latest git tag (the `<!--VERSION-->` placeholder). That is
> expected — after a build, `git status` shows `Sources/Info.plist` as modified.
> It is how the version stays in sync with tags; commit it as part of a release.

Build requirements: macOS 13+ (universal binary: Apple Silicon + Intel). No
external packages.

## Testing

`make test` runs three layers, ordered fast → slow and static → dynamic:

```bash
make test    # 1. check-l10n.py  — key coverage across all six tables (blocking)
             # 2. regress.sh     — 58 source-level assertions on the fixes above
             # 3. smoke.sh       — end-to-end, real blackout / anti-sleep paths
```

`dev-tools/regress.sh` never touches the screen and finishes in seconds, so it
is wired into `make test` rather than left as a target nobody remembers to run —
a regression suite with no entry point is a suite that never catches anything.
Use `make regress` to run only that layer while iterating.

`dev-tools/smoke.sh` skips cases the current environment can't safely run (e.g.
a real blackout while the menu bar app is live — that would interrupt your
session). To cover everything, run it **twice**:

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

Seven languages ship: `zh` (source), `en`, `ja`, `ko`, `de`, `fr`, `es`.

**Chinese is the source language, and the Chinese string *is* the key.** Call
sites read `L("关闭显示器")`; `Sources/Shared/L10n.swift` is the lookup engine
(it holds no translations) and each `L10nXX.swift` holds one language's table.
Lookup degrades in three steps — current language → English → the Chinese key —
so a missing entry shows Chinese rather than a blank or a leaked key.

**Adding one string therefore means adding it to six files.** Three guards cover
this:

```bash
make test           # check-l10n.py (blocking) + regress.sh + smoke.sh
make l10n-audit     # audit-l10n-concat.py — run by hand after touching strings
make copy-preview   # render the composed strings in all seven languages
```

`check-l10n.py` blocks on the four structural errors (call site missing from the
table, dead key, orphan key, duplicate key) plus a fifth: **a translation that is
byte-identical to its Chinese key**, which is almost always untranslated. A few
entries are genuinely identical — full-width punctuation, the shared kanji in
「秒」, the ideographic space Japanese uses for alignment — and those live in the
`SAME_OK` whitelist at the top of the script. Adding to that whitelist is a
deliberate act with a written reason, not a way to silence the check.

`audit-l10n-concat.py` catches the other class of defect: keys are *fragments*
joined with `+`, so a Latin-script translation can glue together
(`power;on battery`) or push a bracket to the wrong side. Chinese hides this
completely, which is why it needs a tool of its own. It stays out of `make test`
because its last section needs a human eye.

`make copy-preview` renders the composed strings — name + marker + reason, joined
clauses — in all seven languages, so you can read the result instead of
inferring it. A per-fragment check cannot see a concatenation problem; that is
how the Korean word-boundary bug survived a whole release.

If you can't read a language you're adding a string for, write the English entry
and say so in the PR — a rough guess in six languages is harder to fix later
than an honest gap.

## A note on the code comments

Comments in `Sources/` are **mostly Chinese** (roughly 9 in 10) — that is the
maintainer's working language, and translating every comment is not a goal.
`Sources/Shared/` is the part worth reading no matter what language you speak
(it is the single implementation both targets compile), so comment there in
English if you're adding to it. Elsewhere, English comments are welcome but
never required.

## Signing / packaging

- Releases are **ad-hoc signed, not notarized** (no paid Apple Developer cert
  behind this project). See the "One manual step" note under **Install** in the
  README for the user impact.
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
