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
    var timeout: Double = 43200              // 黑屏后自动恢复兜底，秒；0 = 不启用
    var restoreFixed: Float? = nil           // nil = 恢复进入黑屏前的亮度
    var batteryFloor: Int = 20               // 电量下限 %，0 = 不限制
    var batteryAction: Int = 0               // 触底时做什么，见 BatteryAction；0 = 只恢复屏幕
    var hotkeyEnabled: Bool = true           // 是否注册全局热键；关掉后只能从菜单栏点击
    var autoNosleep: Bool = false            // 关屏时同时防睡眠（默认关：合盖不睡有耗电风险）
    var lidAwake: Bool = false               // 合盖不睡眠长期模式（菜单一键开关，重启自动恢复）
    var lidBlackout: Bool = true             // 合盖时熄灭内屏。
                                             // 与 lidAwake 分离：熄屏由合盖守护执行，
                                             // 关掉它则合盖只保持机器运转、内屏维持原亮度（熄屏异常时的退路）。
    var lang: String = "auto"                // 界面语言：auto=跟随系统 / zh / en
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
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 43200
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

/// 读取配置。顺带把「缺方案字段 / 方案值是脏的」自愈回盘一次 ——
/// 只在内存里兜底而不落盘，会让兜底值一直暗中生效，用户永远看不到真实配置。
func loadConfig() -> Config {
    if let d = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
       var c = try? JSONDecoder().decode(Config.self, from: d) {
        let miss = planFieldsMissing(d)
        if c.migrate(missingAC: miss.ac, missingBattery: miss.battery) { saveConfig(c) }   // 迁移结果落盘
        else if planFieldsNeedRepair(d) { saveConfig(c) }                                   // 脏值落盘修复
        return c
    }
    var c = Config(); c.schemaVersion = configSchemaVersion
    return c
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

/// 立刻重读 → 改 → 写。用于「必须先做耗时动作（spawn 进程、发网络请求）再落盘」的场合：
/// 把读取压到写之前的一瞬间，另一端在此期间做的改动就不会被旧快照抹掉。
/// 需要旧值做判断的，先取出来放在闭包外的局部变量里。
func updateConfig(_ mutate: (inout Config) -> Void) {
    var c = loadConfig()
    mutate(&c)
    saveConfig(c)
}
