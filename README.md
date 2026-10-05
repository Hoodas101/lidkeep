<img src="docs/icon.png" width="50" align="right" alt="LidKeep app icon">

# LidKeep

**Turn the display off. Don't let the Mac sleep.**

The screen goes black; the machine keeps working — remote desktop connected, downloads and builds still running. One hotkey, or one command over SSH, brings the picture back.

Unlike real display sleep, LidKeep only cuts the backlight. The display never sleeps, so a remote viewer always sees the real picture instead of a black frame.

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

中文: [README.zh-CN.md](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

```
$ lidkeep off      # screen goes black, system keeps running
$ lidkeep on       # display restored (also works over SSH)
```

> **Local-first and private.** No account, no telemetry, no network calls — except an optional daily update check that reads one public version number. MIT-licensed, zero third-party dependencies, CI build on every push.

## Sound familiar?

macOS ties "display off" and "system asleep" together. You only want the screen off; the whole machine goes to sleep.

| You want to… | What macOS does instead |
|---|---|
| Blank the screen while you're away | The moment it sleeps, remote desktop connects to a black frame |
| Close the lid and carry the Mac in a bag | It sleeps too — downloads, builds and remote sessions all drop |
| Run closed-lid without sleeping | The built-in panel stays lit; macOS never cuts the backlight just because the lid is shut |
| Brute-force it with `caffeinate` | The screen glows all night — power drain, burn-in risk, and everything on it visible to anyone nearby |
| Use macOS display sleep | The framebuffer is torn down, screen sharing captures nothing, remote access is dead |

## How it compares

| | Screen off | Remote frames | Machine keeps working | Works closed-lid | Permissions |
|---|:--:|:--:|:--:|:--:|---|
| macOS display sleep | ✅ | ❌ lost | ❌ sleeps | — | none |
| `pmset displaysleepnow` | ✅ | ❌ lost | ❌ sleeps | — | none |
| Screensaver / lock screen | ❌ still lit | ✅ | ⚠️ sleeps eventually | — | none |
| `caffeinate` | ❌ stays lit | ✅ | ✅ | ❌ AC power only | none |
| Third-party keep-awake apps | ❌ stays lit | ✅ | ✅ | partial | some need grants |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **hotkey needs none** (lid mode needs a one-time helper) |

It comes down to one design decision: **LidKeep cuts the backlight and never puts the display to sleep.** The framebuffer keeps rendering, so a remote viewer always sees the real picture.

## Using it

Two menu items, and that's the whole surface:

| Menu item | What it does |
|---|---|
| **Turn Display Off** | Backlight cut — not dimmed — and the machine keeps running. Click it, or press ⌃⌥⌘B |
| **Status: … ▸** | Everything else. The title *is* the current status (e.g. `Status: Power · Keep awake`); open it to configure the power source in use |

**Power plans follow the Windows "Power Options" model:** plugged in and on battery keep separate settings, swapped within seconds of unplugging. Each plan has three independent switches — *stay awake after the display sleeps*, *keep the display on*, *when the lid closes* — and they can all be on at once. If a plan can't take effect right now (helper missing, battery below the floor, machine too hot) the title says "not active" and the app retries by itself; your settings are never silently rewritten, not even by thermal protection. Full detail in [docs/DETAILS.md](docs/DETAILS.md#usage).

Three setups cover most people:

- **Mac as a remote host** (ToDesk / VNC / SSH) — `lidkeep off` and let it run. Forget to restore? A 12-hour fallback timeout brings the display back automatically.
- **Closed in a bag, still working** — set **When the lid closes ▸ Keep awake**. The panel goes dark, downloads and builds continue, brightness returns when you open it.
- **Stepping away from the desk** — hit the hotkey. ⚠️ Blanking is **not** locking: press ⌃⌘Q before you leave.

```bash
lidkeep off             # black out now (auto-restores after the fallback timeout)
lidkeep on              # restore — works over SSH too
lidkeep status          # what's active, plus power source and battery level
lidkeep doctor          # self-check: displays, processes, leftovers
lidkeep plan            # both power plans, and which one is active right now
lidkeep nosleep setup   # privileged helper + anti-sleep in one command
```

## Install

The one-liner above fetches the latest release, verifies `SHA256SUMS`, installs the app and the CLI, clears the quarantine flag and launches. Drop the `| bash` to read it before running it.

Rather do it yourself? Grab `LidKeep-<version>.pkg` or the `.dmg` from [Releases](../../releases/latest), or:

```bash
brew install --cask hoodas101/tap/lidkeep
```

**One manual step, once:** releases are signed **ad-hoc, not notarized** — there is no paid Apple Developer certificate behind this project — so Gatekeeper rejects a downloaded copy until you clear the flag:

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

Then click ☀ in the menu bar → **Turn Display Off**. ⌃⌥⌘B brings the picture back.

## Documentation

- **[docs/DETAILS.md](docs/DETAILS.md)** — full command list, anti-sleep and the privileged helper, how the brightness trick works, thermal protection, FAQ, development
- **[docs/CONFIG.md](docs/CONFIG.md)** — every `config.json` field
- **[docs/COOKBOOK.md](docs/COOKBOOK.md)** — ready-made recipes (Shortcuts, SSH, closed-lid server, Home Assistant, LaunchAgent)

## Requirements

macOS 13 Ventura or later (universal binary: Apple Silicon + Intel), and a built-in display to black out — external monitors generally don't expose software brightness.

## Support this project

LidKeep is built and maintained by a single developer. Every issue is read, and most fixes land within a few days.

- **⭐ [Star the repo](../../stargazers)** — the easiest way to help, and it costs nothing
- **[Discussions](../../discussions)** for questions and ideas
- **[GitHub Sponsors](https://github.com/sponsors/Hoodas101)** — or buy me a coffee ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="WeChat Pay" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="Alipay" width="220">
</p>

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=Hoodas101/lidkeep&type=Date)](https://star-history.com/#Hoodas101/lidkeep&Date)

## License

[MIT](LICENSE)
