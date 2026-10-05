# LidKeep — 完整说明

这是 [README.zh-CN.md](../README.zh-CN.md) 的延伸部分。只想装上、把屏幕关掉的话，
看那份就够了；下面是完整命令、防睡眠与提权助手的设计、原理实测、过热保护、
常见问题与开发指南。

- [使用](#使用)
- [合盖 / 电池 / 无显示器时不睡眠](#合盖--电池--无显示器时不睡眠)
- [原理](#原理)
- [过热保护](#过热保护)
- [界面语言](#界面语言)
- [还有这些细节](#还有这些细节)
- [环境要求](#环境要求)
- [常见问题](#常见问题)
- [卸载](#卸载)
- [开发](#开发)
- [已知限制](#已知限制)

---

## 使用

**菜单栏**（点 ☀ / 🌙 图标）：

- **关闭显示器**：立即熄屏，机器保持运行（再点或按热键恢复）
- **状态：… ▸**：标题即当前状态，例 `状态：电源保持唤醒`；点开改的是此刻生效的那套
- **安装提权助手（首次使用）…**：让「合盖时 保持唤醒」覆盖电池与合盖（弹一次密码框）
- **设置…**：通用 / 热键 / 电池 / 其他 四个标签页
- **热键自检**：自动合成一次热键验证整条链路（无副作用）
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

默认热键 **⌃⌥⌘B**。组合必须带至少一个修饰键（⌘/⌃/⌥/⇧）；macOS 不允许无修饰键的全局热键。

**多显示器**：关屏对所有在线显示器生效。但多数 HDMI / DVI / DP 外接屏不支持软件亮度，关不掉；`lidkeep doctor` 会明确列出哪块屏不可控，不会让你以为它坏了。

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
- **占用记账**：`disablesleep` 是唯一的全局开关，「关屏联动」和「手动防睡」可能同时依赖它。助手记下每个占用方，任一方停止只注销自己，不会顺手关掉别人正在用的防睡（账本 `/var/db/lidkeep-nosleep`，归 root 所有，普通用户伪造不了）
- **与远控共存**：ToDesk / Sunlogin / UURemote / TeamViewer 等远控用同一开关保持在线。检测到它们在跑，`doctor` 说明「远程控制软件在用着」，不会误当成待清理的残留
- 电量下限对防睡同样生效：合盖 + 电池 + 不睡是最容易耗干电池的组合

## 原理

不用 macOS 的「显示器睡眠」（那会停掉帧缓冲，远程看不到画面），而是把**系统亮度归零**，同时用 `caffeinate -di` 维持一个断言，保证显示管线满功率。实测：

| 检测项 | 正常显示 | 黑屏时 |
|---|---|---|
| 截帧内容 | 正常渲染 | 完整渲染（不是涂黑） |
| 内屏亮度 | 例如 0.41 | **0.0**（背光全关，屏幕不发光） |
| `CGDisplayIsAsleep()` | 0 | **0**（显示器从不睡） |
| 显示控制器电源状态 | 4（满功率） | **4**（满功率） |

这是有意的取舍：真正的显示器睡眠能多省约 0.5–1.5 W，但远程画面就没了。LidKeep 保证机器始终可被远程操控。

## 过热保护

合盖不睡的机器（在包里、在沙发上）热量没有地方可去。LidKeep 每 30 秒读一次 `ProcessInfo.thermalState`（公开 API，不需要任何授权），分两级响应：

| 热状态 | LidKeep 怎么做 |
|---|---|
| `serious` | 一切照常运行，只通知一次：系统已开始降频 |
| `critical` | 放开全部断言（关屏 / 防睡眠 / 屏幕常亮），让机器能降频散热 |

**一个字都不写进配置。** 热量是瞬时状态，所以温度一回到 `nominal` / `fair`，你的电源方案就原样生效。这是 LidKeep 唯一一处刻意不照抄电量守卫的地方：电量下限是你**想**长期保留的设置，机身发烫不是。一次编译把机器推到 `critical`，绝不该让你丢掉「合盖时保持唤醒」这个偏好。

它也没有开关。守卫无条件常驻，闲置时每 30 秒一次闭包调用，成本可忽略；之所以必须无条件，是因为断言放掉了还能装回来，机器烧坏了不能。

## 界面语言

**跟随系统**：内置 7 种语言：中 / 英 / 日 / 韩 / 德 / 法 / 西。系统语言命中哪个就用哪个，没命中的一律回落英文。菜单栏 App 与 CLI 一致，无需设置。

要临时或固定切换：`LIDKEEP_LANG=en lidkeep doctor`，或在 `~/Library/Application Support/LidKeep/config.json` 设 `"lang": "en"`。配置可选 `auto`（默认）/ `zh` / `en` / `ja` / `ko` / `de` / `fr` / `es`，环境变量优先级最高。

长帮助文本（多行说明）只做了中 / 英两套：其余语言一律给英文版，而不是给你看不懂的中文。

英文界面对应文案分两类。菜单项：**Turn Display Off** / **Status: …**；方案开关：**Stay awake after the display sleeps** / **Keep display on** / **When the lid closes**（**Sleep** / **Keep awake**）。

## 还有这些细节

- **热键无需任何授权**。全局热键走 Carbon `RegisterEventHotKey`，由 WindowServer 直接派发，不需要「辅助功能」或「输入监控」任何授权，反复重编译重装也不失效（ad-hoc 签名的二进制每次重编译都会丢 TCC 授权，是这类小工具最常见的坑）。**唯一例外**：合盖「保持唤醒」需要下面那个提权助手，会一次性要你输一次管理员密码（见「为什么系统级要提权助手？」与 [SECURITY.md](../SECURITY.md)）。
- **崩溃安全**。黑屏期间进程被意外杀死，下次启动自动恢复原亮度；另有可配兜底超时（默认 12 小时）作最后安全网。
- **电量保护**。仅电池且放电时生效：低于下限（默认 20%）拒绝关屏；黑屏期间每 30 秒复查，跌破立即恢复并通知。插电不干预。可在设置面板或 `lidkeep config --battery 0` 关闭。
- **CLI 与 App 状态互通**。SSH 里 `lidkeep on` 能唤醒菜单栏 App 关掉的屏幕，反之亦然。
- **单实例**。重复启动干净接管，并清理遗留的 `caffeinate` 孤儿。
- **菜单里的更新与关于**。「在 GitHub 上查看」一键开仓库；「关于 LidKeep」显示版本号、commit 与许可证；「检查更新…」调 GitHub Releases API 比版本，有新版本给下载入口。
- **后台自动检查更新**（默认开，可关）。App 每 24 小时静默查一次版本号，**成功才记时间戳**，失败留给下个心跳重试，不会因一次离线整天不查。发现新版本只在菜单栏打一个 `⬆` 徽标、顶部放「打开新版发布页」入口，不弹窗打断；提醒留着直到你装上新版本。请求只读公开版本号，不上传任何本机信息。

## 环境要求

- macOS 13 Ventura 及以上（universal binary，Apple Silicon 与 Intel 均可）
- 内建显示器（走 DisplayServices 控亮度；不支持 DDC 的外接显示器不受控）

## 常见问题

**热键没反应？** 看菜单栏图标旁的 ⚠。三种常见原因：组合被其他 App 占用（换一个）、组合没带修饰键、App 刚重装（退出重开一次）。热键本身永远不需要授权。

**环境光自动亮度会干扰黑屏吗？** 不会。程序每 0.5 秒重设亮度 0，环境光压不住。

**为什么不用 `pmset displaysleepnow`？** 真正的显示器睡眠会拆掉帧缓冲，远程端根本看不到画面；而且很多 App（浏览器、Electron）持有 `NoDisplaySleepAssertion`，根本进不了显示器睡眠。亮度归零在任何情况下都有效，且是唯一保持远程画面可用的方法。

**SSH 里能用吗？锁屏后还生效吗？** 能。CLI（`lidkeep off/on/status`）可在 SSH 里执行；而锁屏（⌃⌘Q）和显示器的亮度状态是两回事：无论屏是否锁着，黑屏与防睡眠都会照常工作。

**无内置显示器的 Mac（如 Mac mini）呢？** 没有背光可关，黑屏无从谈起；但 `lidkeep nosleep` 依然能让机器保持唤醒，供远程访问与下载使用，这通常正是无头 Mac 的需求。

**会和专注模式 / 勿扰 / 夜览冲突吗？** 不会：这些是彼此独立的子系统。黑屏只做两件事：把亮度设为 0、持有一个 `caffeinate` 断言；它不碰通知、专注或色彩设置。

## 卸载

有克隆（或 `make` 环境）时：

```bash
./uninstall.sh           # 或: make uninstall
# 配置与日志（可选）: rm -rf ~/Library/Application\ Support/LidKeep
```

只有一键安装脚本装出来的 App（没有克隆）时，按 [README 的「卸载」小节](../README.zh-CN.md#卸载)手工删四项：App、CLI、登录项、配置目录。
菜单里的**卸载提权助手**只移除提权助手，**不是**卸载 App。

## 开发

```bash
make            # 构建 CLI + App 到 build/
make test       # 端到端冒烟测试（参数校验 / 配置往返 / 防睡眠 / 资产一致性 / 文案双向对齐）
make dev-tools  # 编译调试小工具到 build/dev-tools/
make clean
```

源码结构（Swift 要求主文件名为 `main.swift`，因此按 target 分目录）：

- `Sources/CLI/main.swift`：命令行工具
- `Sources/Bar/main.swift`：菜单栏 App
- `Sources/Shared/`：两个 target 共用的**唯一实现**（配置模型、系统状态与亮度、电源方案、进程归属、本地化、版本）
- `dev-tools/`：开发期辅助工具，以及 `smoke.sh` 冒烟测试、`check-l10n.py` 文案校验、`audit-l10n-concat.py` 拼接审计（漏空格、引号错位这类拼接缺陷）

`make test` 自动跳过当前环境跑不了的用例（如菜单栏 App 常驻时不做真实关屏，避免打断会话）；设 `SMOKE_FULL=1` 强制跑真实关屏 / 恢复。

**构建要求：** macOS 13+ 且装了 Xcode Command Line Tools（`xcode-select --install`）。除它自带的 Swift 工具链外无任何第三方依赖；默认构建 universal binary（Apple Silicon + Intel）。

> **注意：** `make all` 会就地改写 `Sources/Info.plist`。** 它会把最新 git tag 的版本号写进 `<!--VERSION-->` 占位符，所以构建后 `git status` 会显示 `Sources/Info.plist` 被改动。这正是版本号与 tag 保持同步的机制；发布时把它一并提交即可（别跟它较劲）。

**推广素材（截图 / 演示 GIF）：** 不入库，用 `./dev-tools/capture-promo.sh`（menu / settings / `settings-win` / gif）在本地生成。脚本留倒计时让你摆好界面；`settings-win` 按窗口 ID 截取设置窗口，无需手动裁剪。原始整屏帧含你的桌面，已被 git 忽略。

## 已知限制

- **外接显示器可能关不掉。** 关屏走软件亮度接口，多数 HDMI / DVI / DP 外接屏不暴露该接口，只有内建显示器会真正熄灭；`lidkeep doctor` 会点名哪几块没灭（真正的显示器睡眠能让它们也灭，但会中断远程画面，故刻意不做）。
- **热保护只释放它自己恢复得了的东西。** 它会放开熄屏、防睡眠、屏幕常亮，以及你的电源方案所持有的合盖守护；机器凉下来之后，这些都会自行恢复。而你用 `lidkeep nosleep on --system` 手动起的守护进程会被**刻意留着**：热保护无从知道你之后还想不想让它继续跑，贸然停掉等于拿一台发烫的机器，换来一个再也找不回的设置。
- **它不是锁屏。** 机器对键盘前的任何人都完全可用，只是对方看不见屏幕。要离开请先按 ⌃⌘Q 锁屏。
