import Foundation

// MARK: - 电源方案（接通电源 / 使用电池 两套，互不干扰）
//
// CLI 与菜单栏 App 共用这一份定义：两侧共写同一个 config.json，
// 模型若各写一份，迟早会漂移出「一端认得字段、另一端把它抹掉」的故障。
//
// 借鉴 Windows「电源选项」：拔插电源是两种截然不同的使用场景，
// 接电时愿意让机器一直跑，用电池时希望它老实睡觉。因此两套方案各自独立保存，
// 由当前电源来源决定哪一套生效（见 Bar 侧的 activePlan / syncPlanToActive）。
//
// 三个开关互不排斥：
//   - 息屏后保持唤醒：关屏/息屏期间阻止**系统**睡眠（屏幕照常熄灭）
//   - 保持屏幕常亮：阻止**显示器**自动睡眠（屏幕不熄）
//   - 合盖时：睡眠（系统默认）/ 保持唤醒（合盖继续运行）
// 前两项完全可以同时开——一个是系统、一个是显示器；合盖行为独立于前两者。

/// 合盖时的行为。对应 Windows「关闭盖子时」的两个选项。
enum LidAction: String, Codable, CaseIterable {
    case sleep      // 交回系统：按系统设置睡眠
    case nothing    // 保持唤醒：由本工具接管，合盖继续运行

    var title: String {
        switch self {
        case .sleep:   return L("睡眠")
        case .nothing: return L("保持唤醒")
        }
    }
    var cost: String {
        switch self {
        case .sleep:   return L("合盖后按系统设置正常睡眠")
        case .nothing: return L("合盖也持续运行，内屏熄灭，建议接电源")
        }
    }
}

/// 单一电源来源下的运行方案
struct PowerPlan: Codable {
    var keepAwake: Bool = false          // 息屏后保持唤醒（关屏期间阻止系统睡眠）
    var displayOn: Bool = false          // 保持屏幕常亮（阻止显示器自动睡眠）
    var lid: LidAction = .sleep          // 合盖时做什么

    /// 逐字段容错解析：任何一个字段缺失或损坏都退回默认值，
    /// 绝不让整个 config.json 解析失败（那样会连带热键、电量下限一起被重置）。
    init(keepAwake: Bool = false, displayOn: Bool = false, lid: LidAction = .sleep) {
        self.keepAwake = keepAwake; self.displayOn = displayOn; self.lid = lid
    }
    enum PlanKeys: String, CodingKey { case keepAwake, displayOn, lid }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PlanKeys.self)
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
        displayOn = try c.decodeIfPresent(Bool.self, forKey: .displayOn) ?? false
        // rawValue 非法时退回 .sleep，而不是抛错带崩整份配置
        lid = LidAction(rawValue: (try c.decodeIfPresent(String.self, forKey: .lid)) ?? "") ?? .sleep
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PlanKeys.self)
        try c.encode(keepAwake, forKey: .keepAwake)
        try c.encode(displayOn, forKey: .displayOn)
        try c.encode(lid.rawValue, forKey: .lid)
    }
    /// 摘要，用于菜单标题、设置面板回显与 CLI `plan`。**刻意只用短词**。
    ///
    /// 菜单栏下拉与面板摘要行都是单行宽度，长措辞（「息屏保持唤醒 + 屏幕常亮 + 合盖不睡」）
    /// 在三项全开时会顶到边缘被截断 —— 用户看到的是一行读不完的残句，等于什么也没说。
    /// 每一项的完整说明在各开关自己的标签里（「息屏后保持唤醒」/「保持屏幕常亮」/「合盖时」），
    /// 摘要只负责「一眼看清开了哪几项」。
    var summary: String {
        var parts: [String] = []
        if keepAwake { parts.append(L("保持唤醒")) }
        if displayOn { parts.append(L("屏幕常亮")) }
        if lid == .nothing { parts.append(L("合盖不睡")) }
        return parts.isEmpty ? L("不干预") : parts.joined(separator: L("、"))
    }
}

// MARK: - 配置自愈（Bar 与 CLI 共用）
//
// config.json 是纯文本，谁都能改：手改、旧版回写、第三方同步工具都可能留下脏数据。
// 解码层已经用「逐字段兜底」保证读不崩，但兜底只在内存里生效——
// 脏值会一直躺在盘上，每次启动都重新兜一次。下面两个函数在**原始 JSON**上判断，
// 让 loadConfig 有机会把修好的值真正落盘。

/// 顶层是否缺少方案字段（逐套判断）。旧版 App 不认这两个键，回写时会整段抹掉；
/// 用户手改或同步工具也可能只删掉其中一个——所以必须分别判断，
/// 否则「补缺失的那套」会把另一套用户精心设置的方案一起覆盖掉。
func planFieldsMissing(_ d: Data) -> (ac: Bool, battery: Bool) {
    guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return (false, false) }
    return (o["planAC"] == nil, o["planBattery"] == nil)
}

/// 单个方案字段的取值是否非法（类型不对 / lid 不是合法枚举值）。缺失返回 false——那属于「缺失」而非「损坏」。
func planValueInvalid(_ v: Any?) -> Bool {
    guard let v else { return false }
    guard let dict = v as? [String: Any] else { return true }        // 字符串、数组、NSNull 都算坏
    if let lid = dict["lid"] {
        guard let s = lid as? String, LidAction(rawValue: s) != nil else { return true }
    }
    for k in ["keepAwake", "displayOn"] {
        if let b = dict[k], !(b is Bool) { return true }
    }
    return false
}

/// 方案字段存在但内容非法 → 需要重新落盘修复
func planFieldsNeedRepair(_ d: Data) -> Bool {
    guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return false }
    return planValueInvalid(o["planAC"]) || planValueInvalid(o["planBattery"])
}
