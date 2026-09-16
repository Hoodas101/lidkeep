<img src="docs/icon.png" width="112" align="right" alt="LidKeep app icon">

# LidKeep

**让 Mac 熄屏，但别停下。**

屏幕全黑，机器照常运行：远程桌面还在、下载还在、构建还在。按一下热键（或 SSH 里一条命令）立刻恢复画面。

[![Release](https://img.shields.io/github/v/release/Mihooni/lidkeep)](../../releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](#环境要求)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

English: [README.md](README.md)

```
$ lidkeep off      # 屏幕熄灭，系统继续跑
$ lidkeep on       # 恢复显示（SSH 里执行同样有效）
```

## 它解决什么问题

macOS 把「屏幕灭」和「机器睡」绑在了一起。你想要的只是灭屏幕，系统却连机器一起睡过去了。

| 你的场景 | 通常的结果 |
|---|---|
| 想熄屏省电，但人不在机器旁 | 一熄屏远程就瞎了：系统或显示器睡眠后，远程桌面连上只有一片黑 |
| 合上盖子塞进包里带走 | 机器跟着睡了 —— 下载中断、构建中断、远控掉线 |
| 合盖接外接显示器 / 合盖带走 | 一旦阻止了睡眠，内屏就一直亮着 —— macOS 不会因为你合上盖子就关背光，纯白耗电 |
| 用 `caffeinate` / 防睡眠工具硬扛 | 屏幕整夜亮着：费电、烧屏、内容还被别人看见 |
| 用系统自带的「显示器睡眠」 | 帧缓冲被拆掉，屏幕共享抓不到画面，远程等于断线 |

| 方式 | 屏幕灭 | 远程画面 | 机器继续跑 | 合盖可用 | 需要权限 |
|---|:---:|:---:|:---:|:---:|---|
| 系统「显示器睡眠」 | ✅ | ❌ 断开 | ❌ 会睡 | — | 无 |
| `pmset displaysleepnow` | ✅ | ❌ 断开 | ❌ 会睡 | — | 无 |
| 屏保 / 锁屏 | ❌ 还亮 | ✅ | ⚠️ 到点会睡 | — | 无 |
| `caffeinate` | ❌ 一直亮 | ✅ | ✅ | ❌ 仅插电有效 | 无 |
| 第三方防睡眠 App | ❌ 一直亮 | ✅ | ✅ | 部分支持 | 部分要授权 |
| **LidKeep** | ✅ | ✅ | ✅ | ✅ | **热键零授权**（合盖需装一次助手） |

差别只有一行：**LidKeep 灭的是背光，不是显示器电源**。显示器从未睡眠，帧缓冲一直在渲染，所以远程端抓到的永远是真实画面，而不是一片黑。

## 关屏与电源方案

菜单里只有两件事：

| 菜单项 | 解决什么 | 怎么用 |
|---|---|---|
| **关闭显示器** | 屏幕立刻黑掉 —— 背光被切断，不是「调暗」—— 机器照常运行 | 点一下，或按 ⌃⌥⌘B |
| **状态：… ▸** | 其余所有场景 | 标题就是**当前状态**（例：`状态：电源保持唤醒`）；点开按电源来源各设一套，三个开关可同时开启 |

**电源方案**沿用 Windows「电源选项」的思路：接着电源和用电池是两种场景，各存一套设置，拔掉充电器几秒内自动切换 —— 标题里的**电源 / 电池**就是此刻生效的那一套。

| 开关 | 会发生什么 | 代价 |
|---|---|---|
| **息屏后保持唤醒** | 屏幕黑着，机器继续运行 —— 无论是你主动关的屏，还是系统自己熄的屏 | 较省电 |
| **保持屏幕常亮** | 屏幕不会自动熄灭 | 较耗电 |
| **合盖时** | `睡眠`（系统默认）或 `保持唤醒`（持续运行，内屏熄灭） | 选「保持唤醒」需要提权助手，建议接电源 |

三点须知：

- 三项**互不排斥**：前两项一个管系统睡眠、一个管显示器睡眠，合盖行为独立于两者。
- **息屏后保持唤醒**在你打开开关的**那一刻**就自己持有防睡眠断言，所以**不点「关闭显示器」、让屏幕自己熄掉**也照样有效。
- 方案若因故**暂时**起不来（缺提权助手、电量低于下限），菜单标题会写明「未生效」，条件满足后自动补起 —— **你的设置不会被悄悄改掉**。

## 三种典型用法

- **把 Mac 当远程主机**（UURemote / ToDesk / VNC / SSH）—— `lidkeep off` 熄屏，机器不睡，远程画面正常；回到机器前按热键恢复。怕忘？默认 12 小时兜底自动恢复。
- **合盖收纳，任务不断** —— 点开菜单里的**合盖时**选**保持唤醒**，合盖后内屏自动熄灭，下载 / 构建 / 远程照常，开盖自动恢复亮度。
- **人离开工位，不想屏幕被人看见** —— 按热键熄屏，任务继续跑。⚠️ 关屏**不等于**锁屏，离开前请手动 ⌃⌘Q。

## 安装

**一行命令**（查最新版 → 下载并校验 `SHA256SUMS` → 装 App 与 CLI → 清隔离标记 → 启动；GitHub 慢会自动换镜像）：

```bash
curl -fsSL https://raw.githubusercontent.com/Mihooni/lidkeep/main/install-remote.sh | bash
```

想先看清楚再跑？去掉 `| bash`，存成文件打开看一眼即可。

**也可以任选下面一种：**

| 方式 | 怎么做 | 备注 |
|---|---|---|
| Homebrew | `brew install --cask mihooni/tap/lidkeep` | 装完仍需执行一次下面的清隔离命令 |
| 安装包 | 从 [Releases](../../releases/latest) 下载 `.pkg` 双击 | 一步装好 App + CLI；被拦时右键 → **打开** |
| DMG | 下载 `.dmg` 打开，把 App 拖进 Applications | 镜像内「Install Command-Line Tool.command」可顺手装 CLI |
| 源码 | `git clone … && cd lidkeep && ./install.sh` | 需 Xcode Command Line Tools；`--cli-only` 只装 CLI |

装好后点菜单栏 ☀ → **关闭显示器**，屏幕立刻全黑，按 ⌃⌥⌘B 恢复。

### 未公证：装前请先清一次隔离标记

Release 产物用的是 **ad-hoc 临时签名，未经公证**（本项目没有付费 Apple 开发者证书），所以 Gatekeeper 会把下载来的副本视为不可信。macOS 26 实测：

| 途径 | Gatekeeper 的实际行为 |
|---|---|
| 直接下载 `.pkg` / `.dmg` / zip | `spctl` 对安装包**和** App 均判定 `rejected` |
| `brew install --cask` | Homebrew **自己**会打上隔离标记，App 同样被判定 `rejected` |
| 打开带隔离标记的副本 | 系统拒绝打开，**并可能直接把 App 移进废纸篓** |

`brew` 在这里帮不上忙（`--no-quarantine` 在 Homebrew 6 中已不存在）。所以每条路径都需要**手工执行一次**：

```bash
xattr -dr com.apple.quarantine /Applications/LidKeep.app
```

（手动下载 `.dmg` / `.pkg` 的话，也可以改成对文件右键 → **打开**，确认一次即可。）

**真正的解法是公证** —— Developer ID 签名加公证票据。做完之后上述所有路径都会变成普通双击，这是下个版本的最高优先级。在此之前，每个 Release 都附带 `SHA256SUMS` 与 GitHub 构建来源证明（SLSA），可以自行核验下载物确实出自本仓库：

```bash
shasum -a 256 -c SHA256SUMS                                  # 校验文件完整性
gh attestation verify lidkeep-macos.zip -R Mihooni/lidkeep   # 验证构建来源
```

### 中国大陆下载

`github.com` 的 Release 二进制资产在国内经常完全不可达 —— 实测**10 秒下载 0 字节**，而同一域名体系下的 `api.github.com` 与 `raw.githubusercontent.com` 都正常。这是 CDN 层面的阻断，与本项目无关。

在 Release 链接前加 `https://gh-proxy.com/` 即可走镜像。已实测与官方产物**逐字节一致**（SHA-256 相符、长度完整），速度约 **173 KB/s**：

```bash
V=2.2.2
curl -L -O "https://gh-proxy.com/https://github.com/Mihooni/lidkeep/releases/download/v$V/LidKeep-$V.dmg"
shasum -a 256 "LidKeep-$V.dmg"   # 必须与 Release 里的 SHA256SUMS 一致
```

`gh-proxy.com` 是第三方加速服务，不受本项目控制，可能变化或失效。安装前务必核对 `SHA256SUMS`；能直连时优先用官方地址。

### 从更早版本升级

本产品自 v2.0.0 起更名为 **LidKeep**，CLI 名、App 名与全部 bundle identifier 都已改变。v1.x 留下的状态（配置目录、登录项、提权助手与防睡眠账本）**不再**自动迁移或清理：升级前请自行备份 `~/Library/Application Support/` 下对应目录，并删除旧版 App。

## 使用

**菜单栏** —— 点 ☀ / 🌙 图标：

- **关闭显示器** —— 立即熄屏，机器保持运行（再点一次或按热键恢复）
- **状态：… ▸** —— 见上文「关屏与电源方案」。标题即当前状态，例 `状态：电源保持唤醒`；点开改的是此刻生效的那一套
- **安装提权助手（首次使用）…** —— 让「合盖时 保持唤醒」覆盖电池与合盖（弹一次系统密码框）
- **设置…** —— 四个标签页：通用 / 热键 / 电池 / 其他
- **热键自检** —— 自动合成一次热键验证整条链路（无副作用，不会开关屏幕）
- **打开日志**

设置面板四个标签页分别负责：**通用**（两套电源方案并列可改、恢复亮度、合盖时熄灭内屏）、**热键**（直接录制任意组合、可整体停用全局热键、兜底超时）、**电池**（自定义电量阈值 + 触底动作）、**其他**（登录时启动、自动检查更新、安全提醒）。

**CLI**：

```bash
lidkeep off                    # 立即黑屏（一次性 daemon，超时自动恢复）
lidkeep off --timeout 3600     # 自定义兜底超时
lidkeep on                     # 恢复显示
lidkeep toggle                 # 一条命令切换（可绑定到快捷键工具 / 远程脚本）
lidkeep status                 # 查看状态（含电源与电量）
lidkeep doctor                 # 综合自检：关屏能力、显示器可控性、进程、残留
lidkeep version                # 查看版本（反馈问题时一并附上）
lidkeep bright 0.5             # 直接读写系统亮度
lidkeep service install        # 以 launchd 服务常驻（不用菜单栏 App 时）
lidkeep config --key 11 --mods ctrl,alt,cmd --timeout 43200
lidkeep config --battery 20    # 电量下限 %：低于则拒绝/退出黑屏（0 = 不限制）
lidkeep config --auto-nosleep  # 关屏时自动联动防睡眠，恢复显示时自动复位
lidkeep plan                    # 查看两套电源方案，以及此刻哪一套在生效
lidkeep plan --ac --lid nothing                  # 接电源时合盖持续运行
lidkeep plan --battery --keep-awake off --display-on on
lidkeep plan --keep-awake on    # 不带 --ac/--battery 表示两套一起改
```

`lidkeep plan` 改的就是菜单栏那两套方案（`--lid sleep|nothing`、`--keep-awake on|off`、`--display-on on|off`）。设置面板是更顺手的入口，这条命令是给脚本和远程 shell 用的。

默认热键 **⌃⌥⌘B**。组合必须带至少一个修饰键（⌘/⌃/⌥/⇧）—— macOS 不允许无修饰键的全局热键。

**多显示器**：关屏会对所有在线显示器生效。但多数 HDMI / DVI / DP 外接屏不支持软件亮度控制，这类屏幕关不掉 —— `lidkeep doctor` 会明确列出哪块屏不可控，不会让你以为它坏了。

## 防睡眠（合盖 / 电池 / 无显示器时不睡眠）

黑屏只关背光，系统本身仍会按设置睡眠。如果需要黑屏期间机器持续工作（远程访问、下载、合盖外接使用），可以开启防睡眠：

```bash
lidkeep nosleep setup                  # 一键到位：装助手 + 开关屏联动 + 立即防睡眠
lidkeep nosleep on                     # 进程级（caffeinate，仅接电源时有效）
lidkeep nosleep on --system            # 系统级（覆盖电池与合盖，需先装提权助手）
lidkeep nosleep on --timeout 3600      # 定时自动停止
lidkeep nosleep status                 # 查看层级 / 电源 / 已持续时间
lidkeep nosleep off                    # 停止并复位
```

**合盖不睡眠**：在菜单栏点开 **合盖时** 选 **保持唤醒** 即可开启，无需任何终端命令。

- **合盖后内屏熄灭、机器持续运行**：下载、远程访问、外接显示、长时间任务照常工作
- **合盖自动熄屏**（v1.5.2 起）：守护进程经 SMC 检测合盖状态（MSLD 键），合盖时把内屏亮度归零，开盖自动恢复；只动内屏，外接显示器不受影响；守护停止（电量下限 / 超时 / 手动关闭）时同样恢复，不留黑屏残局。可在设置面板的**通用**页用「合盖时熄灭内屏」单独关掉
- **持久化**：标志写入配置，App 重启 / 电脑重启后自动恢复守护
- **与关屏联动互不干扰**：合盖守护与黑屏联动防睡眠在持有者账本中是独立条目，各自开关互不影响

**为什么系统级需要提权助手？** `caffeinate -s` 的断言按 man page 明写「仅 AC 电源有效」；要覆盖电池与合盖，只能调用 `pmset disablesleep`，而它必须以 root 运行。安装助手（一次性，需输入管理员密码）：

```bash
sudo lidkeep nosleep install-helper    # 最小权限：sudoers 限定仅本工具、仅四个白名单参数
lidkeep nosleep detect                 # 查看当前系统对 disablesleep 的支持情况
sudo lidkeep nosleep uninstall-helper  # 卸载（先复位再删除）
```

安全设计：

- 助手是参数白名单脚本，只能执行 `on` / `off` / `status` / `detect`，无法被借道执行任意命令
- sudoers 仅授权单用户、以 root 身份、精确匹配这四个参数
- 卸载时先复位 `disablesleep 0` 再删助手，杜绝「系统永不睡眠」残留
- 开机 LaunchDaemon + 每次启动的自愈检查双保险：任何异常退出都会自动复位
- **持有者记账**：`disablesleep` 是唯一的全局开关，而「关屏联动」和「手动防睡眠」可能同时依赖它。助手会记录每个持有者，任一方停止时只注销自己 —— 不会顺手关掉别人正在用的防睡眠。（账本目录 `/var/db/lidkeep-nosleep`，root 拥有，普通用户无法伪造持有者）
- **与远控软件共存**：ToDesk / Sunlogin / UURemote / TeamViewer 等远控会用同一个开关保持在线。检测到它们在运行时，`doctor` 会说明「由远控软件持有」，而不是误报成需要修复的残留
- 电量下限对防睡眠同样生效 —— 合盖 + 电池 + 不睡眠是最容易耗尽电池的组合

## 它是怎么做到的

不用 macOS 的「显示器睡眠」（那会停掉帧缓冲，远程就看不到画面了），而是把**系统亮度归零**，同时用 `caffeinate -di` 持有断言，保证显示管线满功率运行。实测：

| 检测项 | 正常显示 | 黑屏时 |
|---|---|---|
| 截帧内容 | 正常渲染 | 完整渲染（不是涂黑） |
| 内屏亮度 | 例如 0.41 | **0.0**（背光完全关闭，屏幕不发光） |
| `CGDisplayIsAsleep()` | 0 | **0**（显示器从未睡眠） |
| 显示控制器电源状态 | 4（满功率） | **4**（满功率） |

代价是刻意选择的：真·显示器睡眠能多省约 0.5–1.5 W（背光关闭本身约省 1–2 W，轻载整机约 15–30%），但远程画面就没了。LidKeep 保证机器始终可被远程操控。

## 界面语言

**跟随系统**：系统语言为中文 → 中文界面；其余语言（含英文）→ 英文界面。菜单栏 App 与命令行工具一致，无需任何设置。

需要临时或固定切换时：`LIDKEEP_LANG=en lidkeep doctor`（`zh` / `en`），或在 `~/Library/Application Support/LidKeep/config.json` 里设 `"lang": "en"`。配置可选 `auto`（默认）/ `zh` / `en`，环境变量优先级最高。

英文界面下的对应文案：**Turn Display Off** / **Power plan** ▸ **Stay awake after the display sleeps** · **Keep display on** · **When the lid closes**（**Sleep** / **Keep awake**）。

## 还有这些细节

- **零授权热键**。全局热键走 Carbon `RegisterEventHotKey`，由 WindowServer 直接派发 —— 不需要「辅助功能」「输入监控」任何授权，反复重编译、重装也不会失效（ad-hoc 签名二进制每次重编译都会丢 TCC 授权，这是同类小工具最常见的坑）。
- **崩溃安全**。黑屏期间进程被意外杀死，下次启动自动恢复原亮度；另有可配置的兜底超时（默认 12 小时）作为最后安全网。
- **电量保护**。仅电池且放电时生效：低于下限（默认 20%）拒绝关屏；黑屏期间每 30 秒复查，跌破立即恢复并通知。插电不干预。可在设置面板或 `lidkeep config --battery 0` 关闭。
- **CLI 与 App 状态互通**。SSH 里 `lidkeep on` 能唤醒菜单栏 App 关掉的屏幕，反之亦然。
- **单实例**。重复启动会干净接管，并清理遗留的 `caffeinate` 孤儿进程。
- **菜单里的更新与关于**。「在 GitHub 上查看」一键打开开源仓库；「关于 LidKeep」显示版本号、commit 与许可证；「检查更新…」调用 GitHub Releases API 对比版本，发现新版本时给出下载页入口。
- **后台自动检查更新**（默认开，可在设置里关掉）。App 每 24 小时静默查一次版本号，**成功才记下时间戳** —— 失败会留给下一个心跳重试，不会因为一次离线就整天不再检查。发现新版本时只在菜单栏打一个 `⬆` 徽标、并在菜单顶部放出「打开新版发布页」入口，不弹窗打断；提醒会一直留着，直到你装上新版为止。请求只读取公开的版本号，不上传任何本机信息。

## 环境要求

- macOS 13 Ventura 及以上（universal binary，Apple Silicon 与 Intel 均可）
- 内置显示器（走 DisplayServices 控制亮度；不支持 DDC 的外接显示器不受控）

## 常见问题

**热键没反应？** 看菜单栏图标旁的 ⚠。三种常见原因：组合被其他 App 占用（换一个）、组合没带修饰键、App 刚重装（退出重开一次）。热键本身永远不需要任何授权。

**环境光自动亮度会干扰黑屏吗？** 不会。程序每 0.5 秒重设一次亮度 0，环境光变化压不住。

**为什么不用 `pmset displaysleepnow`？** 真·显示器睡眠会拆掉帧缓冲，远程端什么都看不到；而且很多 App（浏览器、Electron 应用）持有 `NoDisplaySleepAssertion`，根本进不了显示器睡眠。亮度归零在任何情况下都有效，且是唯一保持远程画面可用的方法。

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

`make test` 会自动跳过当前环境跑不了的用例（例如菜单栏 App 正在常驻时不做真实关屏，避免打断会话）；设 `SMOKE_FULL=1` 可强制跑真实关屏 / 恢复。

## 已知限制

- **部分外接显示器关不掉。** 亮度归零依赖软件亮度接口，多数 HDMI / DVI / DP 外接屏不支持它，这类屏幕在关屏时不会熄灭（`lidkeep doctor` 会具体指出是哪一块）。要让它们也熄灭只能走硬件睡眠，而那会中断远程画面 —— 本工具刻意不这么做。
- 屏幕**并非断电** —— 这是刻意设计。背光被设为 0，帧缓冲仍在渲染，因此屏幕共享 / 远程桌面仍能正常取帧。真正的显示器休眠会中断远程访问，详见[它是怎么做到的](#它是怎么做到的)。
- **关屏不等于锁屏。** 关屏期间任何能碰到键盘鼠标的人仍可操作这台机器，只是看不见画面。离开座位前请手动锁屏（⌃⌘Q）。

## 打赏支持

如果这个项目对你有帮助，欢迎请作者喝杯咖啡 —— 每一杯都是持续更新的动力 ☕

<p align="center">
  <img src="docs/donate-wechat.png" alt="微信打赏" width="220">&nbsp;&nbsp;
  <img src="docs/donate-alipay.jpg" alt="支付宝打赏" width="220">
</p>

**中国大陆以外？** 这两个码需要绑定大陆银行卡的微信 / 支付宝，海外朋友多半扫不了。
国际支付通道（信用卡 / PayPal）正在接入；在那之前，点个 ⭐ Star 或提个 Issue，
对项目的帮助比想象中大。

## 许可

[MIT](LICENSE)
