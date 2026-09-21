<img src="docs/icon.png" width="112" align="right" alt="LidKeep app icon">

# LidKeep

**关掉屏幕，但别让 Mac 睡。**

屏幕一黑，机器照常跑：远程桌面还在线、下载还在、构建还在。按一下热键（或在 SSH 里敲一条命令），画面立刻回来。

[![Release](https://img.shields.io/github/v/release/Hoodas101/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/Hoodas101/lidkeep/build.yml?label=build)](../../actions/workflows/build.yml)

English: [README.md](README.md) · [更新日志](CHANGELOG.md) · [贡献指南](CONTRIBUTING.md) · [安全](SECURITY.md)

```
$ lidkeep off      # 屏幕熄灭，系统继续跑
$ lidkeep on       # 恢复显示（SSH 里执行同样有效）
```

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

三项互不冲突：前两个分别管系统睡眠和显示器睡眠，合盖行为独立。**息屏后保持唤醒**一打开，就自动维持一个防睡断言，所以哪怕你不点「关闭显示器」、让屏幕自己熄掉，也同样生效。方案若暂时起不来（缺助手、电量低于下限），标题会写明「未生效」，条件满足后自动补起，你的设置不会被偷偷改动。

## 三种常见用法

- **把 Mac 当远程主机用**（UURemote / ToDesk / VNC / SSH）—— `lidkeep off` 熄屏，机器不睡，远程画面正常；回来按热键恢复。怕忘？默认 12 小时后会自动把屏幕恢复回来。
- **合盖收纳，任务不断** —— 菜单里**合盖时**选**保持唤醒**，合盖后内屏自动熄灭，下载 / 构建 / 远程照常，开盖自动恢复亮度。
- **离座不想屏幕被看见** —— 按热键熄屏，任务继续。⚠️ 关屏**不等于**锁屏，走前请手动 ⌃⌘Q。

## 安装

一行命令（查最新版 → 校验 `SHA256SUMS` → 装 App + CLI → 清隔离标记 → 启动；GitHub 慢自动换镜像）：

```bash
curl -fsSL https://raw.githubusercontent.com/Hoodas101/lidkeep/main/install-remote.sh | bash
```

想先看清楚再跑？去掉 `| bash`，存成文件打开看一眼。

其他方式：

| 方式 | 操作 | 备注 |
|---|---|---|
| Homebrew | `brew install --cask hoodas101/tap/lidkeep` | 装完仍需执行一次下面的清隔离命令 |
| 安装包 | 从 [Releases](../../releases/latest) 下载 `.pkg` 双击 | 一步装好 App + CLI；被拦时右键 → **打开** |
| DMG | 下载 `.dmg` 打开，把 App 拖进 Applications | 镜像内「Install Command-Line Tool.command」可顺手装 CLI |
| 源码 | `git clone … && cd lidkeep && ./install.sh` | 需 Xcode Command Line Tools；`--cli-only` 只装 CLI |

装好后点菜单栏 ☀ → **关闭显示器**，屏幕立刻全黑，按 ⌃⌥⌘B 恢复。

### 未公证：装前清一次隔离标记

Release 产物用 **ad-hoc 自签名，没走公证**（本项目没有付费 Apple 开发者证书），于是 Gatekeeper 把下载来的副本当成不可信。macOS 26 实测：

| 途径 | Gatekeeper 行为 |
|---|---|
| 直接下载 `.pkg` / `.dmg` / zip | `spctl` 对安装包**和** App 都返回 `rejected`（拒绝打开） |
| `brew install --cask` | Homebrew 自己打隔离标记，App 同样 `rejected` |
| 打开带隔离标记的副本 | 系统拒绝打开，**可能直接把 App 丢进废纸篓** |

`brew` 在这里帮不上忙（Homebrew 6 里 `--no-quarantine` 已删除）。所以每条路径都要**手工执行一次**：

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

（手动下载 `.dmg` / `.pkg` 的话，也可对文件右键 → **打开**，确认一次即可。）

**彻底解决要靠公证** —— Developer ID 签名加公证票据。做完后上述路径都变普通双击，这是下个版本最高优先级。在此之前，每个 Release 都附带 `SHA256SUMS` 与构建来源证明（SLSA），可自行核验下载物确实出自本仓库：

```bash
shasum -a 256 -c SHA256SUMS                                  # 校验文件完整性
gh attestation verify lidkeep-macos.zip -R Hoodas101/lidkeep   # 验证构建来源
```

### 中国大陆下载

`github.com` 的 发布安装包在国内经常完全不可达 —— 实测**10 秒只下载到 0 字节**，而 `api.github.com`、`raw.githubusercontent.com` 正常。这是 CDN 层阻断，与本项目无关。

在 Release 链接前加 `https://gh-proxy.com/` 走镜像。已实测与官方产物**逐字节一致**（SHA-256 相符、长度完整），约 **173 KB/s**：

```bash
V=2.2.2
curl -L -O "https://gh-proxy.com/https://github.com/Hoodas101/lidkeep/releases/download/v$V/LidKeep-$V.dmg"
shasum -a 256 "LidKeep-$V.dmg"   # 必须与 Release 的 SHA256SUMS 一致
```

`gh-proxy.com` 是第三方加速，不受本项目控制，可能变化或失效。装前务必核对 `SHA256SUMS`；能直连时优先官方地址。

### 从更早版本升级

本产品自 v2.0.0 起更名 **LidKeep**，CLI 名、App 名与全部 bundle identifier 都已变。v1.x 留下的状态（配置目录、登录项、提权助手与防睡账本）**不再**自动迁移或清理：升级前请自备份 `~/Library/Application Support/` 下对应目录，并删旧版 App。

## 使用

**菜单栏** —— 点 ☀ / 🌙 图标：

- **关闭显示器** —— 立即熄屏，机器保持运行（再点或按热键恢复）
- **状态：… ▸** —— 标题即当前状态，例 `状态：电源保持唤醒`；点开改的是此刻生效的那套
- **安装提权助手（首次）…** —— 让「合盖时 保持唤醒」覆盖电池与合盖（弹一次密码框）
- **设置…** —— 四个标签页：通用 / 热键 / 电池 / 其他
- **热键自检** —— 自动合成一次热键验证整条链路（无副作用）
- **打开日志**

设置面板的四个页：**通用**（两套电源方案并列、恢复亮度、合盖时熄灭内屏）、**热键**（录任意组合、可整体停用、兜底超时）、**电池**（自定义电量下限 + 触底动作）、**其他**（登录启动、自动更新、安全提醒）。

**CLI**：

```bash
lidkeep off                    # 立即黑屏（一次性 daemon，超时自动恢复）
lidkeep off --timeout 3600     # 自定义兜底超时
lidkeep on                     # 恢复显示
lidkeep toggle                 # 一键切换（可绑快捷键工具 / 远程脚本）
lidkeep status                 # 查看状态（含电源与电量）
lidkeep doctor                 # 综合自检：关屏能力、显示器可控性、进程、残留
lidkeep version                # 查看版本（反馈问题时附上）
lidkeep bright 0.5             # 直接读写系统亮度
lidkeep service install        # 以 launchd 服务常驻（不用菜单栏 App 时）
lidkeep config --key 11 --mods ctrl,alt,cmd --timeout 43200
lidkeep config --battery 20    # 电量下限 %：低于则拒绝/退出黑屏（0 = 不限制）
lidkeep config --auto-nosleep  # 关屏时自动联动防睡，恢复时自动复位
lidkeep plan                    # 查看两套电源方案，以及此刻哪套生效
lidkeep plan --ac --lid nothing                  # 接电源时合盖持续运行
lidkeep plan --battery --keep-awake off --display-on on
lidkeep plan --keep-awake on    # 不带 --ac/--battery 表示两套一起改
```

`lidkeep plan` 改的就是菜单栏那两套方案（`--lid sleep|nothing`、`--keep-awake on|off`、`--display-on on|off`）。设置面板更顺手，这条命令给脚本和远程 shell 用。

默认热键 **⌃⌥⌘B**。组合必须带至少一个修饰键（⌘/⌃/⌥/⇧）—— macOS 不允许无修饰键的全局热键。

**多显示器**：关屏对所有在线显示器生效。但多数 HDMI / DVI / DP 外接屏不支持软件亮度，关不掉 —— `lidkeep doctor` 会明确列出哪块屏不可控，不会让你以为它坏了。

## 合盖 / 电池 / 无显示器时不睡眠

黑屏只关背光，系统仍会按设置睡眠。黑屏期间要机器持续工作（远程、下载、合盖外接），就开防睡眠：

```bash
lidkeep nosleep setup                  # 一键到位：装助手 + 关屏联动 + 立即防睡
lidkeep nosleep on                     # 进程级（caffeinate，仅插电有效）
lidkeep nosleep on --system            # 系统级（覆盖电池与合盖，需先装助手）
lidkeep nosleep on --timeout 3600      # 定时自动停止
lidkeep nosleep status                 # 查看层级 / 电源 / 已持续时间
lidkeep nosleep off                    # 停止并复位
```

**合盖不睡眠**：在菜单栏点开**合盖时**，选**保持唤醒**即可，不用开终端。合盖后内屏熄灭、机器持续运行，下载 / 远程 / 外接显示 / 长任务都照常。守护通过 SMC 检测合盖状态（MSLD 键），合盖时内屏亮度归零、开盖自动恢复；只动内屏，外接显示器不受影响；守护停止时（电量到下限 / 超时 / 手动关）也会恢复亮度，不会留下黑屏。可以在**通用**页用「合盖时熄灭内屏」单独关掉这一项。相关标志写入配置，App 或电脑重启后会自动恢复守护。

**为什么系统级要提权助手？** `caffeinate -s` 按 man page 明写「仅 AC 电源有效」；要覆盖电池与合盖只能调 `pmset disablesleep`，而它必须以 root 运行。装一次（要管理员密码）：

```bash
sudo lidkeep nosleep install-helper    # 最小权限：sudoers 限定仅本工具、仅四个白名单参数
lidkeep nosleep detect                 # 查看本机对 disablesleep 的支持
sudo lidkeep nosleep uninstall-helper  # 卸载（先复位再删除）
```

安全设计：

- 助手是参数白名单脚本，只接受 `on` / `off` / `status` / `detect`，借不走执行别的命令
- sudoers 仅授权单用户、以 root、精确匹配这四个参数
- 卸载先复位 `disablesleep 0` 再删助手，杜绝「系统永不睡」残留
- 开机 LaunchDaemon + 每次启动自愈检查双保险：异常退出自动复位
- **占用记账**：`disablesleep` 是唯一的全局开关，「关屏联动」和「手动防睡」可能同时依赖它。助手记下每个占用方，任一方停止只注销自己 —— 不会顺手关掉别人正在用的防睡（账本 `/var/db/lidkeep-nosleep`，归 root 所有，普通用户伪造不了）
- **与远控共存**：ToDesk / Sunlogin / UURemote / TeamViewer 等远控用同一开关保持在线。检测到它们在跑，`doctor` 说明「远程控制软件在用着」，不会误当成待清理的残留
- 电量下限对防睡同样生效 —— 合盖 + 电池 + 不睡是最容易耗干电池的组合

## 原理

不用 macOS 的「显示器睡眠」（那会停掉帧缓冲，远程看不到画面），而是把**系统亮度归零**，同时用 `caffeinate -di` 维持一个断言，保证显示管线满功率。实测：

| 检测项 | 正常显示 | 黑屏时 |
|---|---|---|
| 截帧内容 | 正常渲染 | 完整渲染（不是涂黑） |
| 内屏亮度 | 例如 0.41 | **0.0**（背光全关，屏幕不发光） |
| `CGDisplayIsAsleep()` | 0 | **0**（显示器从不睡） |
| 显示控制器电源状态 | 4（满功率） | **4**（满功率） |

这是有意的取舍：真正的显示器睡眠能多省约 0.5–1.5 W，但远程画面就没了。LidKeep 保证机器始终可被远程操控。

## 界面语言

**跟随系统**：中文系统 → 中文界面；其余（含英文）→ 英文。菜单栏 App 与 CLI 一致，无需设置。

要临时或固定切换：`LIDKEEP_LANG=en lidkeep doctor`（`zh` / `en`），或在 `~/Library/Application Support/LidKeep/config.json` 设 `"lang": "en"`。配置可选 `auto`（默认）/ `zh` / `en`，环境变量优先级最高。

英文界面对应文案：**Turn Display Off** / **Status: …** ▸ **Stay awake after the display sleeps** · **Keep display on** · **When the lid closes**（**Sleep** / **Keep awake**）。

## 还有这些细节

- **热键无需任何授权**。全局热键走 Carbon `RegisterEventHotKey`，由 WindowServer 直接派发 —— 不需要「辅助功能」或「输入监控」任何授权，反复重编译重装也不失效（ad-hoc 签名的二进制每次重编译都会丢 TCC 授权，是这类小工具最常见的坑）。**唯一例外**：合盖「保持唤醒」需要下面那个特权 helper，会一次性要你输一次管理员密码（见「为什么系统级需要特权 helper？」与 [SECURITY.md](SECURITY.md)）。
- **崩溃安全**。黑屏期间进程被意外杀死，下次启动自动恢复原亮度；另有可配兜底超时（默认 12 小时）作最后安全网。
- **电量保护**。仅电池且放电时生效：低于下限（默认 20%）拒绝关屏；黑屏期间每 30 秒复查，跌破立即恢复并通知。插电不干预。可在设置面板或 `lidkeep config --battery 0` 关闭。
- **CLI 与 App 状态互通**。SSH 里 `lidkeep on` 能唤醒菜单栏 App 关掉的屏幕，反之亦然。
- **单实例**。重复启动干净接管，并清理遗留的 `caffeinate` 孤儿。
- **菜单里的更新与关于**。「在 GitHub 上查看」一键开仓库；「关于 LidKeep」显示版本号、commit 与许可证；「检查更新…」调 GitHub Releases API 比版本，有新版本给下载入口。
- **后台自动检查更新**（默认开，可关）。App 每 24 小时静默查一次版本号，**成功才记时间戳** —— 失败留给下个心跳重试，不会因一次离线整天不查。发现新版本只在菜单栏打一个 `⬆` 徽标、顶部放「打开新版发布页」入口，不弹窗打断；提醒留着直到你装上新版本。请求只读公开版本号，不上传任何本机信息。

## 环境要求

- macOS 13 Ventura 及以上（universal binary，Apple Silicon 与 Intel 均可）
- 内置显示器（走 DisplayServices 控亮度；不支持 DDC 的外接显示器不受控）

## 常见问题

**热键没反应？** 看菜单栏图标旁的 ⚠。三种常见原因：组合被其他 App 占用（换一个）、组合没带修饰键、App 刚重装（退出重开一次）。热键本身永远不需要授权。

**环境光自动亮度会干扰黑屏吗？** 不会。程序每 0.5 秒重设亮度 0，环境光压不住。

**为什么不用 `pmset displaysleepnow`？** 真正的显示器睡眠会拆掉帧缓冲，远程端根本看不到画面；而且很多 App（浏览器、Electron）持有 `NoDisplaySleepAssertion`，根本进不了显示器睡眠。亮度归零在任何情况下都有效，且是唯一保持远程画面可用的方法。

## 卸载

```bash
./uninstall.sh           # 或: make uninstall
# 配置与日志（可选）: rm -rf ~/Library/Application\ Support/LidKeep
```

## 开发

```bash
make            # 构建 CLI + App 到 build/
make test       # 端到端冒烟测试（参数校验 / 配置往返 / 防睡眠 / 资产一致性 / 文案双向对齐）
make dev-tools  # 编译调试小工具到 build/dev-tools/
make clean
```

源码结构（Swift 要求主文件名为 `main.swift`，因此按 target 分目录）：

- `Sources/CLI/main.swift` —— 命令行工具
- `Sources/Bar/main.swift` —— 菜单栏 App
- `Sources/Shared/` —— 两个 target 共用的**唯一实现**（配置模型、系统状态与亮度、电源方案、进程归属、本地化、版本）
- `dev-tools/` —— 开发期辅助工具，以及 `smoke.sh` 冒烟测试与 `check-l10n.py` 文案校验

`make test` 自动跳过当前环境跑不了的用例（如菜单栏 App 常驻时不做真实关屏，避免打断会话）；设 `SMOKE_FULL=1` 强制跑真实关屏 / 恢复。

**构建要求：** macOS 13+ 且装了 Xcode Command Line Tools（`xcode-select --install`）。除它自带的 Swift 工具链外无任何第三方依赖；默认构建 universal binary（Apple Silicon + Intel）。

> **注意 —— `make all` 会就地改写 `Sources/Info.plist`。** 它会把最新 git tag 的版本号写进 `<!--VERSION-->` 占位符，所以构建后 `git status` 会显示 `Sources/Info.plist` 被改动。这正是版本号与 tag 保持同步的机制；发布时把它一并提交即可（别跟它较劲）。

**推广素材（截图 / 演示 GIF）：** 不入库 —— 用 `./dev-tools/capture-promo.sh`（menu / settings / `settings-win` / gif）在本地生成。脚本留倒计时让你摆好界面；`settings-win` 按窗口 ID 截取设置窗口，无需手动裁剪。原始整屏帧含你的桌面，已被 git 忽略。

## 已知限制

- **外接显示器可能关不掉。** 关屏走软件亮度接口，多数 HDMI / DVI / DP 外接屏不暴露该接口，只有内建屏会真正熄灭；`lidkeep doctor` 会点名哪几块没灭（真正的显示器睡眠能让它们也灭，但会中断远程画面，故刻意不做）。
- **关屏不等于锁屏。** 关屏期间任何能碰到键鼠的人都能照常操作机器，只是看不见画面。离座请手动锁屏（⌃⌘Q）。

## 打赏支持

如果这个项目帮到你，**⭐ [点个 Star](../../stargazers)** 是最省事也最实在的帮助；问题与想法欢迎来 [Discussions](../../discussions) 聊。

如果想再进一步，欢迎请作者喝杯咖啡 —— 每一杯都是持续更新的动力 ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="微信打赏" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="支付宝打赏" width="220">
</p>

**国际支付（无需大陆银行卡）：** GitHub Sponsors、Ko-fi、PayPal *正在由作者接入* —— 开通后链接会补到这里。在那之前，点个 ⭐ Star 或提个详细 Issue，帮助比想象中大。

**现在就想用信用卡 / PayPal？** GitHub Sponsors 在 `github.com/Hoodas101/lidkeep` 开通后即可全球可用，无需任何中国支付账号。

## 许可

[MIT](LICENSE)
