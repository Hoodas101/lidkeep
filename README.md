<img src="docs/icon.png" width="100" align="right" alt="LidKeep app icon" style="margin-left:33px;margin-bottom:15px;margin-top:-72px;">

# LidKeep

**Turn the display off. Don't let the Mac sleep.**

The screen goes pitch black; the machine keeps working. Remote desktop stays connected, downloads keep going, builds keep running. Press a hotkey (or run one command over SSH) and the picture comes straight back.

Unlike true display sleep, LidKeep only cuts the backlight — the display never sleeps, so screen sharing keeps showing the real picture instead of a black frame.

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

中文: [README.zh-CN.md](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

## Contents

- [Sound familiar?](#sound-familiar)
- [How it compares](#how-it-compares)
- [Two menu items & power plans](#there-are-only-two-menu-items)
- [Three ways people actually use it](#three-ways-people-actually-use-it)
- [Install](#install)
- [Usage](#usage)
- [Anti-sleep (closed lid / battery / headless)](#anti-sleep-closed-lid--battery--headless)
- [How it works](#how-it-works)
- [Language](#language)
- [Details worth knowing](#details-worth-knowing)
- [Requirements](#requirements)
- [FAQ](#faq)
- [Development](#development)
- [Support](#support)

```bash
# Install in one line
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

```
$ lidkeep off      # screen goes black, system keeps running
$ lidkeep on       # display restored (also works over SSH)
```

> **Local-first and private:** LidKeep runs fully on your Mac — no account, no telemetry, no network calls except an optional 24-hour update check that only reads a public version number. MIT-licensed, zero third-party dependencies, fully open source, with a CI build on every push.

## Sound familiar?

macOS wires "display off" and "system asleep" together. You only want the screen off; the system puts the whole machine to sleep.

| Your situation | What usually happens |
|---|---|
| You want the screen dark to save power, but you're not at the machine | The moment it sleeps, remote desktop connects to a black frame |
| You close the lid and toss the Mac in a bag | The machine sleeps with it — downloads, builds and remote sessions all drop |
| You run closed-lid, or carry it closed | The moment sleep is prevented, the built-in panel stays lit — macOS never turns the backlight off just because you closed the lid |
| You brute-force it with `caffeinate` | The screen glows all night — power drain, burn-in risk, and everything on it visible to anyone nearby |
| You use macOS display sleep | The framebuffer is torn down, screen sharing captures nothing, remote access is effectively dead |

## How it compares

| | Screen off | Remote frames | Machine keeps working | Works closed-lid | Permissions |
|---|:--:|:--:|:--:|:--:|---|
| macOS display sleep | ✅ | ❌ lost | ❌ sleeps | — | none |
| `pmset displaysleepnow` | ✅ | ❌ lost | ❌ sleeps | — | none |
| Screensaver / lock screen | ❌ still lit | ✅ | ⚠️ sleeps eventually | — | none |
| `caffeinate` | ❌ stays lit | ✅ | ✅ | ❌ AC power only | none |
| Third-party keep-awake apps | ❌ stays lit | ✅ | ✅ | partial | some need grants |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **hotkey needs none** (lid mode needs a one-time helper) |

The difference comes down to one thing: **LidKeep only cuts the backlight; it never puts the display to sleep.** The display stays awake, the framebuffer keeps rendering, and a remote viewer always sees the real picture instead of a black screen.

## There are only two menu items

| Menu item | What it does | How to use it |
|---|---|---|
| **Turn Display Off** | The screen goes dark instantly — backlight cut, not merely dimmed — and the machine keeps running | Click it, or press ⌃⌥⌘B |
| **Status: … ▸** | Everything else | The title *is* the current status (e.g. `Status: Power · Keep awake`); open it to set each power source separately — the three switches can all be on at once |

**Power plan** follows the Windows "Power Options" model: plugged in and on battery are two different situations, so each keeps its own settings. Unplug the charger and the Mac moves to the battery plan within a few seconds — **Power / Battery** in the title tells you which one is active.

| Switch | What it does | Cost |
|---|---|---|
| **Stay awake after the display sleeps** | The Mac keeps running while the display is dark — whether you blanked it from LidKeep or simply let macOS blank it | easy on battery |
| **Keep the display on** | Display never sleeps on its own | uses more power |
| **When the lid closes** | `Sleep` (system default) or `Keep awake` (keeps running, built-in panel off) | "Keep awake" needs the privileged helper; plug in if you can |

They are not mutually exclusive — the first two act on the system and on the display respectively, and the lid setting is independent of both. **Stay awake after the display sleeps** holds its own anti-sleep assertion from the moment you flip it on, so it works even if you never use *Turn Display Off* — just let the screen go dark on its own. If a plan cannot take effect right now (helper missing, battery below the floor), the menu title says "not active" and the app retries automatically once that changes — your settings are never silently rewritten.

## Three ways people actually use it

- **The Mac as a remote host** (UURemote / ToDesk / VNC / SSH) — `lidkeep off` blanks the screen, the machine stays awake, remote frames stay clean. Press the hotkey when you're back at the desk. Worried you'll forget? A 12-hour fallback timeout restores the display automatically.
- **Closed in a bag, still working** — open **When the lid closes** in the menu and pick **Keep awake**; the built-in panel turns itself off, downloads / builds / remote sessions keep going, and brightness comes back when you open the lid.
- **Stepping away from the desk** — hit the hotkey; the screen goes dark and your tasks keep running. ⚠️ Blanking is **not** locking — press ⌃⌘Q before you leave.

## Install

**One line** (looks up the latest release → downloads and verifies `SHA256SUMS` → installs the app and CLI → clears quarantine → launches; falls back to a mirror if GitHub is slow):

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

Want to read it before running it? Drop the `| bash` and open the file.

**Or pick any of these:**

| Option | How | Notes |
|---|---|---|
| Homebrew | `brew install --cask hoodas101/tap/lidkeep` | still run the one-line quarantine fix below |
| Installer | download `LidKeep-<version>.pkg` from [Releases](../../releases/latest) and double-click | installs app + CLI in one step; if blocked, right-click → **Open** |
| DMG | download the `.dmg`, open it, drag the app into Applications | `Install Command-Line Tool.command` inside the image also installs the CLI |
| Source | `git clone … && cd lidkeep && ./install.sh` | needs Xcode Command Line Tools; `--cli-only` skips the app |

Then click ☀ in the menu bar → **Turn Display Off**. The screen goes black; press ⌃⌥⌘B to bring it back.

### Unsigned: clear the quarantine flag once

Releases are signed **ad-hoc, not notarized** (there is no paid Apple Developer certificate behind this project), so Gatekeeper treats a downloaded copy as untrusted. Measured on macOS 26:

| Path | What Gatekeeper does |
|---|---|
| Direct download (`.pkg` / `.dmg` / zip) | `spctl` assesses the installer **and** the app as `rejected` |
| `brew install --cask` | Homebrew applies the quarantine attribute itself — the app is **also rejected** |
| Opening a quarantined copy | macOS refuses, and **may move the app straight to the Trash** |

Homebrew cannot help here (`--no-quarantine` no longer exists in Homebrew 6), so every path needs **one manual step, once**:

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

(After a manual `.dmg`/`.pkg` download you can instead right-click it → **Open** and confirm once.)

**The real fix is notarization** — Developer ID signing plus a notarization ticket. Once that lands, every path above becomes a plain double-click, and it is the top priority for the next release. In the meantime each release publishes `SHA256SUMS` and GitHub build-provenance attestations, so you can verify that what you downloaded came from this repository:

```bash
shasum -a 256 -c SHA256SUMS                                  # bytes match what was published
gh attestation verify lidkeep-macos.zip -R Hoodas101/lidkeep   # built by this repo's release workflow
```

### Downloading from mainland China

`github.com` release assets are often unreachable from mainland China — measured at **0 bytes in 10 seconds**, while `api.github.com` and `raw.githubusercontent.com` stay fine. That is a CDN-level block, not a problem with this project.

Prefix a release URL with `https://gh-proxy.com/` to route the download through a mirror. This was verified byte-identical to the official artifact (matching SHA-256, full length) at roughly **173 KB/s**:

```bash
V=2.2.3
curl -L -O "https://gh-proxy.com/https://github.com/Hoodas101/lidkeep/releases/download/v$V/LidKeep-$V.dmg"
shasum -a 256 "LidKeep-$V.dmg"   # must match SHA256SUMS from the release
```

`gh-proxy.com` is a third-party accelerator, not something this project controls — it can change or disappear. Always check the hash against `SHA256SUMS` before installing, and prefer the official URL whenever you can reach it.

### Upgrading from an older release

The product has been called **LidKeep** since v2.0.0, when the CLI name, the app name and every bundle identifier changed. State left behind by v1.x — its config folder, login item, privileged helper and anti-sleep ledger — is **not** migrated or cleaned up automatically anymore: back up `~/Library/Application Support/` and remove the old app yourself before upgrading.

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

## Language

**Follows your system**: Chinese system language → Chinese UI; anything else (including English) → English UI. The menu bar app and the CLI always match — nothing to configure.

To switch it temporarily or permanently: `LIDKEEP_LANG=zh lidkeep doctor` (`zh` / `en`), or set `"lang": "zh"` in `~/Library/Application Support/LidKeep/config.json`. The config accepts `auto` (default) / `zh` / `en`, and the environment variable wins over it.

## Details worth knowing

- **No grants needed for the hotkey.** The global hotkey uses the Carbon `RegisterEventHotKey` API, dispatched by WindowServer itself — no Accessibility or Input Monitoring grants, and it keeps working after every rebuild (ad-hoc signed binaries lose TCC grants on each recompile, the most common trap for small tools like this). **One exception:** the lid-closed "Keep awake" mode needs the privileged helper below, which asks for your admin password **once** (see "Why does the system level need a privileged helper?" and [SECURITY.md](SECURITY.md)).
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
- `dev-tools/` — helpers plus `smoke.sh` and the `check-l10n.py` copy guard

`make test` skips cases the current environment can't run (e.g. it won't do a real blackout while the menu bar app is live, since that would interrupt your session). Set `SMOKE_FULL=1` to force it.

**Build requirements:** macOS 13+ with Xcode Command Line Tools (`xcode-select --install`). The Swift toolchain they provide is the only dependency; there are no third-party packages. A universal binary (Apple Silicon + Intel) is built by default.

> **Note — `make all` rewrites `Sources/Info.plist` in place.** It stamps the version from the latest git tag into the `<!--VERSION-->` placeholder, so after a build `git status` will show `Sources/Info.plist` as modified. This is how the version number stays in sync with tags; commit it as part of a release (don't fight it).

**Promo assets (screenshots / demo GIF):** they are *not* committed — generate them locally with `./dev-tools/capture-promo.sh` (menu / settings / `settings-win` / gif). The script leaves a countdown so you can arrange the UI; `settings-win` captures the settings window by its window ID so there is no manual cropping. The raw full-screen frames contain your desktop and are git-ignored.

## Known limitations

- **External monitors may stay lit.** Blackout dims through the software brightness API, which most HDMI/DVI/DisplayPort panels don't expose. The built-in display goes fully dark; `lidkeep doctor` names any that don't. (Real display sleep would fix them, but it kills remote frames — deliberately avoided.)
- **It's not a lock screen.** The machine stays fully usable to anyone at the keyboard — they just can't see it. Lock with ⌃⌘Q.

## Support this project

LidKeep is built and maintained by a single developer. Bug reports and pull requests are answered promptly — every report is read, and most fixes land within a few days. If this project saves you time, **⭐ [star the repo](../../stargazers)** — it's the easiest way to help and costs nothing. Questions and ideas are welcome in [Discussions](../../discussions).

If you'd like to go further, buying me a coffee keeps it going ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="WeChat Pay" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="Alipay" width="220">
</p>

**International options (no mainland bank card needed):** GitHub Sponsors, Ko-fi and PayPal are *being set up by the maintainer* — links will appear here once enabled. Until then, a ⭐ star or a detailed bug report helps this project more than you might think.

**Prefer card / PayPal now?** You can also sponsor via GitHub Sponsors once it's enabled at `github.com/Hoodas101/lidkeep` — that route works worldwide and needs no Chinese payment account.

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=Hoodas101/lidkeep&type=Date)](https://star-history.com/#Hoodas101/lidkeep&Date)

## License

[MIT](LICENSE)
