<img src="docs/icon.png" width="50" align="right" alt="LidKeep 图标">

# LidKeep

**关掉屏幕，机器照常跑。**

屏幕熄了，系统还在工作。远程桌面连着，下载和构建都没断。想恢复画面，按一下热键，或者在 SSH 里敲一条命令。

这和系统的显示器睡眠不是一回事。LidKeep 只关背光，显示器本身没有睡，所以远程端看到的仍然是真实画面。

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

[English README](README.md) · [更新日志](CHANGELOG.md)（英文） · [贡献指南](CONTRIBUTING.md)（英文） · [安全策略](SECURITY.md)（英文）

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash

lidkeep off      # 屏幕熄灭，系统继续跑
lidkeep on       # 恢复显示（SSH 里同样有效）
```

> **本地跑，不联网。** 没有账号，没有遥测，除了可选的每日更新检查去读一个公开版本号，它不发出任何请求。MIT 许可，零第三方依赖，每次推送都跑 CI 构建。

## 你遇到过吗

macOS 把两件事捆在了一起：屏幕灭掉，机器也跟着睡。可多数时候你只想要其中一个。

| 你只是想… | 结果 |
|---|---|
| 人走开，熄屏省电 | 远程桌面连上一片黑 |
| 合盖继续跑（塞包里 / 当服务器 / 接副屏） | 机器还是一起睡了；改成不让它睡，内屏又整天亮着 |
| 用 `caffeinate` 硬扛 | 屏幕整夜亮着，费电，有烧屏风险，屏幕上的内容还被旁边的人看见 |

## 和别的方案比

| | 屏幕灭 | 远程画面 | 机器继续 | 合盖可用 | 需要授权 |
|---|:--:|:--:|:--:|:--:|---|
| 系统显示器睡眠 | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| `pmset displaysleepnow` | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| 屏保 / 锁屏 | ❌ 亮 | ✅ | ⚠️ 会睡 | — | 无 |
| `caffeinate` | ❌ 亮 | ✅ | ✅ | ❌ 仅插电 | 无 |
| 第三方防睡 App | ❌ 亮 | ✅ | ✅ | 部分 | 部分要授权 |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **热键无需授权**（合盖模式装一次助手） |

**差别只在一个设计决定上。** LidKeep 关的是背光，从不把显示器送进睡眠，帧缓冲一直在渲染。

## 怎么用

日常只用其中两个，其余都在**设置…**里和菜单底部。

| 菜单项 | 作用 |
|---|---|
| **关闭显示器** | 背光直接切断，屏幕全黑，机器继续跑。点一下，或按 ⌃⌥⌘B |
| **状态：… ▸** | 其余全在这里。标题就是当前状态，打开它可以配置当前生效的电源方案 |

**电源方案沿用 Windows「电源选项」的思路。** 插电和用电池各存一套，拔掉充电器几秒内自动切换。每套方案有三个互不冲突的开关：*息屏后保持唤醒*、*保持屏幕常亮*、*合盖时怎么办*。方案暂时起不来时（缺助手、电量低于下限、机身过热），标题会写明「未生效」，条件满足后自动补起。完整说明见 [docs/DETAILS.zh-CN.md](docs/DETAILS.zh-CN.md#使用)。

- **当远程主机用**（ToDesk / VNC / SSH）。`lidkeep off` 之后放着跑，忘了恢复也不要紧，默认 12 小时的兜底会把屏幕叫回来。
- **合盖收纳**。菜单里把**合盖时**设为**保持唤醒**，内屏熄灭，下载和构建照常。
- **离座时不想被人看见屏幕**。按热键熄屏即可。⚠️ 关屏不等于锁屏，走之前先按 ⌃⌘Q。

```bash
lidkeep off / on / status      # 熄屏 · 恢复 · 查看状态（SSH 里同样有效）
lidkeep doctor / plan          # 自检 · 此刻生效的是哪套电源方案
lidkeep nosleep setup          # 一条命令装好提权助手并开启防睡眠
```

## 安装

上面那行命令会查最新版、校验 `SHA256SUMS`、装好 App 和 CLI、清掉隔离标记并启动。去掉 `| bash` 可以先读一遍再决定。也可以从 [Releases](../../releases/latest) 下 `LidKeep-<版本>.pkg` 或 `.dmg`，或者 `brew install --cask hoodas101/tap/lidkeep`。

**需要手动做一次。** Release 是 ad-hoc 自签名、没有公证（这个项目背后没有付费的 Apple 开发者证书），Gatekeeper 会拒绝下载来的副本，清一次标记就行：

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

## 卸载

先退出 LidKeep，然后删掉 App、CLI 和登录项：

```bash
rm -rf /Applications/LidKeep.app
rm -f /opt/homebrew/bin/lidkeep /usr/local/bin/lidkeep ~/.local/bin/lidkeep
rm -f ~/Library/LaunchAgents/com.lidkeep.*.plist
rm -rf ~/Library/Application\ Support/LidKeep   # 可选：连同热键与电源方案一起清掉
```

有克隆的话，`./uninstall.sh` 做掉前三步。菜单里的**卸载提权助手**只移除提权助手，不是卸载 App。

## 环境要求

macOS 13 Ventura 及以上（通用二进制：Apple Silicon + Intel），并且要有内建显示器可以熄屏，外接显示器一般不提供软件调亮度的接口。

## 文档

**[DETAILS.zh-CN.md](docs/DETAILS.zh-CN.md)** 有完整命令、防睡眠与提权助手、运行原理、过热保护和常见问题。**[CONFIG.md](docs/CONFIG.md)** 列了 `config.json` 的全部字段；**[COOKBOOK.md](docs/COOKBOOK.md)** 是常见场景的现成配方。

## 打赏支持

LidKeep 只有我一个人在做。每个 Issue 我都会看，大部分修复几天内就能发出来。

[点个 Star](../../stargazers) · [Discussions](../../discussions) · [GitHub Sponsors](https://github.com/sponsors/Hoodas101)

<p align="center">
  <img src="docs/donate-wechat.png" alt="微信打赏" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="支付宝打赏" width="220">
</p>

## 许可

[MIT](LICENSE)
