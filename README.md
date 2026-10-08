<img src="docs/icon.png" width="50" align="right" alt="LidKeep app icon">

# LidKeep

**Turn the display off. Keep the machine running.**

The screen goes dark and the system keeps working. Remote desktop stays connected; downloads and builds keep going. To get the picture back, hit the hotkey or run one command over SSH.

That is not the same thing as display sleep. LidKeep cuts the backlight only; the display itself never sleeps, so a remote viewer still sees the real picture.

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

[中文 README](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash

lidkeep off      # screen goes black, system keeps running
lidkeep on       # display restored (also works over SSH)
```

> **Local and offline.** No account, no telemetry, and nothing leaves your machine except an optional daily update check that reads one public version number. MIT licensed, no third-party dependencies, CI builds on every push.

## Sound familiar?

macOS ties two things together: turning the display off, and putting the system to sleep. Most of the time you only want one of them.

| You want to… | What macOS does instead |
|---|---|
| Blank the screen while you're away | Remote desktop connects to a black frame |
| Work closed-lid (bag, server, second desk) | It sleeps with the lid; block that and the built-in panel stays lit all day |
| Brute-force it with `caffeinate` | The screen glows all night: power drain, burn-in risk, and whatever is on it stays visible |

## How it compares

| | Screen off | Remote frames | Machine keeps working | Works closed-lid | Permissions |
|---|:--:|:--:|:--:|:--:|---|
| macOS display sleep | ✅ | ❌ lost | ❌ sleeps | — | none |
| `pmset displaysleepnow` | ✅ | ❌ lost | ❌ sleeps | — | none |
| Screensaver / lock screen | ❌ still lit | ✅ | ⚠️ sleeps eventually | — | none |
| `caffeinate` | ❌ stays lit | ✅ | ✅ | ❌ AC power only | none |
| Third-party keep-awake apps | ❌ stays lit | ✅ | ✅ | partial | some need grants |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **hotkey needs none** (lid mode needs a one-time helper) |

**The difference comes down to one design decision.** LidKeep cuts the backlight and never puts the display to sleep, so the framebuffer keeps rendering.

## Using it

Day to day you only touch two of them; the rest live in **Settings…** and the bottom of the menu.

| Menu item | What it does |
|---|---|
| **Turn Display Off** | Cuts the backlight outright, so the screen goes fully black, and the machine keeps running. Click it, or press ⌃⌥⌘B |
| **Status: … ▸** | Everything else. The title *is* the current status; open it to configure the power source in use |

**Power plans work like Windows "Power Options."** Plugged-in and on-battery settings are stored separately, and they swap within seconds of unplugging. Each plan has three switches that don't conflict: *stay awake after the display sleeps*, *keep the display on*, *when the lid closes*. If a switch can't take effect (helper missing, battery low, machine hot) its own row is marked **not active** and says why, the parent row carries a `⚠`, and the app starts it as soon as conditions allow. Full detail in [docs/DETAILS.md](docs/DETAILS.md#usage).

- **Remote host** (ToDesk / VNC / SSH). Run `lidkeep off` and leave it. If you forget to restore, the 12-hour fallback brings the display back.
- **Closed in a bag.** Set **When the lid closes ▸ Keep awake**. The panel goes dark; downloads and builds continue.
- **Stepping away.** Hit the hotkey. ⚠️ Blanking is not locking; press ⌃⌘Q first.

```bash
lidkeep off / on / status      # black out · restore · inspect (all work over SSH)
lidkeep doctor / plan          # self-check · which power plan is active
lidkeep nosleep setup          # privileged helper + anti-sleep in one command
```

## Install

The one-liner above fetches the latest release, verifies `SHA256SUMS`, installs the app and CLI, clears the quarantine flag, and launches it. Drop the `| bash` to read it first. You can also grab `LidKeep-<version>.pkg` or `.dmg` from [Releases](../../releases/latest), or run `brew install --cask hoodas101/tap/lidkeep`.

**One manual step.** Releases are signed ad-hoc, not notarized, because there is no paid Apple Developer certificate behind this project. Gatekeeper will reject a downloaded copy until you clear the flag:

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

## Uninstall

Quit LidKeep, then remove the app, the CLI and the login item:

```bash
rm -rf /Applications/LidKeep.app
rm -f /opt/homebrew/bin/lidkeep /usr/local/bin/lidkeep ~/.local/bin/lidkeep
rm -f ~/Library/LaunchAgents/com.lidkeep.*.plist
rm -rf ~/Library/Application\ Support/LidKeep   # optional: also drops your hotkey and power plans
```

From a clone, `./uninstall.sh` covers the first three. The menu's **Uninstall Privileged Helper** removes the helper only, not the app.

## Requirements

macOS 13 Ventura or later (universal binary: Apple Silicon + Intel), plus a built-in display to black out. External monitors generally don't expose software brightness.

## Docs

**[DETAILS.md](docs/DETAILS.md)** has every command, the anti-sleep and privileged helper, how it works, thermal protection and the FAQ. Two companion docs are **Chinese only** for now: **[CONFIG.md](docs/CONFIG.md)** documents every config field, and **[COOKBOOK.md](docs/COOKBOOK.md)** has ready-made recipes; the [中文 README](README.zh-CN.md) links to the same pair.

## Support

LidKeep is built and maintained by one person. Every issue gets read, and most fixes ship within a few days.

[Star the repo](../../stargazers) · [Discussions](../../discussions) · [GitHub Sponsors](https://github.com/sponsors/Hoodas101)

<p align="center">
  <img src="docs/donate-wechat.png" alt="WeChat Pay" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="Alipay" width="220">
</p>

## License

[MIT](LICENSE)
