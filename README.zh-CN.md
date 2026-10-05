<img src="docs/icon.png" width="50" align="right" alt="LidKeep 图标">

# LidKeep

**关掉屏幕，但别让 Mac 睡。**

屏幕一黑，机器照跑 —— 远程桌面还在线，下载和构建继续。按一下热键（或在 SSH 里敲一条命令），画面立刻回来。

和真正的显示器睡眠不同，LidKeep 只关背光，显示器始终不睡眠，所以远程端看到的始终是真实画面，而不是一片黑。

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

English: [README.md](README.md) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [安全](SECURITY.md)

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

```
$ lidkeep off      # 屏幕熄灭，系统继续跑
$ lidkeep on       # 恢复显示（SSH 里同样有效）
```

> **本地优先、隐私优先。** 无账号、无遥测、无网络请求 —— 除了一次可选的每日更新检查，只读取一个公开版本号。MIT 许可、零第三方依赖，每次推送都有 CI 构建。

## 你遇到过吗

macOS 把「屏幕灭」和「机器睡」绑在了一起。你只想关屏幕，它把整台机器也睡了。

| 你只是想… | 结果 |
|---|---|
| 人走开，熄屏省电 | 一睡眠，远程桌面连上一片黑 |
| 合盖塞进包里带走 | 机器跟着睡：下载断、构建断、远控掉线 |
| 合盖继续跑，不让它睡 | 内屏一直亮着 —— macOS 不因合盖关背光，白白耗电 |
| 用 `caffeinate` 硬扛 | 屏幕整夜亮：费电、烧屏、内容还被旁边的人看见 |
| 用系统「显示器睡眠」 | 帧缓冲被拆掉，屏幕共享抓不到画面，远程等于断线 |

## 和别的方案比

| | 屏幕灭 | 远程画面 | 机器继续 | 合盖可用 | 需要授权 |
|---|:--:|:--:|:--:|:--:|---|
| 系统显示器睡眠 | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| `pmset displaysleepnow` | ✅ | ❌ 断 | ❌ 睡 | — | 无 |
| 屏保 / 锁屏 | ❌ 亮 | ✅ | ⚠️ 会睡 | — | 无 |
| `caffeinate` | ❌ 亮 | ✅ | ✅ | ❌ 仅插电 | 无 |
| 第三方防睡 App | ❌ 亮 | ✅ | ✅ | 部分 | 部分要授权 |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **热键无需授权**（合盖模式装一次助手） |

只差一个设计决定：**LidKeep 只关背光，从不让显示器睡眠。** 帧缓冲一直在渲染，所以远程端看到的始终是真实画面。

## 怎么用

菜单栏只有两个入口：

| 菜单项 | 作用 |
|---|---|
| **关闭显示器** | 背光切断（不是调暗），机器照跑。点一下，或按 ⌃⌥⌘B |
| **状态：… ▸** | 其余全在这里。标题即当前状态（例：`状态：电源 · 保持唤醒`），打开它配置当前生效的电源方案 |

**电源方案沿用 Windows「电源选项」的思路：** 插电和用电池各存一套，拔掉充电器几秒内自动切换。每套方案三个开关互不冲突 —— *息屏后保持唤醒*、*保持屏幕常亮*、*合盖时怎么办*。方案若暂时起不来（缺助手、电量低于下限、机身过热），标题会写明「未生效」，条件满足后自动补起，你的设置不会被偷偷改动 —— 过热保护也一样。完整说明见 [docs/DETAILS.zh-CN.md](docs/DETAILS.zh-CN.md#使用)。

三种最常见的情形：

- **把 Mac 当远程主机**（ToDesk / VNC / SSH）—— `lidkeep off` 后放着跑。忘了恢复也不要紧，默认 12 小时的兜底超时会自动把屏幕叫回来。
- **合盖收纳，任务不断** —— 菜单里把**合盖时**设为**保持唤醒**，内屏熄灭，下载和构建照常，开盖即恢复亮度。
- **离座不想屏幕被看见** —— 按热键熄屏。⚠️ 关屏**不等于**锁屏，走前请按 ⌃⌘Q。

```bash
lidkeep off             # 立刻熄屏（到兜底时间自动恢复）
lidkeep on              # 恢复显示（SSH 里同样有效）
lidkeep status          # 当前状态，含电源来源与电量
lidkeep doctor          # 自检：显示器、进程、残留
lidkeep plan            # 两套电源方案，以及此刻生效的是哪套
lidkeep nosleep setup   # 一条命令装好提权助手并开启防睡眠
```

## 安装

上面那行命令会自动查最新版、校验 `SHA256SUMS`、装好 App 与 CLI、清隔离标记并启动。去掉 `| bash` 可以先读一遍再决定。

想自己动手？从 [Releases](../../releases/latest) 下 `LidKeep-<版本>.pkg` 或 `.dmg`，或：

```bash
brew install --cask hoodas101/tap/lidkeep
```

**需要手动做一次：** Release 是 **ad-hoc 自签名、未公证**（本项目没有付费 Apple 开发者证书），Gatekeeper 会拒绝下载的副本，清一次标记即可：

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

然后点菜单栏 ☀ → **关闭显示器**，⌃⌥⌘B 把画面叫回来。

## 文档

- **[docs/DETAILS.zh-CN.md](docs/DETAILS.zh-CN.md)** —— 完整命令、防睡眠与提权助手、原理实测、过热保护、常见问题、开发
- **[docs/CONFIG.md](docs/CONFIG.md)** —— `config.json` 的全部字段
- **[docs/COOKBOOK.md](docs/COOKBOOK.md)** —— 常见场景的现成配方（快捷指令、SSH、合盖服务器、Home Assistant、LaunchAgent）

## 环境要求

macOS 13 Ventura 及以上（通用二进制：Apple Silicon + Intel），并且要有内建显示器可熄屏 —— 外接显示器通常不暴露软件亮度接口。

## 打赏支持

LidKeep 由**一个人**开发和维护。每个 Issue 都会被读，绝大多数修复几天内落地。

- **⭐ [点个 Star](../../stargazers)** —— 最省事也最实在的帮助，不花钱
- **[Discussions](../../discussions)** 聊问题和想法
- **[GitHub Sponsors](https://github.com/sponsors/Hoodas101)**，或请作者喝杯咖啡 ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="微信打赏" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="支付宝打赏" width="220">
</p>

## Star 历史

[![Star History Chart](https://api.star-history.com/svg?repos=Hoodas101/lidkeep&type=Date)](https://star-history.com/#Hoodas101/lidkeep&Date)

## 许可

[MIT](LICENSE)
