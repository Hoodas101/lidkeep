<img src="docs/icon.png" width="50" align="right" alt="LidKeep app icon">

# LidKeep

**Turn the display off. Don't let the Mac sleep.**

The screen goes pitch black; the machine keeps working. Remote desktop stays connected, downloads keep going, builds keep running. Press a hotkey (or run one command over SSH) and the picture comes straight back.

Unlike true display sleep, LidKeep only cuts the backlight — the display never sleeps, so screen sharing keeps showing the real picture instead of a black frame.

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

中文: [README.zh-CN.md](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

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

They are not mutually exclusive — the first two act on the system and on the display respectively, and the lid setting is independent of both. **Stay awake after the display sleeps** holds its own anti-sleep assertion from the moment you flip it on, so it works even if you never use *Turn Display Off* — just let the screen go dark on its own. If a plan cannot take effect right now (helper missing, battery below the floor, or the machine is too hot), the menu title says "not active" and the app retries automatically once that changes — your settings are never silently rewritten, not even by thermal protection.

## Three ways people actually use it

- **The Mac as a remote host** (UURemote / ToDesk / VNC / SSH) — `lidkeep off` blanks the screen, the machine stays awake, remote frames stay clean. Press the hotkey when you're back at the desk. Worried you'll forget? A 12-hour fallback timeout restores the display automatically.
- **Closed in a bag, still working** — open **When the lid closes** in the menu and pick **Keep awake**; the built-in panel turns itself off, downloads / builds / remote sessions keep going, and brightness comes back when you open the lid.
- **Stepping away from the desk** — hit the hotkey; the screen goes dark and your tasks keep running. ⚠️ Blanking is **not** locking — press ⌃⌘Q before you leave.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

It fetches the latest release, verifies `SHA256SUMS`, installs the app and the CLI, clears
the quarantine flag and launches. Drop the `| bash` to read it before running it.

Rather do it yourself? Grab `LidKeep-<version>.pkg` or the `.dmg` from
[Releases](../../releases/latest), or `brew install --cask hoodas101/tap/lidkeep`.

**One manual step, once:** releases are signed **ad-hoc, not notarized** — there is no
paid Apple Developer certificate behind this project — so Gatekeeper rejects a downloaded
copy until you clear the flag:

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

Then click ☀ in the menu bar → **Turn Display Off**. ⌃⌥⌘B brings the picture back.

## Commands you'll actually use

```bash
lidkeep off             # black out now (auto-restores after the fallback timeout)
lidkeep on              # restore — works over SSH too
lidkeep status          # what's active, plus power source and battery level
lidkeep doctor          # self-check: displays, processes, leftovers
lidkeep plan            # both power plans, and which one is active right now
lidkeep nosleep setup   # privileged helper + anti-sleep in one command
```

## Documentation

- **[docs/DETAILS.md](docs/DETAILS.md)** — full command list, anti-sleep and the
  privileged helper, how the brightness trick works, thermal protection, FAQ, development
- **[docs/CONFIG.md](docs/CONFIG.md)** — every `config.json` field
- **[docs/COOKBOOK.md](docs/COOKBOOK.md)** — ready-made recipes for common setups

## Requirements

macOS 13 Ventura or later (universal binary: Apple Silicon + Intel), and a built-in
display to black out — external monitors generally don't expose software brightness.

## Support this project

LidKeep is built and maintained by a single developer. Bug reports and pull requests are answered promptly — every report is read, and most fixes land within a few days. If this project saves you time, **⭐ [star the repo](../../stargazers)** — it's the easiest way to help and costs nothing. Questions and ideas are welcome in [Discussions](../../discussions).

If you'd like to go further, buying me a coffee keeps it going ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="WeChat Pay" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="Alipay" width="220">
</p>

**International options (no mainland bank card needed):** GitHub Sponsors, Ko-fi and PayPal are *being set up by the maintainer* — links will appear here once enabled. Until then, a ⭐ star or a detailed bug report helps this project more than you might think.

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=Hoodas101/lidkeep&type=Date)](https://star-history.com/#Hoodas101/lidkeep&Date)

## License

[MIT](LICENSE)
