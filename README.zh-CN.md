<img src="docs/icon.png" width="50" align="right" alt="LidKeep app icon">

# LidKeep

**关掉屏幕，但别让 Mac 睡。**

屏幕一黑，机器照常跑：远程桌面还在线、下载还在、构建还在。按一下热键（或在 SSH 里敲一条命令），画面立刻回来。

和真正的显示器睡眠不同 —— LidKeep 只是把背光关掉，显示器始终不睡眠，所以屏幕共享看到的始终是真实画面，而不是一片黑。

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

English: [README.md](README.md) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [安全](SECURITY.md)

```bash
# 一行安装
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

```
$ lidkeep off      # 屏幕熄灭，系统继续跑
$ lidkeep on       # 恢复显示（SSH 里执行同样有效）
```

> **本地优先、隐私优先：** LidKeep 完全在你的 Mac 上运行 —— 无账号、无遥测，除了一次可选的 24 小时更新检查（只读取一个公开版本号）之外不发起任何网络请求。MIT 许可、零第三方依赖、完全开源，每次推送都有 CI 构建。

## 你遇到过吗

macOS 把「屏幕灭」和「机器睡」绑在了一起。你只想关屏幕，它顺手把机器也睡了。

| 你只是想… | 通常的结局 |
|---|---|
| 熄屏省电 / 防偷窥，人走开 | 一睡眠，远程桌面连上一片黑 |
| 合盖塞进包里带走 | 机器跟着睡：下载断、构建断、远控掉线 |
| 合盖接显示器 / 合盖收纳 | 不让睡的话内屏一直亮着 —— macOS 不因合盖关背光，白白耗电 |
| 用 `caffeinate` 硬扛 | 屏幕整夜亮：费电、烧屏、内容还被看见 |
| 用系统「显示器睡眠」 | 帧缓冲被拆掉，屏幕共享抓不到画面，远程等于断线 |

## 和别的方案比

| | 屏幕灭 | 远程画面 | 机器继续 | 合盖可用 | 需要授权 |
|---|:--:|:--:|:--:|:--:|---|
| 系统显示器睡眠 | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| `pmset displaysleepnow` | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| 屏保 / 锁屏 | ❌ 亮 | ✅ | ⚠️ 会睡 | — | 无 |
| `caffeinate` | ❌ 亮 | ✅ | ✅ | ❌ 仅插电 | 无 |
| 第三方防睡 App | ❌ 亮 | ✅ | ✅ | 部分 | 部分要授权 |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **热键无需授权**（合盖装一次助手） |

差别只有一处：**LidKeep 只是把背光关掉，并不让显示器进入睡眠**。显示器始终不睡眠，帧缓冲一直在渲染，所以远程端看到的始终是真实画面，而不是一片黑。

## 菜单里就两件事

| 菜单项 | 干啥 | 怎么用 |
|---|---|---|
| **关闭显示器** | 屏幕立刻黑 —— 背光切断，不是调暗 —— 机器照跑 | 点一下，或按 ⌃⌥⌘B |
| **状态：… ▸** | 其余所有场景 | 标题即当前状态（例：`状态：电源保持唤醒`）；按电源来源各设一套，三个开关可同时开 |

**电源方案**和 Windows 的「电源选项」是同一套思路：插电和用电池是两套设置，拔充电器几秒内自动切换 —— 标题里的**电源 / 电池**就是此刻生效的那一套。

| 开关 | 会发生什么 | 代价 |
|---|---|---|
| **息屏后保持唤醒** | 屏幕黑着，机器照跑（你主动关屏、或系统自己熄屏都算） | 较省电 |
| **保持屏幕常亮** | 屏幕不会自动熄 | 较耗电 |
| **合盖时** | `睡眠`（默认）或 `保持唤醒`（持续运行，内屏熄灭） | 保持唤醒需装提权助手，建议接电源 |

三项互不冲突：前两个分别管系统睡眠和显示器睡眠，合盖行为独立。**息屏后保持唤醒**一打开，就自动维持一个防睡断言，所以哪怕你不点「关闭显示器」、让屏幕自己熄掉，也同样生效。方案若暂时起不来（缺助手、电量低于下限、机身过热），标题会写明「未生效」，条件满足后自动补起，你的设置不会被偷偷改动 —— 过热保护也一样。

## 三种常见用法

- **把 Mac 当远程主机用**（UURemote / ToDesk / VNC / SSH）—— `lidkeep off` 熄屏，机器不睡，远程画面正常；回来按热键恢复。怕忘？默认 12 小时后会自动把屏幕恢复回来。
- **合盖收纳，任务不断** —— 菜单里**合盖时**选**保持唤醒**，合盖后内屏自动熄灭，下载 / 构建 / 远程照常，开盖自动恢复亮度。
- **离座不想屏幕被看见** —— 按热键熄屏，任务继续。⚠️ 关屏**不等于**锁屏，走前请手动 ⌃⌘Q。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

它会自动查最新版、校验 `SHA256SUMS`、装好 App 与 CLI、清隔离标记并启动。去掉 `| bash` 可以先读一遍再决定。

想自己动手？从 [Releases](../../releases/latest) 下 `LidKeep-<版本>.pkg` 或 `.dmg`，或 `brew install --cask hoodas101/tap/lidkeep`。

**需要手动做一次：** Release 是 **ad-hoc 自签名、未公证**（本项目没有付费 Apple 开发者证书），Gatekeeper 会拒绝下载的副本，清一次标记即可：

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

然后点菜单栏 ☀ → **关闭显示器**，⌃⌥⌘B 把画面叫回来。

## 常用命令

```bash
lidkeep off             # 立刻熄屏（到兜底时间自动恢复）
lidkeep on              # 恢复显示（SSH 里同样有效）
lidkeep status          # 当前状态，含电源来源与电量
lidkeep doctor          # 自检：显示器、进程、残留
lidkeep plan            # 两套电源方案，以及此刻生效的是哪套
lidkeep nosleep setup   # 一条命令装好提权助手并开启防睡眠
```

## 文档

- **[docs/DETAILS.zh-CN.md](docs/DETAILS.zh-CN.md)** —— 完整命令、防睡眠与提权助手、原理实测、过热保护、常见问题、开发
- **[docs/CONFIG.md](docs/CONFIG.md)** —— `config.json` 的全部字段
- **[docs/COOKBOOK.md](docs/COOKBOOK.md)** —— 常见场景的现成配方

## 环境要求

macOS 13 Ventura 及以上（通用二进制：Apple Silicon + Intel），并且要有内建显示器可熄屏 —— 外接显示器通常不暴露软件亮度接口。

## 打赏支持

LidKeep 是**一个人**在做和维护。每个 Issue 都会被读、绝大多数修复几天内落地；欢迎提 PR。如果这个项目帮到你，**⭐ [点个 Star](../../stargazers)** 是最省事也最实在的帮助；问题与想法欢迎来 [Discussions](../../discussions) 聊。

如果想再进一步，欢迎请作者喝杯咖啡 —— 每一杯都是持续更新的动力 ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="微信打赏" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="支付宝打赏" width="220">
</p>

**国际支付（无需大陆银行卡）：** GitHub Sponsors、Ko-fi、PayPal *正在由作者接入* —— 开通后链接会补到这里。在那之前，点个 ⭐ Star 或提个详细 Issue，帮助比想象中大。

## Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=Hoodas101/lidkeep&type=Date)](https://star-history.com/#Hoodas101/lidkeep&Date)

## 许可
