# LidKeep — 完整说明

This is the long-form companion to [README.md](../README.md). If you only want to
install it and turn the screen off, the README is enough — come back here for the
full command list, the anti-sleep and privileged-helper design, the measured
behavior behind the brightness trick, thermal protection, FAQ and development.

- [Usage](#usage)
- [Anti-sleep (closed lid / battery / headless)](#anti-sleep-closed-lid--battery--headless)
- [How it works](#how-it-works)
- [Thermal protection](#thermal-protection)
- [Language](#language)
- [Details worth knowing](#details-worth-knowing)
- [Requirements](#requirements)
- [FAQ](#faq)
- [Uninstall](#uninstall)
- [Development](#development)
- [Known limitations](#known-limitations)

---

## Usage

**Menu bar app** — click ☀ / 🌙 in the menu bar:

- **Turn Display Off** — black out now, machine keeps running (click again or press the hotkey to restore)
- **Status: … ▸** — the title *is* the current status (e.g. `Status: Power · Keep awake`), and it edits whichever plan is active right now
- **Install Privileged Helper (first run)…** — lets "When the lid closes ▸ Keep awake" cover battery and lid (one password prompt)
- **Settings…** — four tabs: General / Hotkey / Battery / Other
- **Hotkey Self-test** — synthesizes your hotkey once and verifies the delivery path (no side effects)
- **Open Log**

The four settings tabs cover: **General** (both power plans side by side, restore brightness, blank the display when the lid closes), **Hotkey** (record any combination, enable/disable the global hotkey, fallback timeout), **Battery** (custom floor + what happens when it is hit), and **Other** (launch at login, automatic update checks, safety note).

**CLI**:

```bash
lidkeep off                    # black out now (one-shot daemon, auto-restores after timeout)
lidkeep off --timeout 3600     # custom fallback timeout
lidkeep on                     # restore the display
lidkeep toggle                 # one-command switch — handy for hotkey tools and remote scripts
lidkeep status                 # state, including power source and battery level
lidkeep doctor                 # full self-check: display control, processes, leftovers
lidkeep version                # print version (include it when reporting issues)
lidkeep bright 0.5             # read/write system brightness directly
lidkeep service install        # run the CLI as a launchd service (menu app not required)
lidkeep config --key 11 --mods ctrl,alt,cmd --timeout 43200
lidkeep config --battery 20    # battery floor %: refuse/exit blackout below it (0 = off)
lidkeep config --auto-nosleep  # link anti-sleep to blackout; auto-reset on restore
lidkeep plan                    # show both power plans and which one is active right now
lidkeep plan --ac --lid nothing                  # lid-closed running while plugged in
lidkeep plan --battery --keep-awake off --display-on on
lidkeep plan --keep-awake on    # no --ac/--battery = change both plans at once
```

`lidkeep plan` edits the same plans the menu bar uses (`--lid sleep|nothing`, `--keep-awake on|off`, `--display-on on|off`). The settings panel is the friendlier way in; this exists so scripts and remote shells can do it too.

Default hotkey: **⌃⌥⌘B**. The combo must include at least one modifier (⌘/⌃/⌥/⇧) — macOS rejects global hotkeys without one.

**Multiple displays:** blackout applies to every online display. However, most HDMI/DVI/DP external monitors don't support software brightness, so those panels can't be dimmed — `lidkeep doctor` names the exact display instead of leaving you guessing.

## Anti-sleep (closed lid / battery / headless)

Blackout only turns the backlight off — the system itself still sleeps on schedule. If the machine must keep working while blacked out (remote access, downloads, closed-clamshell use), enable anti-sleep:

```bash
lidkeep nosleep setup                  # one command: install helper + blackout linkage + start anti-sleep
lidkeep nosleep on                     # process-level (caffeinate; effective on AC power only)
lidkeep nosleep on --system            # system-level (covers battery + lid; requires the helper)
lidkeep nosleep on --timeout 3600      # auto-stop after a duration
lidkeep nosleep status                 # level / power source / uptime
lidkeep nosleep off                    # stop and reset
```

**Lid-closed anti-sleep**: open **When the lid closes** in the menu bar and pick **Keep awake** — no terminal needed. The built-in panel turns off, the machine keeps running, and downloads / remote access / external displays / long tasks all keep going. The daemon polls the SMC lid switch (MSLD key); on lid close it zeroes the built-in display brightness and restores it when the lid opens — the built-in panel only, external displays are never touched; when the daemon stops (battery floor / timeout / manual off) the brightness is restored too, never leaving a black screen behind. Turn it off separately with **Blank the built-in display when the lid closes** on the General tab. The flag is saved in config; the daemon is restored automatically after app or system restarts.

**Why does the system level need a privileged helper?** Per `man caffeinate`, the `-s` assertion is effective **on AC power only**. Covering battery and closed-lid requires `pmset disablesleep`, which must run as root. Install the helper once (asks for your admin password):

```bash
sudo lidkeep nosleep install-helper    # least privilege: sudoers limited to this tool, 4 whitelisted args
lidkeep nosleep detect                 # check disablesleep support on this system
sudo lidkeep nosleep uninstall-helper  # uninstall (resets disablesleep before removal)
```

Safety design:

- The helper is a whitelisted script that only accepts `on` / `off` / `status` / `detect` — it cannot be abused to run arbitrary commands
- sudoers grants a single user, running as root, exactly those four arguments
- Uninstall resets `disablesleep 0` *before* deleting the helper — no "system never sleeps again" leftovers
- A boot-time LaunchDaemon plus a self-heal check on every start reset any state left by a crashed process
- **Owner accounting:** `disablesleep` is a single global switch that "blackout-linked anti-sleep" and "manual anti-sleep" may both depend on. The helper records each owner, so when one stops it only unregisters itself — it never disables the anti-sleep the other one still relies on. (Ledger lives in `/var/db/lidkeep-nosleep`, owned by root; unprivileged users can't forge owners.)
- **Coexists with remote-control apps:** ToDesk / Sunlogin / UURemote / TeamViewer and friends use the same switch to stay reachable. When one is running, `doctor` reports "held by a remote-control app" instead of flagging it as a leftover to fix
- The battery floor applies to anti-sleep too — closed lid + battery + no sleep is the fastest way to drain a battery

## How it works

Instead of letting macOS put the display to sleep (which kills the framebuffer and breaks screen capture), LidKeep sets the **system brightness to 0** and holds a `caffeinate -di` assertion so the display pipeline stays fully powered. Verified behavior:

| Probe | Normal | Blacked out |
|---|---|---|
| Screenshot content | rendered | fully rendered (not painted black) |
| Built-in brightness | e.g. 0.41 | **0.0** — backlight fully off, the panel emits no light |
| `CGDisplayIsAsleep()` | 0 | **0** — display never sleeps |
| Display power state | 4 (max) | **4** (max) |

The trade-off is deliberate: true display sleep saves ~0.5–1.5 W more (backlight off alone saves roughly 1–2 W, up to ~15–30% of a lightly loaded machine), but it makes remote frames unavailable. LidKeep keeps the machine fully remote-controllable.

## Thermal protection

A Mac held awake with the lid closed — in a bag, on a sofa — has nowhere left to put its heat. LidKeep reads `ProcessInfo.thermalState` (a public API, no permission of any kind) every 30 s and reacts in two tiers:

| Thermal state | What LidKeep does |
|---|---|
| `serious` | Keeps everything running; notifies you once that macOS has started throttling |
| `critical` | Releases every assertion (blackout, anti-sleep, display-on) so the machine can throttle down and cool |

**Nothing is written to your config.** Heat is a transient state, so the moment it falls back to `nominal` / `fair` your power plan is re-applied exactly as you left it. This is the one place LidKeep deliberately does *not* copy the battery guard: a battery floor is a setting you meant to keep, a hot chassis is not. One long compile that nudges the machine into `critical` must never cost you your "keep awake when the lid closes" preference.

There is no switch for it. The guard is unconditional, costs a single closure call every 30 s while idle, and exists because a released assertion is recoverable while a cooked machine is not.

## Language

**Follows your system**: seven languages ship with the app — Chinese, English, Japanese, Korean, German, French, and Spanish. Your system language picks one; a language that isn't among them falls back to English. The menu bar app and the CLI always match — nothing to configure.

To switch it temporarily or permanently: `LIDKEEP_LANG=en lidkeep doctor`, or set `"lang": "en"` in `~/Library/Application Support/LidKeep/config.json`. The config accepts `auto` (default) / `zh` / `en` / `ja` / `ko` / `de` / `fr` / `es`, and the environment variable wins over it.

The long-form help text is written in Chinese and English only; every other language gets the English version rather than Chinese you may not read.

## Details worth knowing

- **No grants needed for the hotkey.** The global hotkey uses the Carbon `RegisterEventHotKey` API, dispatched by WindowServer itself — no Accessibility or Input Monitoring grants, and it keeps working after every rebuild (ad-hoc signed binaries lose TCC grants on each recompile, the most common trap for small tools like this). **One exception:** the lid-closed "Keep awake" mode needs the privileged helper below, which asks for your admin password **once** (see "Why does the system level need a privileged helper?" and [SECURITY.md](../SECURITY.md)).
- **Crash-safe.** If the app is killed while the screen is black, the next launch restores your previous brightness automatically. A configurable fallback timeout (default 12 h) is the last safety net.
- **Battery guard.** Only on battery and discharging: below the floor (default 20%) a blackout is refused, and during a blackout the level is re-checked every 30 s — cross the floor and the display comes back with a notification. No effect on AC power. Disable with `lidkeep config --battery 0` or in the settings panel.
- **CLI and app share state.** `lidkeep on` over SSH can restore a screen the menu bar app turned off, and vice versa.
- **Single instance.** Launching a second copy takes over cleanly and kills orphaned `caffeinate` helpers.
- **Update & about from the menu.** "View on GitHub" opens the repo in one click; "About LidKeep" shows the version, commit and license; "Check for Updates…" queries the GitHub Releases API and links to the download page when a newer version exists.
- **Automatic update checks** (on by default, switchable in Settings). The app quietly reads the latest version number once every 24 hours and only records the timestamp on **success** — a failed check is retried on the next heartbeat instead of leaving you unchecked for a whole day. A newer release shows a `⬆` badge in the menu bar and puts an "open the release page" entry at the top of the menu; nothing interrupts you, and the reminder stays until you actually install the new version. The request only reads a public version number and uploads nothing about your Mac.

## Requirements

- macOS 13 Ventura or later (built as a universal binary: Apple Silicon + Intel)
- Built-in display (brightness control via DisplayServices; external monitors without DDC support are not affected)

## FAQ

**Hotkey doesn't trigger.** Check the ⚠ badge next to the menu bar icon. Three common causes: the combo is taken by another app (pick another), the combo has no modifier, or the app was just reinstalled (quit and relaunch once). The hotkey itself never needs any permission.

**Does an auto-brightness sensor fight the blackout?** The app re-asserts brightness 0 twice a second, so ambient-light changes won't light the screen up.

**Why not just `pmset displaysleepnow`?** True display sleep tears down the framebuffer — remote viewers get nothing. Many apps (browsers, Electron apps) also hold `NoDisplaySleepAssertion`, which blocks display sleep entirely. Brightness-zeroing works everywhere and is the only method that keeps remote frames flowing.

**Does it work over SSH, or when the screen is locked?** Yes. The CLI (`lidkeep off/on/status`) runs over SSH, and locking the screen (⌃⌘Q) is separate from the display's brightness state — blackout and anti-sleep keep working whether the screen is locked or not.

**Headless Mac (Mac mini with no built-in display)?** There's no backlight to cut, so blackout has nothing to do; but `lidkeep nosleep` still keeps the machine awake for remote access and downloads, which is the usual reason to run one headless.

**Does it clash with Focus, Do Not Disturb, or Night Shift?** No — those are unrelated subsystems. Blackout only sets brightness to 0 and holds a `caffeinate` assertion; it never touches notification, focus, or color settings.

## Uninstall

```bash
./uninstall.sh           # or: make uninstall
# config/logs (optional): rm -rf ~/Library/Application\ Support/LidKeep
```

## Development

```bash
make            # build CLI + app into build/
make test       # end-to-end smoke test (arg validation, config round-trip, anti-sleep, asset parity, l10n parity)
make dev-tools  # build debugging helpers into build/dev-tools/
make clean
```

Source layout (Swift requires the top-level file to be named `main.swift`, so each target gets its own directory):

- `Sources/CLI/main.swift` — command-line tool
- `Sources/Bar/main.swift` — menu bar app
- `Sources/Shared/` — the **single implementation** both targets compile (config model, system state and brightness, power plans, process ownership, localization, version)
- `dev-tools/` — helpers plus `smoke.sh`, the `check-l10n.py` copy guard, and `audit-l10n-concat.py` (flags translated fragments that would glue together wrong — missing spaces, mismatched quotes)

`make test` skips cases the current environment can't run (e.g. it won't do a real blackout while the menu bar app is live, since that would interrupt your session). Set `SMOKE_FULL=1` to force it.

**Build requirements:** macOS 13+ with Xcode Command Line Tools (`xcode-select --install`). The Swift toolchain they provide is the only dependency; there are no third-party packages. A universal binary (Apple Silicon + Intel) is built by default.

> **Note — `make all` rewrites `Sources/Info.plist` in place.** It stamps the version from the latest git tag into the `<!--VERSION-->` placeholder, so after a build `git status` will show `Sources/Info.plist` as modified. This is how the version number stays in sync with tags; commit it as part of a release (don't fight it).

**Promo assets (screenshots / demo GIF):** they are *not* committed — generate them locally with `./dev-tools/capture-promo.sh` (menu / settings / `settings-win` / gif). The script leaves a countdown so you can arrange the UI; `settings-win` captures the settings window by its window ID so there is no manual cropping. The raw full-screen frames contain your desktop and are git-ignored.

## Known limitations

- **External monitors may stay lit.** Blackout dims through the software brightness API, which most HDMI/DVI/DisplayPort panels don't expose. The built-in display goes fully dark; `lidkeep doctor` names any that don't. (Real display sleep would fix them, but it kills remote frames — deliberately avoided.)
- **The thermal guard only releases what it can restore.** It lets go of the blackout, anti-sleep, display-on and the lid daemon your power plan owns — all of which come back on their own once the machine cools. A daemon *you* started by hand with `lidkeep nosleep on --system` is left running on purpose: the guard has no way to know you wanted it back, so stopping it would trade a hot machine for a setting you can never recover.
- **It's not a lock screen.** The machine stays fully usable to anyone at the keyboard — they just can't see it. Lock with ⌃⌘Q.
