<img src="docs/icon.png" width="50" align="right" alt="LidKeep app icon">

# LidKeep

**Turn the display off. Don't let the Mac sleep.**

The screen goes black; the machine keeps working — remote desktop connected, downloads and builds still running. One hotkey, or one command over SSH, brings the picture back.

Unlike real display sleep, LidKeep only cuts the backlight, so a remote viewer always sees the real picture instead of a black frame.

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

中文: [README.zh-CN.md](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash

lidkeep off      # screen goes black, system keeps running
lidkeep on       # display restored (also works over SSH)
```

> **Local-first and private.** No account, no telemetry, no network calls — except an optional daily update check that reads one public version number. MIT-licensed, zero third-party dependencies, CI build on every push.

## Sound familiar?

macOS ties "display off" and "system asleep" together — you want one, you get both.

| You want to… | What macOS does instead |
|---|---|
| Blank the screen while you're away | Remote desktop connects to a black frame |
| Work closed-lid — bag, server, second desk | It sleeps with the lid; prevent that and the built-in panel stays lit all day |
| Brute-force it with `caffeinate` | The screen glows all night — power drain, burn-in risk, everything on it visible |

## How it compares

| | Screen off | Remote frames | Machine keeps working | Works closed-lid | Permissions |
|---|:--:|:--:|:--:|:--:|---|
| macOS display sleep | ✅ | ❌ lost | ❌ sleeps | — | none |
| `pmset displaysleepnow` | ✅ | ❌ lost | ❌ sleeps | — | none |
| Screensaver / lock screen | ❌ still lit | ✅ | ⚠️ sleeps eventually | — | none |
| `caffeinate` | ❌ stays lit | ✅ | ✅ | ❌ AC power only | none |
| Third-party keep-awake apps | ❌ stays lit | ✅ | ✅ | partial | some need grants |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **hotkey needs none** (lid mode needs a one-time helper) |

**One design decision separates it:** LidKeep cuts the backlight and never puts the display to sleep — the framebuffer keeps rendering, so remote viewers always see the real picture.

## Using it

Two menu items, and that's the whole surface:

| Menu item | What it does |
|---|---|
| **Turn Display Off** | Backlight cut — not dimmed — and the machine keeps running. Click it, or press ⌃⌥⌘B |
| **Status: … ▸** | Everything else. The title *is* the current status; open it to configure the power source in use |

**Power plans work like Windows "Power Options":** plugged in and on battery keep separate settings, swapped within seconds of unplugging. Each plan has three independent switches — *stay awake after the display sleeps*, *keep the display on*, *when the lid closes*. If one can't take effect (helper missing, battery low, machine hot) the title says so and the app retries by itself. Full detail in [docs/DETAILS.md](docs/DETAILS.md#usage).

- **Remote host** (ToDesk / VNC / SSH) — `lidkeep off` and let it run; a 12-hour fallback restores the display if you forget.
- **Closed in a bag** — set **When the lid closes ▸ Keep awake**; the panel goes dark, downloads and builds continue.
- **Stepping away** — hit the hotkey. ⚠️ Blanking is **not** locking: press ⌃⌘Q first.

```bash
lidkeep off / on / status      # black out · restore · inspect (all work over SSH)
lidkeep doctor / plan          # self-check · which power plan is active
lidkeep nosleep setup          # privileged helper + anti-sleep in one command
```

## Install

The one-liner above fetches the latest release, verifies `SHA256SUMS`, installs the app and CLI, clears the quarantine flag and launches — drop the `| bash` to read it first. Or take `LidKeep-<version>.pkg` / `.dmg` from [Releases](../../releases/latest), or `brew install --cask hoodas101/tap/lidkeep`.

**One manual step, once:** releases are signed **ad-hoc, not notarized** — there is no paid Apple Developer certificate behind this project — so Gatekeeper rejects a downloaded copy until you clear the flag:

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

## Requirements

macOS 13 Ventura or later (universal binary: Apple Silicon + Intel), and a built-in display to black out — external monitors generally don't expose software brightness.

## Docs

**[DETAILS.md](docs/DETAILS.md)** — every command, anti-sleep and the privileged helper, how it works, thermal protection, FAQ · **[CONFIG.md](docs/CONFIG.md)** — every config field · **[COOKBOOK.md](docs/COOKBOOK.md)** — ready-made recipes

## Support

LidKeep is built and maintained by one developer. Every issue is read; most fixes land within a few days.

⭐ **[Star the repo](../../stargazers)** · 💬 **[Discussions](../../discussions)** · ☕ **[GitHub Sponsors](https://github.com/sponsors/Hoodas101)**

<p align="center">
  <img src="docs/donate-wechat.png" alt="WeChat Pay" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="Alipay" width="220">
</p>

## License

[MIT](LICENSE)
