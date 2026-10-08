// 通知闸门：决定一条用户通知「现在该不该弹」。
//
// 为什么需要它：本工具的失败大多是**持续状态**而不是**瞬时事件**。
// 「提权助手授权失效」会一直失效，周期巡检每 15 秒撞一次；「电量低于下限」
// 会一直低到插上电源为止。没有闸门时，同一个原因按每轮一条的频率灌进通知中心，
// 用户看到的是几十条内容相同的通知 —— 他会认为「这软件老在弹通知」，
// 而实际上它们说的是同一件事。
//
// 闸门按**语义 key** 记忆（不是消息原文：原文常含电量、时间这类变量），
// 同一 key 在窗口期内只放行一次。用户把问题解决掉之后调 notifyGateReset 开闸，
// 否则下一次真的复发时反而不会提醒。

import Foundation

/// 后台拉起时置为 true。
///
/// App spawn CLI 时带上 `LIDKEEP_QUIET=1`，被拉起的子进程于是全程不弹通知：
/// 后台动作的对错由拉起方统一呈现，子进程再弹一条只会与拉起方重复一条。
/// 这条通道是必需的 —— 闸门是**进程内**状态，而 App 每次 spawn 的都是新进程，
/// 靠闸门本身拦不住「每拉一次弹一条」。
let quietMode: Bool = ProcessInfo.processInfo.environment["LIDKEEP_QUIET"] != nil

/// 同一 key 的默认静默窗口。
///
/// 取 24 小时而不是「每次状态变化」：这类通知要传达的是「有个问题需要你处理」，
/// 提醒一次就够；反复提醒不会让人更快去处理，只会让人关掉通知权限。
let notifyWindow: TimeInterval = 24 * 3600

private var notifyShownAt: [String: Date] = [:]

/// 闸门是否放行（true = 该弹）。放行时记下本次时间。
///
/// 调用方传 key 的语义应当稳定：同一种问题用同一个 key，不同问题用不同 key。
func notifyGateOpen(_ key: String, window: TimeInterval = notifyWindow) -> Bool {
    if quietMode { return false }
    if let t = notifyShownAt[key], Date().timeIntervalSince(t) < window { return false }
    notifyShownAt[key] = Date()
    return true
}

/// 开闸。条件真实变化后调用 —— 用户装好了提权助手、插上了电源、关掉了过热来源。
/// key 传 nil 表示全部开闸（例如配置被外部改动，一切判断都要重来）。
func notifyGateReset(_ key: String? = nil) {
    if let k = key { notifyShownAt.removeValue(forKey: k) } else { notifyShownAt.removeAll() }
}
