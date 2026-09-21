# LidKeep 配置参考（config.json）

配置文件位于：

```
~/Library/Application Support/LidKeep/config.json
```

菜单栏 App 与 CLI **共写同一份**文件。它使用逐字段容错解析——单个字段缺失或损坏只会退回默认值，不会让整份配置解析失败（那样会连热键、电量下限一起被重置）。

> **重要心智模型：电源方案是真值，三个布尔是「投影」。**
> `planAC` / `planBattery`（每个都是一个 `PowerPlan`）是你真正保存下来的东西。
> `autoNosleep` / `lidAwake` / `keepDisplayOn` 只是「当前电源来源那套方案」的派生值，
> **不单独持久化**。改耗电行为请走 `lidkeep plan`（或直接编辑方案），不要只改投影布尔——
> 周期性的方案重算会把投影重新算回去，你的改动会被无声抹掉。

## 顶层字段

| 字段 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `keyCode` | Int | `11` (B) | 全局热键的虚拟键码 |
| `modFlags` | UInt64 | `MOD_CTRL\|MOD_ALT\|MOD_CMD` (⌃⌥⌘) | 修饰键位掩码，见下表 |
| `timeout` | Double | `43200` | 黑屏后自动恢复的兜底超时（秒）；`0` 关闭 |
| `restoreFixed` | Float? | `nil` | 恢复时的固定亮度；`nil` = 恢复黑屏前的亮度 |
| `batteryFloor` | Int | `20` | 电量下限 %；`0` = 不限制 |
| `batteryAction` | Int | `0` | 触底时做什么，见下表 |
| `hotkeyEnabled` | Bool | `true` | 是否注册全局热键；关掉后只能从菜单栏点击 |
| `autoNosleep` | Bool | `false` | 关屏时联动防睡眠（投影，真值在方案 `keepAwake`） |
| `lidAwake` | Bool | `false` | 合盖不睡眠长期模式（投影，真值在方案 `lid`） |
| `lidBlackout` | Bool | `true` | 合盖时熄灭内屏（独立开关） |
| `lang` | String | `"auto"` | 界面语言：`auto`(跟随系统) / `zh` / `en` |
| `keepDisplayOn` | Bool | `false` | 保持屏幕常亮（投影，真值在方案 `displayOn`） |
| `autoCheckUpdate` | Bool | `true` | 后台自动检查更新（节流 24h） |
| `lastUpdateCheckAt` | Double | `0` | 上次自动检查的 Unix 时间戳（仅用于节流） |
| `schemaVersion` | Int | — | 配置 schema 版本（自动迁移用） |
| `planAC` | PowerPlan | 见下 | 接通电源时的方案 |
| `planBattery` | PowerPlan | 见下 | 使用电池时的方案 |

### 修饰键掩码（`modFlags`）

| 常量 | 值 | 键 |
|---|---|---|
| `MOD_SHIFT` | `1 << 17` | ⇧ |
| `MOD_CTRL` | `1 << 18` | ⌃ |
| `MOD_ALT` | `1 << 19` | ⌥ |
| `MOD_CMD` | `1 << 20` | ⌘ |

组合时按位或，例如 `⌃⌥⌘` = `MOD_CTRL | MOD_ALT | MOD_CMD` = `(1<<18)|(1<<19)|(1<<20)` = `[` → 数值 `917504`。

全局热键**必须至少包含一个修饰键**——macOS 拒绝无修饰键的全局热键。

### `batteryAction`（触底动作）

| 值 | 名称 | 行为 |
|---|---|---|
| `0` | `restoreOnly` | 只恢复屏幕；并放开「保持屏幕常亮」（保留防睡眠） |
| `1` | `restoreAndRelease` | 恢复屏幕 **并** 撤销防睡眠（全面放手） |
| `2` | `notifyOnly` | 只通知，状态原样保留 |

## PowerPlan（单一电源来源下的方案）

| 字段 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `keepAwake` | Bool | `false` | 息屏后保持唤醒（关屏/息屏期间阻止**系统**睡眠，屏幕照常熄灭） |
| `displayOn` | Bool | `false` | 保持屏幕常亮（阻止**显示器**自动睡眠） |
| `lid` | String | `"sleep"` | 合盖时：`"sleep"`(交回系统) / `"nothing"`(保持唤醒) |

三个开关互不排斥：`keepAwake` 作用于系统、`displayOn` 作用于显示器、`lid` 独立于前两者。

## 修改配置的两种方式

**1. 用 CLI（推荐，自动保持方案/投影一致）：**

```bash
lidkeep config --key 11 --mods ctrl,alt,cmd --timeout 43200
lidkeep config --battery 20                 # 电量下限 %
lidkeep config --battery-action 0           # 0/1/2
lidkeep config --hotkey off                 # 关闭全局热键
lidkeep plan --ac --lid nothing             # 接电时合盖保持唤醒
lidkeep plan --battery --keep-awake off --display-on on
lidkeep plan --keep-awake on               # 不加 --ac/--battery = 同时改两套
```

**2. 手写 JSON（仅当你知道自己在做什么）：** 直接编辑 `planAC` / `planBattery`，
不要只改 `autoNosleep` / `lidAwake` / `keepDisplayOn` 这三个投影——它们会被周期重算覆盖。
改完保存即可，App/CLI 会重载。

## 示例：始终接电、合盖保持唤醒、电池时老实睡觉

```json
{
  "planAC":      { "keepAwake": false, "displayOn": false, "lid": "nothing" },
  "planBattery": { "keepAwake": false, "displayOn": false, "lid": "sleep" },
  "batteryFloor": 20,
  "batteryAction": 0,
  "hotkeyEnabled": true,
  "keyCode": 11,
  "modFlags": 917504
}
```

> 想看当前生效的完整配置：`lidkeep doctor`（会同时打印两套方案的真值，不只是投影）。
