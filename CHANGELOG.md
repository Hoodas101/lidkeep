# Changelog

All notable changes to LidKeep are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

Versions before v2.0.0 shipped under the name **BlankScreen**; the product was
renamed to LidKeep at v2.0.0 (CLI name, app name, and all bundle identifiers
changed).

## [Unreleased]

## [2.2.3] — 2026-09-21
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

## [2.2.2] — 2026-09-16
- Per-power-source plans (plugged-in vs battery), compact status line, one
  shared core compiled by both targets.
- Added donation QR codes (WeChat / Alipay).

## [2.2.1] — 2026-09-12
- Rebuilt settings panel with recordable hotkey and custom battery floor /
  battery action.
- One-line installer for machines without Xcode.

## [2.2.0] — 2026-09-11
- Automatic update checks; dropped the v1.x rename compatibility layer.

## [2.1.0] — 2026-09-11
- "Check for Updates", About panel, and GitHub link in the menu.

## [2.0.0] — 2026-09-11
- **Renamed to LidKeep** and redesigned the app icon. Breaking: CLI/app/bundle
  identifiers changed; v1.x state is not migrated.

## [1.6.5] — 2026-09-11
- Exclusive power modes, visible power assertions, atomic config writes.

## [1.6.4] — 2026-09-11
- Lid blackout gets its own switch; icon redesigned.

## [1.6.3] — 2026-09-11
- Made lid blackout actually survive closing the lid.

## [1.6.2] — 2026-09-11
- Original app icon that reads clearly at every size.

## [1.6.1] — 2026-09-10
- Fall back to English when the system language is neither Chinese nor English.

## [1.6.0] — 2026-09-10
- English/Chinese UI that follows the system language.

## [1.5.2] — 2026-09-10
- Recognize remote-control apps holding `disablesleep`; auto blackout of the
  built-in display on lid close during anti-sleep.

## [1.5.1] — 2026-09-10
- Rewrote menu wording around the three core functions.

## [1.5.0] — 2026-09-10
- One-click lid-closed anti-sleep long-running mode in the menu bar app.

## [1.4.0] — 2026-09-10
- Multi-display blackout, `disablesleep` owner accounting, `doctor`/`version`/
  `toggle`, smoke tests.

## [1.3.2] — 2026-09-09
- Drag-and-drop `.dmg` alongside the `.pkg` installer.

## [1.3.1] — 2026-09-09
- One-click `nosleep setup`; fixed helper detection for non-root users.

## [1.3.0] — 2026-09-09
- Anti-sleep (`nosleep`): keep the machine awake during blackout, incl. lid
  closed / on battery.

## [1.2.0] — 2026-09-09
- Battery guard, visible failures, release checksums, `.pkg` installer.

## [1.1.1] — 2026-09-08
- Fixed stuck-black screen, `caffeinate` orphans, pid reuse; auto-detect
  Homebrew prefix (Apple Silicon vs Intel).

## [1.1.0] — 2026-09-08
- Initial release: blank the display while keeping the Mac awake.

[Unreleased]: ../../compare/v2.2.3...HEAD
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
