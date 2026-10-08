# Changelog

All notable changes to LidKeep are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

Versions before v2.0.0 shipped under the name **BlankScreen**; the product was
renamed to LidKeep at v2.0.0 (CLI name, app name, and all bundle identifiers
changed).

## [Unreleased]

## [2.2.6] - 2026-10-08

### Fixed

- **A failed lid-close daemon start retried every 15 seconds and notified on
  every attempt.** `setLidAwake` returned only a `Bool`, so the caller guessed
  the reason from `helperInstalled() ? "battery" : "helper"` — a file-existence
  check standing in for "can this actually run right now". When the privileged
  helper was installed but its authorization had gone stale, the failure was
  filed as a battery problem, and the "has this cause cleared?" test for battery
  problems (`!batteryBlocksStart`) is trivially true while on AC power. The
  patrol therefore dropped its backoff every 15 seconds, retried, failed, and
  posted another notification. One machine logged eight complete
  start → degrade-to-caffeinate → roll back → external-config-change → stop
  cycles inside two minutes. `setLidAwake` now returns a `LidAwakeBlocker`
  naming the real cause, each cause carries its own retry delay (60s for battery
  and thermal, 600s for anything the user must act on), and the patrol's
  clearing test is keyed to the specific cause. The new `helperUsable()` probe
  answers "does it work right now" where `helperInstalled()` answers "is it
  there at all".
- **The notification gate was only wired up on the app side.** The gate itself
  (`notifyGateOpen`, semantic key, 24-hour window) shipped with the app, but the
  CLI's `notify` took no key and every call went straight through. The CLI's
  own long-lived paths therefore had no dedupe at all: `nosleep on --system`
  degrading to adapter-only posted one notification per invocation, so a user
  retrying the command because it did not give the expected result got one
  notification per attempt. `notify` now takes the same key and window, and the
  two lasting conditions on the CLI side — a missing privileged helper and a
  failed brightness restore, the latter on both the one-shot daemon and the
  resident service — go through the gate. `regress.sh` asserts the CLI's
  signature carries the key, that both conditions are gated, and that the gate
  is actually called at runtime: the gap survived a previous round of fixes
  because nothing in the suite mentioned the gate, so "all green" said nothing
  about whether it was covered.
- **A persistent problem is now notified once a day, not once a cycle.** Every
  lasting condition (missing helper, stale authorization, overheating, a failed
  brightness restore) went through a bare `osascript` call, so the 15-second
  patrol turned a single problem into hundreds of notifications. `notifyUser`
  now takes a semantic key and a 24-hour window, and the key is reset when the
  condition genuinely clears. Calls that are the direct result of a user action
  pass no key and still fire every time.
- **A child process can no longer notify behind the parent's back.** The app
  spawns a fresh CLI process for every action, so an in-process dedupe table
  cannot see the duplicate. Background spawns now set `LIDKEEP_QUIET=1`, and
  both `notify` implementations return immediately when it is set.
- **The degraded rollback path was rewriting the user's power plan.** When
  system-level anti-sleep was unavailable, the rollback ran `nosleep off` with
  `--no-touch-plan` but not `--no-persist`, so the child process wrote
  `lidAwake: false` back to `config.json` while the parent kept projecting
  `true`. The config oscillated once per cycle, and the log filled with
  "power plan changed externally". Both flags are now passed.
- **Korean lost its word boundaries in the menu.** The status line is assembled
  from fragments and only inserts a separator for languages that need one;
  Korean was in the "concatenate directly" list alongside Chinese and Japanese,
  so the first line of the menu read `상태: 전원잠자지 않기`. Korean separates
  words with spaces, so it now gets the separator too.
- **A single command could permanently break the resident service, with no way
  back.** `lidkeep config --timeout 1e300` passed validation (it only checked
  `>= 0`), was written to `config.json`, and then crashed while printing the
  config — converting that `Double` to `Int` traps. Worse, the value was already
  on disk: every blackout after that hit the same trap, and the attempt to fix it
  (`config --timeout 43200`) crashed on its way out. Hand-editing the file was
  the only way back. `--timeout` now rejects anything above 31536000 seconds and
  anything non-finite, and the value is clamped on read, so a config that is
  already poisoned heals itself on the next run instead of bricking the service.
- **`--timeout` was unvalidated on three other paths.** `daemon`,
  `nosleep-daemon` and `nosleep on` took the value verbatim: `--timeout abc`
  became `nil`, which those paths read as "run forever", and it exited 0 saying
  nothing. All three validate now.
- **Quitting could leave the screen black forever.** `shutdown()` restored the
  brightness, and on failure started a retry timer — then called `exit(0)`
  immediately, so the timer never fired. The user got a notification reading
  "retrying continuously" and a black screen. Quitting now retries in-process
  and, if it still fails, writes the target brightness back to the state file so
  the next launch completes the restore.
- **The privileged helper deleted every disablesleep holder when `ps` was
  refused.** Its prune step decided "is this pid still ours?" purely from
  `ps -o comm=` output, and an empty string fell through to the catch-all branch —
  so on any machine that refuses the setuid `ps`, closing one holder turned the
  global switch off for the daemons still relying on it. It now checks liveness
  with `kill -0` first and keeps the holder whenever the process name cannot be
  read. `on` also warns instead of silently skipping its bookkeeping when the
  caller pid cannot be determined.
- **The menu bar app reloaded its own writes.** The modification-time baseline
  was only refreshed inside the reload path, while nine other write sites bypassed
  it — so every write was mistaken for an external change 0.3s later and replayed
  the full side-effect chain: re-register the hotkey, rebuild the battery timer,
  and replace the settings panel's edit copy, silently discarding whatever the
  user was in the middle of typing. All Bar-side writes now go through wrappers
  that stamp the baseline. The 225 reloads this produced (3 within 6 seconds in
  one log) are gone.
- **Battery protection could switch itself off silently.** When `pmset -g batt`
  could not be read or contained no percentage, the parsed value stayed at its
  default of 100 — every `percent <= batteryFloor` guard then passed while the UI
  showed "100%". An unreadable battery is now treated as empty, so the guards
  hold. A new `percentKnown` field distinguishes a real reading from a fallback.
- **Restoring brightness no longer forces a value the user never chose.** The
  brightness read looks only at the main display while the write covers every
  display; when the read failed, the restore silently pulled the screen to 50%.
  It now uses a low 0.35 and says so, and per-display bookkeeping lets the UI
  report which screen could not be blanked instead of claiming success.
- **Subprocess calls had no timeout.** `pmset` is called by the battery guard,
  the thermal guard and the power-source switch, and `sudo -n` waits on
  authorization. A hung child froze the main loop outright. `runCapture` now
  times out at 5s and returns nil so callers degrade; `sh` returns -1 to
  distinguish "did not run" from "ran and failed".
- **Force-quitting a stale app instance left the system switch on.** The killed
  instance never ran its cleanup. Its caffeinate children were collected, but
  `disablesleep` was not — and resetting it unconditionally would have cancelled
  a running lid daemon's work, so the reaper now only resets when no daemon
  holds it, and says what it did either way.
- **Interface language no longer needs a restart.** `L10n.lang` was a `static
  let`, evaluated once, so `lidkeep config --lang` changed the file while the
  running app kept the old language. It is now computed per access.
- **`osascript` quoting.** The privileged-install path escaped only `\` and `"`,
  but the string is re-parsed by `sh`, so a home directory containing an
  apostrophe truncated the command — and the caller reported success. It now
  uses AppleScript's `quoted form of`.
- **The menu bar app silently reset the lid-close plan every 30 seconds.**
  Reconciling the lid daemon shells out to `nosleep off`, and that command
  deliberately writes the current power plan's lid setting back to "sleep" —
  correct when the user typed it, wrong when the app merely wanted a daemon
  stopped. The periodic reconcile does exactly that, so choosing "keep awake
  when closed" lasted until the next sweep, and nothing in the log mentioned it.
  The app's own cleanup paths now pass `--no-touch-plan`; the plan is only
  rewritten when the user asks for it, or when the battery guard releases
  everything on purpose.
- **`lidkeep toggle` did nothing at all against a CLI-resident service.** The
  command file was written but never read: the CLI service only listened for
  signals, and `toggle` expressed "flip the state" as SIGUSR1, which means
  "blank". With the screen already black, `blackout()` returned on its
  `guard !blacked` and `restore()` was never reached — yet the command printed
  success and exited 0. The same command worked when the menu bar app was the
  resident process, so the behaviour depended on which of the two was running.
  The CLI service now reads the command file exactly like the app does
  (`off` / `on` / `toggle`), `toggle` no longer signals at all, and an
  unacknowledged toggle exits non-zero instead of claiming success.
- Orphaned `config.json.tmp.<pid>` files are cleaned up at startup. Thirty-one
  had accumulated on one machine, the oldest from 2026-09-21.
- **"disabled sleep again" was printed whether or not the switch moved.** Both
  the stale-daemon cleanup and the daemon's own shutdown path called
  `helperExec("off")`, discarded the result, and logged success. A privileged
  helper that is installed but no longer authorized returns nil there, so the
  log said the global sleep switch had been cleared while `SleepDisabled` was
  still 1 — the machine would not sleep, and every surface in the app said it
  would. Both paths now re-read the real state with an unprivileged `pmset -g`
  and say plainly when the reset did not take.
- **A full disk could strand the screen black.** The state file that records
  "currently blanked, and this is the brightness to come back to" was written
  with `try?`. If that write failed, the process went on to set brightness to 0
  with no record on disk, so nothing knew what to restore — including the
  next-launch recovery path. All three blanking entry points now refuse to
  blank, and say why, when the state file cannot be written.
- The quit path released one sleep assertion and not the other. `shutdown()`
  stopped `caffeinate -is` but left `caffeinate -d` to exit on its own. Both
  carry `-w <pid>`, so nothing leaked — this is about the asymmetry, which is
  the kind that gets copied the next time a third assertion is added, silently.
- **The quit-time recovery note was written with `try?` while the notification
  claimed it had been.** When the brightness could not be restored on quit,
  `shutdown()` wrote the target brightness to the state file for the next
  launch to pick up — and told the user "it will recover on next launch"
  whether or not that write succeeded. On a full disk nothing was recorded, the
  next launch had nothing to recover from, and the only thing the user had was a
  notification promising otherwise. Both the write and the message are now
  checked; when the note cannot be written, the user is told to restore the
  brightness by hand, with the value.
- **An unknown option was ignored, and the command still exited 0.**
  `lidkeep config --battary 50` — one missing `e` — matched no branch, was
  skipped whole, and the command then ran to completion reporting success. The
  user saw a successful command and a setting that had not changed, which is
  worse than an error: they act on it. `config`, `plan`, `daemon`,
  `nosleep-daemon` and `nosleep on` now reject unknown `-`-prefixed arguments
  and list the options they do accept. Bare words are left alone — those are
  subcommands, dispatched by the outer switch.
- **A missing option value was reported as an unknown option.** `lidkeep config
  --battery` failed the `i + 1 < count` guard, fell through to the unknown-option
  branch, and pointed at the wrong problem. Values-taking options are now
  pre-scanned per subcommand, and the message names the option that lost its
  value. The pre-scan looks for a following `--` rather than a following `-`, so
  `lidkeep config --timeout -1` still reaches value validation (and is still
  rejected) instead of being called incomplete.
- **`off` and `on` exited 0 even when nothing happened.** Both already said so
  in words — "指令已发送，3s 内未确认" — and then exited 0, so a script reading
  `lidkeep off && echo done` reported success with the screen still lit. Worse,
  `on` against a one-shot daemon sent SIGTERM, never checked whether the process
  actually died, and printed "已恢复显示" unconditionally. Both now wait for the
  state to change, say what really happened, and exit non-zero when it did not —
  the same rule P1-2 established for `toggle`.
- **One thermal-guard assertion had never run.** In the smoke script the shell
  function `newlog` was defined one line *after* its first use. bash resolves
  function bodies at call time, so that is not a syntax error — the call printed
  `newlog: command not found` on stderr, the script does not use `set -e`, and
  the flag it fed stayed `0`. Every run therefore skipped the check that the
  `-is` sleep assertion is released alongside the rest, which is the exact
  regression `releaseForThermal` once shipped. The report said green. The
  definition now precedes the call, and `regress.sh` asserts both the ordering
  and that the script parses (`bash -n`) — a half-run script otherwise loses
  the second half of its results without saying so.
- **Two "command sent but not confirmed" messages mixed bracket styles.** The
  Japanese translations wrapped a half-width colon inside a full-width
  opening bracket, and the Korean ones ran the bracket straight into the verb
  with no space. Both are only seen when a command fails, which is exactly the
  copy an author never sees while writing. The new `已发送恢复指令…` string went
  into all six tables, and the two existing siblings were corrected — verified
  by rendering all seven languages, since a per-fragment check cannot see a
  concatenation problem.
- **Two battery-guard cases had never run on a locked-down machine.** The smoke
  suite distinguishes the three `caffeinate` assertions (`-d` / `-is` / `-dis`)
  by reading process command lines through `ps`, and `ps` is setuid — a
  restricted environment refuses to execute it. Both cases therefore skipped
  themselves with "ps unavailable here", and they cover exactly the failure that
  matters: the battery floor failing to release a held assertion, so the Mac
  discharges itself to a shutdown with the UI still saying everything is on.
  `dev-tools/caff-args` now reads the same data through `KERN_PROCARGS2` and
  `proc_listpids`, reusing `Ownership.swift` — the approach that guard already
  uses for daemon ownership, for the same reason. It matches each parameter
  exactly, so `-d` never matches `-dis`. `make test` now depends on
  `make dev-tools`; otherwise a clean checkout skips them again on the first
  run, and the report does not look any different.
- **One battery-guard case failed for reasons outside the guard.** It also
  depends on `thermalBlocksStart()`, whose simulation hook falls back to the
  real `ProcessInfo.thermalState` whenever the hook file is absent. A machine
  that had just run the whole suite twice was genuinely at `serious`, so the
  thermal guard released both assertions inside the observation window: the
  test reported the assertion still held while the log plainly said
  `过热保护触发`. Both cases now pin the hook to `nominal` before they start.
  The judgement was never wrong; the environment was reaching in.
- **The keep-awake case could never arm its assertion.** It enabled
  `keepAwake` on the AC plan only (`plan --ac --keep-awake on`), but the app
  applies the plan for the power source it is actually on. The preceding case
  leaves the simulated battery on battery, so that edit did nothing to the
  running app and the assertion never appeared — reported as "assertion not
  armed", which points at brightness interfaces and the privileged helper,
  neither of which is involved. Both plans are now enabled, the matching
  teardown disables both, and the wait accounts for the patrol interval.
  The `caffeinate -is` battery-floor release now actually runs on this machine
  for the first time.
- **`install-remote.sh --help` printed a stray `set -u` line.** The usage text
  was sliced with hard-coded line numbers, so it broke the moment the header
  comment got shorter. It now stops at the end of the comment block.
- **The installer's fallback version was pinned at 2.2.2.** When the version
  lookup failed (rate limit, offline, CN network) it silently installed an old
  release. Bumped, and the release workflow now fails if the pinned value and
  the tag ever drift apart.

### Changed

- **"Not in effect" now says why, on the row it belongs to.** The menu used to
  stack two markers onto the parent plan row ("awake with the lid closed is not
  active", "stay-awake after display sleep is not active"), leaving the user to
  map each one back to the checkbox it referred to — and never saying what was
  wrong. Each marker now sits on the affected row and carries the reason:
  `When the lid closes: Keep awake (not active: install the privileged helper
  first)`. The parent row keeps a single `⚠` so the problem is visible before
  the submenu is opened. The settings panel lists the same items under
  `— not active:`, each with its reason, and only when something is actually
  wrong.
- **Two notifications removed.** Switching power source popped a notification
  restating the new plan, and startup popped another when it stopped a leftover
  daemon that the user's own plan called for. Both repeated something the menu
  already shows, and together they accounted for most of "why does this notify
  me every time I open it". The log records both; the Notification Center does
  not.
- **Settings copy cut to one line per section.** The lid, hotkey, timeout,
  battery and update sections carried three-sentence explanations of
  implementation detail. Each is now a single sentence naming the dependency or
  the default; what was cut was either already shown by the adjacent control or
  belonged in the code comment. 30 stale strings were removed from all six
  language tables, 22 new ones added.

- **Uninstall instructions.** The README now has an `## Uninstall` section for
  the common case: installed from the one-liner, no clone on disk. The installer
  used to tell you to "use the menu item", but that item only removes the
  privileged helper, and the README section it pointed at did not exist.
- Localization: `check-l10n.py` **fails** on a translation that is byte-identical
  to its Chinese key, instead of only warning — "untranslated=10" used to pass
  CI. The two Japanese/Korean entries that really were untranslated are fixed;
  entries that are legitimately identical live in an explicit whitelist.
  `make l10n-audit` now exposes the concatenation audit, which until now had no
  entry point outside the docs.
- Docs: corrected the `modFlags` value for `⌃⌥⌘` (917504 was ⇧⌃⌥), removed a
  CONTRIBUTING reference to a README section that does not exist, refreshed the
  localization notes, restored the two known limitations missing from the Chinese
  DETAILS, and noted which companion docs are Chinese-only.

### Added

- `make copy-preview` — renders the composed strings (name + marker + reason,
  joined clauses) in all seven languages so the result can be read rather than
  inferred. `check-l10n.py` proves every fragment has a translation; it cannot
  prove the fragments read correctly once concatenated, which is how the Korean
  word-boundary bug above stayed invisible.
- `dev-tools/preview-copy/main.swift` — the renderer behind that target. It is
  compiled against the real `Sources/Shared/L10n*.swift`, so it cannot drift
  from the app's strings.
- `dev-tools/regress.sh` — 58 checks covering the fixes above. Read-only with
  respect to the screen: it never runs `off`/`on`, and it restores `config.json`
  on exit. It is wired into `make test` (and `make regress`), because a
  regression suite with no entry point is a suite nobody runs.
- `dev-tools/sync-helper-to-embed.py` — copies `packaging/helper/com.lidkeep.pmset`
  into the copy embedded in `CLI/main.swift`. The two must stay byte-identical
  (smoke.sh diffs them), and the embedded one is the source of truth that
  `nosleep write-assets` writes from.
- `dev-tools/sync-timeout-l10n.py`, `sync-display-l10n.py`, `sync-p0-l10n.py`,
  `sync-toggle-l10n.py`, `sync-notify-l10n.py` — insert new strings into all six
  language tables, and delete keys that lost their call site. Editing them by
  hand is error-prone: the keys contain colons, so a regex-based edit reliably
  eats the neighbouring entry.

## [2.2.5] - 2026-10-02
- **Seven UI languages.** Chinese, English, Japanese, Korean, German, French and
  Spanish, 539 strings each at 100% coverage. Follows the system language; a
  language outside the set falls back to English. Override with `LIDKEEP_LANG`
  or `"lang"` in `config.json` (`auto` / `zh` / `en` / `ja` / `ko` / `de` /
  `fr` / `es`). The long-form help text is still Chinese/English only.
- **Thermal protection.** At `critical` thermal state the anti-sleep assertion is
  released so the machine can throttle down and cool; `serious` only notifies.
  Nothing is written to the config — heat is transient and must not leave a
  persistent mark on the user's power plan.
- **Notarization tooling.** `packaging/notarize.sh` rewritten with a `--dry-run`
  mode that exercises signing → dmg/pkg/zip → self-check using ad-hoc +
  hardened runtime, so failures surface before buying a Developer ID certificate.
- **Fix:** `/bin/bash` on macOS is 3.2 and folds a following multibyte character
  into the variable name (`$VER）` is read as `VER）`), which aborts under
  `set -u`. Script variables are now written `${VAR}`; a smoke check guards it.
- **Fix:** thermal protection now actually releases everything, and actually
  leaves the config alone. Both defects were found by *running* it — the feature
  had shipped untested, and every static check was green while it was broken:
  - Stopping the lid daemon went through `lidkeep nosleep off`, which cleared
    the persistent lid-awake flag **unconditionally**. The bar app's
    `persist: false` only stops the parent from writing; it cannot stop its own
    child. One hot compile therefore permanently dropped "keep awake when the
    lid closes" — exactly what the feature promises never to do. The command now
    accepts `--no-persist` and the thermal path passes it.
  - The "stay awake after the display sleeps" assertion (`caffeinate -is`) was
    never released at all: `syncKeepAwake()` early-returns when the assertion is
    already held, so the guard logged the release, notified the user, and left
    the machine blocked from sleeping. It is now stopped explicitly.
  - The smoke test now holds *both* assertions so that releasing only one fails
    the check, and it asserts the config is byte-identical across the whole
    cycle.

## [2.2.3] - 2026-09-21
- **Battery guard now covers "Keep the display on".** This was the only
  power-draining path the floor check missed — a laptop on battery with the
  screen forced on would drain to a hard shutdown. The floor now refuses to
  start it and releases it on hit (restore-only mode also releases it, not just
  restore-the-screen).
- **CLI respects `hotkeyEnabled`.** `lidkeep config --hotkey off` now actually
  unregisters the global hotkey in the CLI service/daemon (previously ignored).
- **Fixed a `runCapture` pipe deadlock.** `stderr` is now discarded instead of
  left on an unread pipe that could hang the caller.
- **Stopping a stale lid daemon now notifies.** When the current power plan
  doesn't require lid-closed running, the app stops a leftover daemon and tells
  the user (instead of silently undoing a manual command).
- **UX:** slider commits only on release (not every drag tick); power-source
  query is cached 1 s to avoid spawning `pmset` per UI refresh; `doctor`
  reports the actual power plans, not just the derived booleans.
- **Build:** fixed a `codesign --deep` self-lock from leftover `*.cstemp*`
  files (the app was silently stuck at linker-signed).
- Internals: removed dead code, tightened comments, added a smoke test for the
  always-on-display battery release.

## [2.2.2] - 2026-09-16
- Per-power-source plans (plugged-in vs battery), compact status line, one
  shared core compiled by both targets.
- Added donation QR codes (WeChat / Alipay).

## [2.2.1] - 2026-09-12
- Rebuilt settings panel with recordable hotkey and custom battery floor /
  battery action.
- One-line installer for machines without Xcode.

## [2.2.0] - 2026-09-11
- Automatic update checks; dropped the v1.x rename compatibility layer.

## [2.1.0] - 2026-09-11
- "Check for Updates", About panel, and GitHub link in the menu.

## [2.0.0] - 2026-09-11
- **Renamed to LidKeep** and redesigned the app icon. Breaking: CLI/app/bundle
  identifiers changed; v1.x state is not migrated.

## [1.6.5] - 2026-09-11
- Exclusive power modes, visible power assertions, atomic config writes.

## [1.6.4] - 2026-09-11
- Lid blackout gets its own switch; icon redesigned.

## [1.6.3] - 2026-09-11
- Made lid blackout actually survive closing the lid.

## [1.6.2] - 2026-09-11
- Original app icon that reads clearly at every size.

## [1.6.1] - 2026-09-10
- Fall back to English when the system language is neither Chinese nor English.

## [1.6.0] - 2026-09-10
- English/Chinese UI that follows the system language.

## [1.5.2] - 2026-09-10
- Recognize remote-control apps holding `disablesleep`; auto blackout of the
  built-in display on lid close during anti-sleep.

## [1.5.1] - 2026-09-10
- Rewrote menu wording around the three core functions.

## [1.5.0] - 2026-09-10
- One-click lid-closed anti-sleep long-running mode in the menu bar app.

## [1.4.0] - 2026-09-10
- Multi-display blackout, `disablesleep` owner accounting, `doctor`/`version`/
  `toggle`, smoke tests.

## [1.3.2] - 2026-09-09
- Drag-and-drop `.dmg` alongside the `.pkg` installer.

## [1.3.1] - 2026-09-09
- One-click `nosleep setup`; fixed helper detection for non-root users.

## [1.3.0] - 2026-09-09
- Anti-sleep (`nosleep`): keep the machine awake during blackout, incl. lid
  closed / on battery.

## [1.2.0] - 2026-09-09
- Battery guard, visible failures, release checksums, `.pkg` installer.

## [1.1.1] - 2026-09-08
- Fixed stuck-black screen, `caffeinate` orphans, pid reuse; auto-detect
  Homebrew prefix (Apple Silicon vs Intel).

## [1.1.0] - 2026-09-08
- Initial release: blank the display while keeping the Mac awake.

[Unreleased]: ../../compare/v2.2.6...HEAD
[2.2.6]: ../../compare/v2.2.5...v2.2.6
[2.2.5]: ../../compare/v2.2.3...v2.2.5
[2.2.3]: ../../compare/v2.2.2...v2.2.3
[2.2.2]: ../../compare/v2.2.1...v2.2.2
[2.2.1]: ../../compare/v2.2.0...v2.2.1
[2.2.0]: ../../compare/v2.1.0...v2.2.0
[2.1.0]: ../../compare/v2.0.0...v2.1.0
[2.0.0]: ../../compare/v1.6.5...v2.0.0
[1.6.5]: ../../compare/v1.6.4...v1.6.5
[1.6.4]: ../../compare/v1.6.3...v1.6.4
[1.6.3]: ../../compare/v1.6.2...v1.6.3
[1.6.2]: ../../compare/v1.6.1...v1.6.2
[1.6.1]: ../../compare/v1.6.0...v1.6.1
[1.6.0]: ../../compare/v1.5.2...v1.6.0
[1.5.2]: ../../compare/v1.5.1...v1.5.2
[1.5.1]: ../../compare/v1.5.0...v1.5.1
[1.5.0]: ../../compare/v1.4.0...v1.5.0
[1.4.0]: ../../compare/v1.3.2...v1.4.0
[1.3.2]: ../../compare/v1.3.1...v1.3.2
[1.3.1]: ../../compare/v1.3.0...v1.3.1
[1.3.0]: ../../compare/v1.2.0...v1.3.0
[1.2.0]: ../../compare/v1.1.1...v1.2.0
[1.1.1]: ../../compare/v1.1.0...v1.1.1
[1.1.0]: ../../releases/tag/v1.1.0
