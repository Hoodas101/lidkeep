import Foundation
import Darwin

// MARK: - 配置模型（两端共用的唯一一份定义）
//
// Bar 与 CLI 共写同一个 config.json，所以这个结构**只能有一份定义**。
//
// 历史上两端各写了一遍，于是每加一个字段都要同时改两处（属性 + CodingKeys + decode）。
// 漏掉任何一处，另一端落盘时就会把那个字段整段抹掉 —— 用户看到的现象是
// 「刚设置好，过一会儿自己变回去了」，且毫无提示。实测踩过两次
// （lidBlackout、自动检查更新那两个字段）。合并到这里之后，加字段只需要改这一处。
//
// 兼容纪律（改字段时务必遵守）：
//   * 新字段一律 `decodeIfPresent` + 默认值 —— 旧配置读出来不能是空的
//   * 语义变过就升 `schemaVersion` 并在 `migrate()` 里纠正，不要沿用旧含义
//   * 单个字段类型被写坏（字符串/数组）时只该丢这一个字段，不能整份配置重置

// MARK: - Carbon 修饰键位
// 取值与 Carbon 的 cmdKey/shiftKey/optionKey/controlKey 一致，但这里不引 Carbon 框架
// （CLI 侧不需要为了这几个常量加载 HIToolbox）。
let MOD_CTRL: UInt64  = 1 << 18
let MOD_ALT: UInt64   = 1 << 19
let MOD_CMD: UInt64   = 1 << 20
let MOD_SHIFT: UInt64 = 1 << 17

/// 配置结构的当前版本，「全新配置」用它初始化。
/// 新增字段若带安全默认值（decodeIfPresent ?? x）就不必 bump；只有「同一字段换了语义」
/// 或「需要按旧值推导新值」时才 bump，并在 `Config.migrate()` 里补一步。
/// 必须与 migrate() 最后一步设的值一致 —— 放在这里就是为了两端不会各写一个数。
let configSchemaVersion = 2

// MARK: - 兜底超时的取值范围
//
// timeout 是「黑屏后多久自动把屏幕叫回来」，语义上是个几小时量级的秒数。
// 上界取 365 天不是技术限制，是「比这更长就没有意义」的判断 —— 但**必须有**：
// 少了它，`--timeout 1e300` 会通过校验、落盘、然后在每一次 `Int(timeout)` 转换时
// 触发 fatal error（Double 转 Int 溢出是 trap，不是返回 0）。
// 更糟的是它改不回来：用户想 `config --timeout 43200` 救回来，改的过程自己先崩。
let timeoutUpperBound: Double = 365 * 24 * 3600
let timeoutDefault: Double = 43200

/// 把任意 timeout 夹回合法区间。**读**与*写*两侧都必须走它：
/// 只在 CLI 入口拦是拦不住的，config.json 是纯文本，谁都能手写进去。
func sanitizeTimeout(_ v: Double) -> Double {
    guard v.isFinite else { return timeoutDefault }      // NaN / ±inf 一律回到默认
    if v <= 0 { return 0 }                              // 0 = 不启用兜底，是合法取值
    return min(v, timeoutUpperBound)
}

/// timeout 显示成整秒。**任何**把 timeout 插进字符串的地方都要用它，
/// 不要再写 `Int(timeout)` —— 那是把一个用户可写的字段直接交给会 trap 的转换。
func timeoutText(_ v: Double) -> String {
    guard v.isFinite else { return "∞" }
    return "\(Int(min(max(v, 0), timeoutUpperBound)))"
}

/// 解析命令行上的 timeout 值。合法返回夹紧后的秒数，非法返回 nil。
///
/// 守护类子命令（daemon / nosleep-daemon / nosleep on）以前是裸 `Double(args[i+1])`，
/// 于是 `--timeout abc` 得到 nil 被当成「永久运行」、`--timeout -5` 直接进
/// Timer.scheduledTimer，两处都不报错。nil 在这些调用点与「不启用」同义，
/// 所以这里必须让调用方区分：**解析失败与显式的 0 不是一回事**。
func parseTimeoutArg(_ raw: String) -> Double? {
    guard let t = Double(raw), t.isFinite else { return nil }
    return sanitizeTimeout(t)
}

/// 电量触底时做什么（设置面板「电池」页可改，CLI `--battery-action` 对应）。
/// 0 是默认值，与老配置兼容，勿改。
enum BatteryAction: Int, CaseIterable {
    case restoreOnly = 0        // 只恢复屏幕，防睡眠继续
    case restoreAndRelease = 1  // 恢复屏幕 + 撤销防睡眠 + 退出合盖运行
    case notifyOnly = 2         // 只提醒，不自动干预

    var title: String {
        switch self {
        case .restoreOnly:       return L("恢复屏幕，继续防睡眠")
        case .restoreAndRelease: return L("恢复屏幕并撤销防睡眠（回到原本的电池行为）")
        case .notifyOnly:        return L("只提醒，不自动干预")
        }
    }
    var detail: String {
        switch self {
        case .restoreOnly:
            return L("屏幕亮起，机器继续保持不睡眠。适合还要把任务跑完的场景。")
        case .restoreAndRelease:
            return L("屏幕亮起，同时撤销防睡眠并退出合盖运行，Mac 回到系统原本的省电行为，可以正常睡眠。")
        case .notifyOnly:
            return L("只在通知中心提醒一次，不改变任何状态，由你自己决定。")
        }
    }
}

struct Config: Codable {
    var keyCode: Int64 = 11                  // B
    var modFlags: UInt64 = MOD_CTRL | MOD_ALT | MOD_CMD   // 默认 ⌃⌥⌘
    var timeout: Double = timeoutDefault         // 黑屏后自动恢复兜底，秒；0 = 不启用
                                              // 经sanitizeTimeout 夹紧，见文件上方说明
    var restoreFixed: Float? = nil           // nil = 恢复进入黑屏前的亮度
    var batteryFloor: Int = 20               // 电量下限 %，0 = 不限制
    var batteryAction: Int = 0               // 触底时做什么，见 BatteryAction；0 = 只恢复屏幕
    var hotkeyEnabled: Bool = true           // 是否注册全局热键；关掉后只能从菜单栏点击
    var autoNosleep: Bool = false            // 关屏时同时防睡眠（默认关：合盖不睡有耗电风险）
    var lidAwake: Bool = false               // 合盖不睡眠长期模式（菜单一键开关，重启自动恢复）
    var lidBlackout: Bool = true             // 合盖时熄灭内屏。
                                             // 与 lidAwake 分离：熄屏由合盖守护执行，
                                             // 关掉它则合盖只保持机器运转、内屏维持原亮度（熄屏异常时的退路）。
    var lang: String = "auto"                // 界面语言：auto=跟随系统 / zh / en / ja / ko / de / fr / es
    var keepDisplayOn: Bool = false          // 保持屏幕常亮：阻止显示器自动睡眠（caffeinate -d）
    /// 配置结构版本。旧配置没有这个字段 → 读出 0 → 由 migrate() 补齐语义。
    /// 字段语义一旦变过，老配置必须能被纠正，而不是沿用写盘时的旧含义。
    var schemaVersion: Int = 0
    var autoCheckUpdate: Bool = true         // 后台自动检查更新（节流 24h，发现新版在菜单栏提示）
    var lastUpdateCheckAt: Double = 0        // 上次自动检查的 Unix 时间戳，仅用于节流
    /// 接通电源时的运行方案（定义见 Sources/Shared/PowerPlan.swift）
    var planAC: PowerPlan = PowerPlan()
    /// 使用电池时的运行方案。与 planAC 完全独立，互不覆盖。
    var planBattery: PowerPlan = PowerPlan()

    enum CodingKeys: String, CodingKey { case keyCode, modFlags, timeout, restoreFixed, batteryFloor, batteryAction, autoNosleep, lidAwake, lidBlackout, lang, keepDisplayOn, schemaVersion, autoCheckUpdate, lastUpdateCheckAt, hotkeyEnabled, planAC, planBattery }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decodeIfPresent(Int64.self, forKey: .keyCode) ?? 11
        modFlags = try c.decodeIfPresent(UInt64.self, forKey: .modFlags) ?? (MOD_CTRL | MOD_ALT | MOD_CMD)
        // 夹紧而不是直接取：config.json 是纯文本，手写进去的 1e300 会一路带到
        // 每处 Int(timeout) 上触发 fatal error，且用户改不回来（改的那条命令自己先崩）。
        let rawTimeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? timeoutDefault
        timeout = sanitizeTimeout(rawTimeout)
        restoreFixed = try c.decodeIfPresent(Float.self, forKey: .restoreFixed)
        batteryFloor = try c.decodeIfPresent(Int.self, forKey: .batteryFloor) ?? 20
        batteryAction = try c.decodeIfPresent(Int.self, forKey: .batteryAction) ?? 0
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? true
        autoNosleep = try c.decodeIfPresent(Bool.self, forKey: .autoNosleep) ?? false
        lidAwake = try c.decodeIfPresent(Bool.self, forKey: .lidAwake) ?? false
        lidBlackout = try c.decodeIfPresent(Bool.self, forKey: .lidBlackout) ?? true
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "auto"
        keepDisplayOn = try c.decodeIfPresent(Bool.self, forKey: .keepDisplayOn) ?? false
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        autoCheckUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdate) ?? true
        lastUpdateCheckAt = try c.decodeIfPresent(Double.self, forKey: .lastUpdateCheckAt) ?? 0
        // try? 而非 try：单个字段被写成字符串/数组时 decodeIfPresent 会抛错。
        // 若让它抛出，整个 JSONDecoder().decode 就失败，loadConfig 会退回全新 Config ——
        // 用户会丢掉热键、语言、电量下限等**全部**设置。单个字段坏掉只该丢这一个字段。
        planAC = (try? c.decodeIfPresent(PowerPlan.self, forKey: .planAC)) ?? PowerPlan()
        planBattery = (try? c.decodeIfPresent(PowerPlan.self, forKey: .planBattery)) ?? PowerPlan()
    }

    /// 迁移配置。只由 loadConfig() 调用一次：init 里跑过的话，loadConfig 再跑会因版本已最新
    /// 而无从判断是否该回写。
    ///
    /// missingAC / missingBattery = 原始 JSON 里缺哪一套方案。
    /// 为 false 表示盘上**已经**有那套方案——此时绝不能用三布尔覆盖它：
    /// 那三布尔只是「当前生效值」的投影，覆盖会把用户分设的两套压成一套。
    @discardableResult
    mutating func migrate(missingAC: Bool = true, missingBattery: Bool = true) -> Bool {
        var changed = false
        if schemaVersion < 1 {
            // v0 → v1：合盖熄屏从「隐含在 lidAwake 里」拆成独立开关。
            // 之前开着合盖模式的用户，行为必须维持不变（合盖即熄屏）。
            if lidAwake { lidBlackout = true }
            schemaVersion = 1
            changed = true
        }
        if schemaVersion < 2 { schemaVersion = 2; changed = true }   // v1 → v2：引入两套电源方案
        // 补齐缺失的方案字段。两套都缺（全新配置 / 被旧版整段抹掉）：用旧的三布尔推导，
        // 升级前后行为完全一致；只缺一套（手改 / 同步工具删了一个）：复制另一套，
        // 比塞默认值更贴近「我只有一套设置」的真实意图。
        if missingAC || missingBattery {
            let legacy = PowerPlan(keepAwake: autoNosleep, displayOn: keepDisplayOn,
                                   lid: lidAwake ? .nothing : .sleep)
            if missingAC && missingBattery {
                planAC = legacy; planBattery = legacy
            } else if missingAC {
                planAC = planBattery
            } else {
                planBattery = planAC
            }
            changed = true
        }
        return changed
    }
}

// MARK: - 配置读写（两端共用的唯一一份实现）
//
// 同样必须是同一份：Bar 与 CLI 共写 config.json，两端格式化方式一旦不同，
// 文件就会在「一行压缩」与「缩进整齐」之间来回跳，diff 也失去意义。

/// 读取配置。顺带把「缺方案字段 / 方案值是脏的 / timeout 被写成非法值」自愈回盘一次 ——
/// 只在内存里兜底而不落盘，会让兜底值一直暗中生效，用户永远看不到真实配置。
func loadConfig() -> Config {
    if let d = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
       var c = try? JSONDecoder().decode(Config.self, from: d) {
        let miss = planFieldsMissing(d)
        if c.migrate(missingAC: miss.ac, missingBattery: miss.battery) { saveConfig(c) }   // 迁移结果落盘
        else if planFieldsNeedRepair(d) { saveConfig(c) }                                   // 脏值落盘修复
        else if timeoutNeedRepair(d) { saveConfig(c) }                                      // 非法 timeout 落盘修复
        return c
    }
    var c = Config(); c.schemaVersion = configSchemaVersion
    return c
}

/// 盘上的 timeout 是否非法（NaN / inf / 负数 / 超过上界）。
/// 与 sanitizeTimeout 配对：解码层已经把它夹回合法值，但要真正清掉脏数据还得再读一遍原始 JSON。
func timeoutNeedRepair(_ d: Data) -> Bool {
    guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
          let raw = o["timeout"] else { return false }
    guard let n = raw as? NSNumber else { return true }      // 字符串/数组/NSNull 都算坏
    return sanitizeTimeout(n.doubleValue) != n.doubleValue
}

/// 原子写：先写同目录临时文件再 rename。
/// 菜单栏 App 与 CLI 守护写同一个 config.json，直接覆盖可能在崩溃瞬间留下半截 JSON，
/// 下次读出空配置（热键回默认、模式全关）—— 这类故障极难复现，必须一开始就排除。
///
/// **写入纪律（踩过坑，务必遵守）**：`Config` 是整份覆盖写，App 与 CLI 又在共写同一个文件，
/// 所以**「读」与「写」之间不得夹耗时动作**。曾经的写法是「先 loadConfig() → 拉起/停止守护
/// （要 spawn 进程，约 1 秒）→ 把开头那份快照 saveConfig 回去」，结果那一秒里 CLI 改过的方案
/// 被旧快照整份抹掉：用户刚用 `lidkeep plan` 改完，一秒后自己变回去，且毫无提示。
/// 需要先做耗时动作的，用 `updateConfig` 在**动作之后**重新读改写。
func saveConfig(_ c: Config) {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let d = try? enc.encode(c) else { return }
    let tmp = configFile + ".tmp.\(getpid())"
    do {
        try d.write(to: URL(fileURLWithPath: tmp))
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tmp)
        if rename(tmp, configFile) != 0 { try? fm.removeItem(atPath: tmp) }
    } catch {
        try? fm.removeItem(atPath: tmp)
    }
}

/// 清理遗留的 `config.json.tmp.<pid>`。
///
/// 临时文件按 pid 命名是为了避免两个进程写同一个 tmp 互相踩，但代价是**每次异常退出
/// （SIGKILL、崩溃、掉电）都会留下一个孤儿**。实测本机积累 31 个，最早的来自 2026-09-21。
/// 它们不影响读取，但会一直堆积，且用户会在「配置目录里一堆看不懂的文件」时怀疑数据有问题。
///
/// 只删 tmp 前缀的，不碰 config.json 本身；调用方在启动时跑一次即可（扫目录成本可忽略）。
func cleanConfigTempFiles() {
    let dir = (configFile as NSString).deletingLastPathComponent
    guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
    let prefix = (configFile as NSString).lastPathComponent + ".tmp."
    for name in names where name.hasPrefix(prefix) {
        try? fm.removeItem(atPath: dir + "/" + name)
    }
}

/// 立刻重读 → 改 → 写。用于「必须先做耗时动作（spawn 进程、发网络请求）再落盘」的场合：
/// 把读取压到写之前的一瞬间，另一端在此期间做的改动就不会被旧快照抹掉。
/// 需要旧值做判断的，先取出来放在闭包外的局部变量里。
func updateConfig(_ mutate: (inout Config) -> Void) {
    var c = loadConfig()
    mutate(&c)
    saveConfig(c)
}
