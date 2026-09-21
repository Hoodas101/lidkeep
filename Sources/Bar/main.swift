// LidKeep —— lidkeep 的菜单栏控制器 + 可视化设置
//
// 与 CLI 的协作方式:
//   - 共用 ~/Library/Application Support/LidKeep/ 下的 config.json 与状态文件
//   - 本 App 接管 service.pid，因此 `lidkeep off / on / status`
//     会自动识别为常驻服务，通过 SIGUSR1 / SIGUSR2 控制本进程，两边状态永远一致
//   - 本 App 可直接由 launchd 拉起实现开机自启（不依赖 CLI 的 service install）
import Foundation
import Cocoa
import CoreGraphics
import Carbon.HIToolbox
import Darwin

// MARK: - 路径（与 CLI 完全一致）

/// 登录项 plist 路径。**是否真的生效以 launchd 的注册状态为准**：
/// 文件在而没 bootstrap 时，开机并不会启动（见 isLoginItemEnabled）。
let barPlist = home + "/Library/LaunchAgents/com.lidkeep.bar.plist"

/// CLI 二进制路径：合盖模式以独立的 CLI 守护进程持有 disablesleep，
/// 从而在持有者账本里与黑屏联动（App 自身 pid）互不干扰。
let cliCandidates = ["/opt/homebrew/bin/lidkeep", "/usr/local/bin/lidkeep"]
let cliPath: String = cliCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) ?? cliCandidates[0]

/// 以 launchd 实际注册状态为准：plist 文件存在但没 bootstrap 时，开机并不会启动
func isLoginItemEnabled() -> Bool {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    t.arguments = ["print", "gui/\(getuid())/\(barLabel)"]
    t.standardOutput = FileHandle.nullDevice
    t.standardError = FileHandle.nullDevice
    t.standardInput = FileHandle.nullDevice
    do { try t.run() } catch { return false }
    t.waitUntilExit()
    return t.terminationStatus == 0
}
let barLabel = "com.lidkeep.bar"

/// 登录项 plist。KeepAlive 用 SuccessfulExit=false：只有崩溃 / 被强杀才重启，
/// 正常退出（菜单「退出」、SIGTERM）不再拉起。
/// 原因：无条件 KeepAlive 会与 App 内部的单实例接管互相残杀 —— launchd 不停
/// 拉起新实例，新实例又杀掉旧实例，进程陷入重启竞赛，热键注册随进程不断消亡。
func loginItemPlist() -> String {
    let bundle = Bundle.main.bundlePath
    let exe = bundle.hasSuffix(".app")
        ? bundle + "/Contents/MacOS/LidKeep"
        : "/Applications/LidKeep.app/Contents/MacOS/LidKeep"
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>\(barLabel)</string>
        <key>ProgramArguments</key><array><string>\(exe)</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    </dict>
    </plist>
    """
}
try? fm.createDirectory(atPath: base, withIntermediateDirectories: true)

func blog(_ s: String) {
    if let a = try? fm.attributesOfItem(atPath: logPath),
       let size = a[.size] as? UInt64, size > 262_144 {
        try? fm.removeItem(atPath: logPath + ".old")
        try? fm.moveItem(atPath: logPath, toPath: logPath + ".old")
    }
    let line = "\(Date()) \(s)\n"
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { fm.createFile(atPath: logPath, contents: line.data(using: .utf8)) }
}

// MARK: - 配置（结构与版本号见 Sources/Shared/Config.swift，两端同一份）

// MARK: - 电源方案：真值是两套 PowerPlan，三布尔只是「当前生效值」的投影
//
// 接电与用电池是两种场景，各自保存一套方案（planAC / planBattery），
// 由当前电源来源决定哪一套生效。底层仍保留 autoNosleep / keepDisplayOn / lidAwake
// 三个布尔——它们表示「此刻实际生效什么」，每次由方案推导（syncPlanToActive），
// 不做单独持久化，因此不存在两份真值漂移；CLI 侧也仍照旧读这三个布尔。

/// 当前是否由电池供电（测试钩子 LK_SIMULATE_BATTERY 见 batteryStatus）
///
/// 1 秒短缓存：`activePlan` 与 `refreshUI` 都要问「现在是不是电池」，而每次提问都会
/// spawn 一个 `pmset -g batt` 进程 —— 打开一次菜单因此创建约 3 个进程，
/// 对一个以省电为卖点的常驻工具来说，这笔开销本不该有。同一次 UI 刷新里的重复提问
/// 间隔只有微秒，缓存 1 秒足以把它们合并掉。
///
/// 刻意**不做更长**：`_sim-battery` 文件钩子会在运行中被测试改写（拔插电源的端到端用例），
/// 读旧值会让那些用例得到与事实相反的结论；而真实的拔插电源是人工动作，
/// 电源轮询本身就是 15 秒一次，1 秒的滞后无感。
private var cachedOnBattery: (value: Bool, at: Date)?
func onBatteryNow() -> Bool {
    if let c = cachedOnBattery, Date().timeIntervalSince(c.at) < 1.0 { return c.value }
    let v = batteryStatus().onBattery
    cachedOnBattery = (v, Date())
    return v
}

/// 电源来源的名字，用于菜单与日志
func powerSourceTitle(battery: Bool) -> String { battery ? L("使用电池") : L("接通电源") }

/// 当前应当生效的那套方案
func activePlan(_ c: Config) -> PowerPlan { onBatteryNow() ? c.planBattery : c.planAC }

/// 菜单里那一行状态摘要，例：`状态：电源保持唤醒` / `状态：电池不干预`。
///
/// 电源来源在这里压成两个字（电源 / 电池）——完整叫法（接通电源 / 使用电池）留给
/// 设置面板与通知；菜单栏那一行要的是一眼扫完，不是把「接通电源方案」这类字全堆上去。
/// buildMenu 的初始标题与 refreshUI 都走这里，两处各写一遍必然有一次会漂移。
func planStatusTitle(_ plan: PowerPlan, battery: Bool) -> String {
    // 连写规则中英不同：中文「状态：电源保持唤醒」可以直连，
    // 英文直连会连成 "Status: PowerKeep awake"，必须留分隔。
    let sep = L10n.isEN ? " · " : ""
    return L("状态：") + (battery ? L("电池") : L("电源")) + sep + plan.summary
}

/// 把方案投影到三布尔（纯计算，不落盘、不产生副作用）
func projected(_ c: inout Config, from p: PowerPlan) {
    c.autoNosleep   = p.keepAwake
    c.keepDisplayOn = p.displayOn
    c.lidAwake      = (p.lid == .nothing)
}

/// 启动时按当前电源来源对齐生效值。
/// 上次退出时接着电源、这次开机用电池，三布尔还停在上一次的方案上——
/// 不同步就会出现「配置写着一套、机器按另一套跑」。
@discardableResult
func syncPlanToActive() -> Config {
    var c = loadConfig()
    let p = activePlan(c)
    let before = (c.autoNosleep, c.keepDisplayOn, c.lidAwake)
    projected(&c, from: p)
    if before != (c.autoNosleep, c.keepDisplayOn, c.lidAwake) {
        blog("bar: 按「\(powerSourceTitle(battery: onBatteryNow()))」方案对齐生效值"
             + "（息屏保持唤醒=\(p.keepAwake) 屏幕常亮=\(p.displayOn) 合盖=\(p.lid.rawValue)）")
        saveConfig(c)
    }
    return c
}

/// 保存两套方案，并让生效值与「当前电源来源对应的那套」对齐。菜单与设置面板共用这一处。
/// 改的不是当前生效的那套时，只落盘不改动运行状态——否则会在接电时误关掉电池的守护。
/// 返回 false = 前置条件不满足（缺提权助手 / 电量低于下限），此时方案**仍然落盘**，
/// 但合盖那一项按失败处理并告知用户，避免 UI 显示已开启而实际没开。
@discardableResult
func commitPlans(_ plans: (ac: PowerPlan, battery: PowerPlan)) -> Bool {
    let ctl = ScreenController.shared
    var c = loadConfig()
    c.planAC = plans.ac
    c.planBattery = plans.battery
    let p = activePlan(c)
    projected(&c, from: p)
    let wasOurs = ctl.cfg.lidAwake      // 必须在 ctl.cfg = c 之前取：投影会把标志改成 false
    saveConfig(c)
    ctl.cfg = c                  // 先落盘并让归属判断看到新方案，再动合盖守护
    ctl.syncKeepDisplayOn()
    ctl.syncKeepAwake()
    let lidOK = ctl.reconcileLidDaemon(want: p.lid == .nothing, why: "切换电源方案",
                                       wasOurs: wasOurs, force: true)
    // 开不起来**不**回滚方案：方案是用户的意图，电量低/助手未装都是临时状态，
    // 抹掉它等于让用户每次插电、每次装完助手都要重新设一遍。
    // 改为让 UI 说真话——菜单与面板会标注「未生效」，巡检在条件满足后自动补起。
    // 切走「息屏后保持唤醒」时，正由它拉起的黑屏防睡眠一并解除
    if !c.autoNosleep && ctl.nosleepOn && ctl.nosleepAuto { ctl.stopNosleep(L("切换运行方案")) }
    return lidOK
}

/// 电源来源变化时的自动切换。返回是否真的切换了来源。
/// 轮询而非 IOKit 通知：拔插电源本就是低频事件，15 秒的延迟无感，
/// 换来的是不依赖 IOKit 的 PowerSources 私有通知链路，更稳。
@discardableResult
func switchPlanIfPowerSourceChanged() -> Bool {
    let isBattery = onBatteryNow()
    if isBattery == lastPowerSourceWasBattery { return false }
    lastPowerSourceWasBattery = isBattery
    blog("bar: 电源来源切换为\(isBattery ? "电池" : "电源适配器")，按对应方案重新生效")
    var c = loadConfig()
    let p = activePlan(c)
    projected(&c, from: p)
    let ctl = ScreenController.shared
    let wasOurs = ctl.cfg.lidAwake      // 取值须在 ctl.cfg 被覆盖之前，见 reconcileLidDaemon 注释
    saveConfig(c)
    ctl.cfg = c
    ctl.syncKeepDisplayOn()
    ctl.syncKeepAwake()
    // 失败不回滚方案：拔电源后电量低于下限属临时状态，退回「睡眠」会丢掉用户设置。
    // 周期巡检会在电量回升、助手就绪后自动补起守护。
    let lidOK = ctl.reconcileLidDaemon(want: p.lid == .nothing, why: "电源来源切换", wasOurs: wasOurs)
    if !p.keepAwake && ctl.nosleepOn && ctl.nosleepAuto { ctl.stopNosleep(L("切换电源方案")) }
    var msg = L("电源方案：") + powerSourceTitle(battery: isBattery) + L(" —— ") + p.summary
    if p.lid == .nothing && !lidOK { msg += L("（合盖不睡未生效，将在条件满足后自动重试）") }
    notifyUser(msg)
    return true
}
var lastPowerSourceWasBattery: Bool? = nil

// loadConfig() / saveConfig() / updateConfig() 见 Sources/Shared/Config.swift

// MARK: - 键位表（table 与 keyName / modsText 见 Sources/Shared/SystemState.swift）
func hotkeyText(_ c: Config) -> String { modsText(c.modFlags) + keyName(c.keyCode) }

// MARK: - 全局热键：Carbon（实现见 Sources/Shared/SystemState.swift）

// MARK: - 用户通知（osascript，免授权）
func notifyUser(_ msg: String) {
    let safe = msg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \"\(safe)\" with title \"LidKeep\""]
    try? p.run()
}

var gotTerminate = false
// SIGTERM/SIGINT 由传统 handler 置位，再由 Timer 在主线程安全收尾

// MARK: - 屏幕控制器（与 CLI 常驻服务同一套语义）
final class ScreenController {
    static let shared = ScreenController()

    var cfg = loadConfig()
    var blacked = false
    var saved: Float = 0.5
    var caff: Process?
    // 一律用 AppKit 原生 Timer：AppKit run loop 对 GCD main queue 的 timer / signal
    // source 交付不可靠（实测延迟数秒且乱序），NSTimer 挂 .common 模式则稳定
    var pinTimer: Timer?
    var timeoutTimer: Timer?
    var battTimer: Timer?
    var powerTimer: Timer?       // 电源来源轮询（拔插电源 → 切换方案）
    /// 合盖守护拉起失败后的退避时间与通知节流。
    /// 失败原因分两类：缺提权助手（能力缺失，不会自愈 → 长退避）与电量低于下限
    /// （随时会变 → 短退避，且一旦恢复就地清除，别让用户插上电还干等）。
    var lidRetryAfter: Date? = nil
    var lidRetryBlocker: String? = nil
    var lidNotifyAt: Date? = nil
    /// 同一轮低电量只提醒一次。30 秒一轮的检查会把通知中心刷满。
    private var battNotified = false
    var cmdTimer: Timer?
    var signalSources: [DispatchSourceSignal] = []
    var configMtime: Date? = nil
    var selfTesting = false
    var onStateChange: (() -> Void)?
    /// config.json 被外部（CLI / 手动编辑）改动并已重载时回调。
    /// 用途：让已打开的设置面板刷新自己的编辑副本——面板里留着旧值的话，
    /// 用户下一次在面板里改动任何一项，提交时就会把外部改动整片盖掉。
    var onConfigReloaded: (() -> Void)?
    var restoreRetry: Timer?      // 亮度恢复失败后的持续重试（屏幕不能就此黑着）

    // MARK: 防睡眠
    //
    // 与关屏是两件事：关屏只让背光熄灭，防睡眠是阻止系统进入睡眠。
    // caffeinate -s 的断言仅 AC 有效（man page 明写），所以电池与合盖场景
    // 必须靠 pmset disablesleep（需 root、默认不安装）。
    var nosleepCaff: Process?
    var nosleepSystemOn = false
    var nosleepOn = false
    var nosleepAuto = false            // 由「关屏联动」开启时为 true，恢复显示时随之关闭

    // MARK: 合盖不睡眠（长期模式）
    //
    // 委托一个独立的 CLI 系统级守护（nosleep-daemon --system）持有 disablesleep：
    // 独立 pid = 持有者账本里的独立条目，与黑屏联动的 App 侧防睡眠互不干扰；
    // App 退出 / 重启都不影响它，重启电脑后由本函数按持久标志自动恢复。
    func lidDaemonPid() -> Int32? {
        guard let s = try? String(contentsOfFile: nosleepPidFile, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else { return nil }
        return pid
    }

    /// 守护写入的状态行：level|since|systemOn。用于确认合盖守护真的到达系统级。
    func nosleepInfoStatus() -> (level: String, systemOn: Bool)? {
        guard lidDaemonPid() != nil,
              let s = try? String(contentsOfFile: base + "/nosleep.state", encoding: .utf8) else { return nil }
        let p = s.split(separator: "|").map(String.init)
        return (level: p.count > 0 ? p[0] : "caffeinate",
                systemOn: p.count > 2 ? p[2] == "1" : false)
    }

    var lidOn: Bool { cfg.lidAwake && lidDaemonPid() != nil }

    /// 开启 / 停止合盖守护，并把标志写回配置。
    ///
    /// 注意落盘方式：中途要 spawn CLI 进程（约 1 秒），所以**不能**在开头 loadConfig()
    /// 再在末尾把那份快照写回去——这一秒里 CLI 对方案的改动会被整份抹掉（真踩过）。
    /// 判断所需的值（电量下限等）在开头读一次即可，落盘统一走 updateConfig 在动作后重读。
    @discardableResult
    func setLidAwake(_ on: Bool) -> Bool {
        let snapshot = loadConfig()
        guard let cli = fm.isExecutableFile(atPath: cliPath) ? cliPath : nil else {
            blog("bar: 合盖模式需要命令行工具")
            return false
        }
        if on {
            guard helperInstalled() else {
                blog("bar: 合盖模式需要提权助手（覆盖合盖睡眠必须 root）")
                return false
            }
            if batteryBlocksStart(snapshot) {
                blog("bar: 电量 \(batteryStatus().percent)% 低于下限，暂不能开启合盖模式")
                return false
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = ["nosleep", "on", "--system"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch { blog("bar: 启动合盖守护失败 \(error)"); return false }
            guard lidDaemonPid() != nil else {
                blog("bar: 合盖守护启动未确认，详见 CLI 日志")
                return false
            }
            // 必须确认到达系统级：降级成进程级时合盖照样睡，用户会带着错误预期合盖
            if let info = nosleepInfoStatus(), info.level != "system" {
                blog("bar: 合盖守护降级为进程级（helper 调用失败），回滚")
                let q = Process()
                q.executableURL = URL(fileURLWithPath: cli)
                q.arguments = ["nosleep", "off"]
                q.standardOutput = FileHandle.nullDevice; q.standardError = FileHandle.nullDevice
                q.standardInput = FileHandle.nullDevice
                try? q.run(); q.waitUntilExit()
                return false
            }
            // 到这里进程动作已结束，才重读并只改自己这一个字段
            updateConfig { $0.lidAwake = true }
            cfg = loadConfig()
            blog("bar: 合盖不睡眠已开启 pid=\(lidDaemonPid() ?? 0)")
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = ["nosleep", "off"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch { blog("bar: 停止合盖守护失败 \(error)") }
            updateConfig { $0.lidAwake = false }
            cfg = loadConfig()
            blog("bar: 合盖不睡眠已关闭")
        }
        onStateChange?()
        return true
    }

    /// 让「合盖守护」与当前方案对齐，并区分守护的归属。
    ///
    /// 判断守护在不在，看的是 pid 文件**而不是** `cfg.lidAwake`：后者只是配置里的标志，
    /// 与守护真实状态随时可能分叉（守护被外部杀掉、CLI 单独改了配置）。
    /// 用标志做开关条件会漏掉「该关却没关」——守护还在跑，却因标志已是 false 而跳过关闭动作。
    ///
    /// 归属判定：调用方通过 `wasOurs` 传入「变更**之前**守护是否属于本工具」。
    /// 这个值必须在投影/落盘之前取——投影会把 `cfg.lidAwake` 一起改掉，
    /// 之后再读就永远是 false，于是「按方案该关的守护」一个也关不掉（实测踩过）。
    /// 用户手动 `lidkeep nosleep on --system` 起的守护，其 wasOurs 为 false，不该被方案切换误杀。
    ///
    /// `force = true` 用于用户主动操作：绕过拉起失败的退避窗口。
    /// 否则用户刚装好提权助手、点菜单要开合盖不睡，却因为几十秒前自动重试失败仍在退避期里
    /// 而毫无反应——点了没反应比报错更让人困惑。
    @discardableResult
    func reconcileLidDaemon(want: Bool, why: String, wasOurs: Bool = true, force: Bool = false) -> Bool {
        let running = lidDaemonPid() != nil
        if want {
            if running { return true }
            if let t = lidRetryAfter, Date() < t, !force { return false }   // 退避中，不反复重试
            let ok = setLidAwake(true)
            if ok {
                lidRetryAfter = nil
                lidRetryBlocker = nil
            } else {
                // 两种失败原因的重试节奏不同：缺助手要等用户去装，电量低插上电就好了。
                // 用同一个退避值的话，要么白等一分钟，要么每 15 秒重试一次把日志刷满。
                let blocker = helperInstalled() ? "battery" : "helper"
                lidRetryBlocker = blocker
                lidRetryAfter = Date().addingTimeInterval(blocker == "helper" ? 600 : 60)
                // 电量低是用户自己就知道的状态，弹通知只会添乱；缺助手才需要主动告知
                if blocker == "helper",
                   lidNotifyAt == nil || Date().timeIntervalSince(lidNotifyAt!) > 1800 {
                    lidNotifyAt = Date()
                    notifyUser(L("「合盖不睡」未能生效：需要提权助手，且电量需高于下限。详见「打开日志」。"))
                }
                blog("bar: 合盖守护拉起失败（\(why)，原因=\(blocker)），\(blocker == "helper" ? "10 分钟" : "1 分钟")内不再重试")
            }
            return ok
        }
        guard running else { return true }
        guard wasOurs else {
            blog("bar: 合盖守护在跑但非本工具按方案开启（\(why)），保持不动")
            return true
        }
        blog("bar: 当前方案不要求合盖运行（\(why)），停止守护")
        return setLidAwake(false)
    }

    /// 合盖运行无法生效（缺提权助手 / 电量低于下限）时，把当前电源那套方案的合盖项退回「睡眠」。
    /// 不退的话，方案里写着 nothing、菜单与面板都显示「合盖不睡」，而守护根本没在跑——
    /// 用户带着「合盖也不会睡」的预期把机器塞进包里，正是最贵的那种错觉。
    /// 电量触底「彻底放手」时，把当前电源来源那一套方案退回系统默认行为：
    /// 合盖睡眠 + 不再要求息屏保持唤醒 + 不再保持屏幕常亮。另一套保持不动——
    /// 用户可能只在接电时才需要它。
    ///
    /// 为什么必须连 keepAwake 一起清掉：只停断言的话，方案里仍写着「息屏后保持唤醒」，
    /// 下一次周期对齐（配置重载 / 电源切换）会立刻把断言装回去，
    /// 「电量触底彻底放手」等于没做，机器照样在包里耗到关机。
    /// displayOn 同理：它是四条耗电路径里最费电的一条，留着就等于没放手。
    func rollbackPlanToSystemDefaults(reason: String) {
        var c = loadConfig()
        if onBatteryNow() {
            guard c.planBattery.lid != .sleep || c.planBattery.keepAwake || c.planBattery.displayOn
            else { return }
            c.planBattery.lid = .sleep
            c.planBattery.keepAwake = false
            c.planBattery.displayOn = false
        } else {
            guard c.planAC.lid != .sleep || c.planAC.keepAwake || c.planAC.displayOn
            else { return }
            c.planAC.lid = .sleep
            c.planAC.keepAwake = false
            c.planAC.displayOn = false
        }
        projected(&c, from: activePlan(c))
        saveConfig(c)
        cfg = c
        blog("bar: 电量保护触发（\(reason)），当前方案已退回「合盖睡眠 + 不强制唤醒 + 不保持常亮」")
    }

    /// 「保持屏幕常亮」单独放手：停断言 **并且** 清掉当前电源方案里的 displayOn。
    ///
    /// 为什么不能只靠 rollbackPlanToSystemDefaults：那条路径同时清掉合盖与息屏保持唤醒，
    /// 而触底动作选「只恢复屏幕」的用户恰恰是想**保留**防睡眠、只把屏幕常亮放开。
    /// 两种意图不同，必须分开走。
    ///
    /// 为什么必须连方案一起清：只停断言的话，方案里仍写着 displayOn=true，
    /// 下一次周期对齐（配置重载 / 电源切换 / 巡检）会立刻把断言装回去，
    /// 「电量触底放手」等于没做 —— 屏幕照样整夜亮着放电到关机。
    /// 只动「当前电源来源」那套：用户可能只在接电时才需要常亮。
    func releaseKeepDisplayOn(reason: String) {
        var c = loadConfig()
        if onBatteryNow() {
            guard c.planBattery.displayOn else { return }
            c.planBattery.displayOn = false
        } else {
            guard c.planAC.displayOn else { return }
            c.planAC.displayOn = false
        }
        projected(&c, from: activePlan(c))
        saveConfig(c)
        cfg = c
        blog("bar: 电量保护触发（\(reason)），已关闭「保持屏幕常亮」")
        syncKeepDisplayOn()
    }

    /// 黑屏期间持有 caffeinate，阻止空闲/显示器睡眠（-w 保证退出即回收）
    private func startCaff() {
        guard caff == nil else { return }
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        c.arguments = ["-di", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        try? c.run()
        caff = c
    }

    @discardableResult
    func startNosleep(auto: Bool = false) -> Bool {
        guard !nosleepOn else { return true }
        // 电量下限对防睡眠同样强制生效：合盖 + 电池 + 不睡是最容易耗尽电量的组合，
        // 机器在包里一直跑到没电，用户却毫不知情。
        if batteryBlocksStart(cfg) {
            let b = batteryStatus()
            return reject((L("电量 ") + "\(b.percent)" + L("% 低于下限 ") + "\(cfg.batteryFloor)" + L("%，已取消开启防睡眠（避免耗尽电池）")))
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        c.arguments = ["-dis", "-w", String(pid)]
        try? c.run()
        nosleepCaff = c
        nosleepOn = true
        // -dis 已覆盖 -d -i，不必再单独持有黑屏用的 caffeinate；
        // 同理「息屏后保持唤醒」的 -is 也被覆盖，留着就是两条重复断言
        caff?.terminate(); caff = nil
        stopKeepAwakeAssertion()

        if helperInstalled(), let r = helperExec("on"), r == "on", systemSleepDisabled() {
            nosleepSystemOn = true
            blog("bar: 防睡眠开启（系统级，覆盖电池与合盖）")
        } else {
            nosleepSystemOn = false
            blog("bar: 防睡眠开启（进程级，仅电源适配器时有效）")
        }
        nosleepAuto = auto
        scheduleBatteryGuard()
        onStateChange?()
        return true
    }

    /// 系统级开关是持久的，停止时必须显式复位，否则系统再也不会睡眠
    func stopNosleep(_ reason: String = L("手动关闭")) {
        guard nosleepOn else { return }
        if nosleepSystemOn { _ = helperExec("off"); nosleepSystemOn = false }
        nosleepCaff?.terminate(); nosleepCaff = nil
        nosleepOn = false
        nosleepAuto = false
        if blacked { startCaff() }      // 仍在黑屏则恢复黑屏所需的断言
        blog("bar: 防睡眠停止（\(reason)）")
        onStateChange?()
    }

    // MARK: 保持屏幕常亮（-d）
    //
    // 与「防睡眠」是两件事：防睡眠挡的是系统睡眠，这里只挡显示器睡眠。
    // 一个 caffeinate -d 即可，不需要 root——这正是它能作为独立模式存在的理由。
    // 注意与主动关屏不冲突：-d 挡的是「系统自动熄屏」，用户主动把亮度归零照样生效。
    var displayCaff: Process?

    /// 此刻是否真的持有「保持屏幕常亮」的断言（菜单与面板据此标注「未生效」）
    var keepDisplayOnActive: Bool { displayCaff != nil }

    func startKeepDisplayOn() {
        guard displayCaff == nil else { return }
        // 电量下限对「保持屏幕常亮」同样强制生效。它是本程序里唯一「屏幕整夜亮着」的
        // 形态，也是耗电最快的一条 —— 低于下限还去开，等于把「包里放电到关机」铺平。
        // 与另外三条耗电路径（关屏 / 防睡眠 / 息屏后保持唤醒）保持同一套拦截。
        // 只记日志、不弹通知：本函数会被周期对齐反复调用，弹窗会变成骚扰
        // （与 startKeepAwakeAssertion 的 notifyOnBlock 同一取舍）。
        if batteryBlocksStart(cfg) {
            let b = batteryStatus()
            blog("bar: " + L("电量 ") + "\(b.percent)" + L("% 低于下限 ") + "\(cfg.batteryFloor)"
                 + L("%，已取消「保持屏幕常亮」（避免耗尽电池）"))
            onStateChange?()
            return
        }
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        c.arguments = ["-d", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        try? c.run()
        displayCaff = c
        blog("bar: 保持屏幕常亮已开启（阻止显示器自动睡眠）")
        onStateChange?()
    }
    func stopKeepDisplayOn() {
        guard displayCaff != nil else { return }
        displayCaff?.terminate(); displayCaff = nil
        blog("bar: 保持屏幕常亮已关闭")
        onStateChange?()
    }
    /// 按配置对齐常亮状态：启动时恢复持久设置，配置变更后重新对齐。
    func syncKeepDisplayOn() {
        if cfg.keepDisplayOn { startKeepDisplayOn() } else { stopKeepDisplayOn() }
    }

    // MARK: 息屏后保持唤醒（caffeinate -is）
    //
    // 与上面的「防睡眠」是两件事，不能合并：
    //   黑屏联动 = 我们主动压黑屏幕，期间连显示器睡眠一起挡（-dis），屏幕由我们掌控；
    //   这里     = 屏幕交给系统照常熄灭，只挡**系统**睡眠（-is）。
    // 所以这里绝不能带 -d —— 带上之后显示器永远不会自动熄屏，与开关名字自相矛盾。
    //
    // 为什么必须单独有一条：黑屏联动只在用户点过「关闭显示器」的那段时间有效，
    // 而开启「息屏后保持唤醒」的人，最常见用法恰恰是不去点关屏、等系统自己熄屏。
    // 那条路径上过去一条断言都没有，机器照睡，开关等于空转。
    var keepCaff: Process?

    /// 返回 false = 电量低于下限，本次没有持有断言。
    /// notifyOnBlock 只在用户主动开启时传 true：周期对齐时弹通知会变成骚扰。
    @discardableResult
    func startKeepAwakeAssertion(notifyOnBlock: Bool = false) -> Bool {
        guard keepCaff == nil else { return true }
        // 黑屏联动的 -dis 已经覆盖系统睡眠，再叠一条纯属多一个进程
        guard !nosleepOn else { return true }
        if batteryBlocksStart(cfg) {
            let b = batteryStatus()
            let m = (L("电量 ") + "\(b.percent)" + L("% 低于下限 ") + "\(cfg.batteryFloor)"
                     + L("%，已取消「息屏后保持唤醒」（避免耗尽电池）"))
            blog("bar: \(m)")
            if notifyOnBlock { notifyUser(m) }
            onStateChange?()
            return false
        }
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w 本进程：App 一旦退出（哪怕被强杀）caffeinate 自动退出，不留孤儿断言
        c.arguments = ["-is", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        do { try c.run() } catch {
            blog("bar: 息屏后保持唤醒启动失败 \(error)")
            return false
        }
        keepCaff = c
        // 又出现了一个长期耗电的持有者，立刻把电量守卫重新计时。
        // 不重算的话守卫按上一次的节拍走，最长要等 30 秒才发现电量已经触底。
        scheduleBatteryGuard()
        blog("bar: 息屏后保持唤醒已生效（caffeinate -is，屏幕仍可自动熄灭）")
        onStateChange?()
        return true
    }

    func stopKeepAwakeAssertion() {
        guard keepCaff != nil else { return }
        keepCaff?.terminate(); keepCaff = nil
        blog("bar: 息屏后保持唤醒已解除")
        onStateChange?()
    }

    /// 按配置对齐。与 syncKeepDisplayOn 一样是纯对齐，供启动 / 方案变更 /
    /// 电源切换 / 外部改配置 / 黑屏结束各路径共用，避免四处各写一份判断。
    func syncKeepAwake() {
        if cfg.autoNosleep { _ = startKeepAwakeAssertion() } else { stopKeepAwakeAssertion() }
    }

    /// 此刻系统睡眠是否真的被挡住（黑屏联动持有的 -dis 也算）
    var systemSleepBlocked: Bool { keepCaff != nil || nosleepOn }

    // MARK: 状态
    var isBlacked: Bool { fm.fileExists(atPath: stateFile) }

    /// 记录、通知并回传拒绝原因（CLI 从 rejectFile 读到后会给用户明确提示）
    private func reject(_ m: String) -> Bool {
        blog("bar: \(m)")
        notifyUser(m)
        try? m.write(toFile: rejectFile, atomically: true, encoding: .utf8)
        onStateChange?()
        return false
    }

    /// 返回 false = 没能进入黑屏（亮度接口不可用或电量过低）
    @discardableResult
    func blackout() -> Bool {
        guard !blacked else { return true }
        restoreRetry?.invalidate(); restoreRetry = nil
        guard dsAvailable else {
            return reject(L("亮度接口不可用（DisplayServices 缺失），无法关屏"))
        }
        // 电量下限：黑屏 + 阻止睡眠的组合让人最容易忘记，耗尽电池会带走未保存的工作
        if batteryBlocksStart(cfg) {
            let b = batteryStatus()
            return reject((L("电量 ") + "\(b.percent)" + L("% 低于下限 ") + "\(cfg.batteryFloor)" + L("%，已取消关屏（避免耗尽电池）")))
        }
        try? fm.removeItem(atPath: rejectFile)
        let cur = max(readBrightness(), 0)
        saved = cur > 0.001 ? cur : saved
        try? String(saved).write(toFile: stateFile, atomically: true, encoding: .utf8)
        blacked = true
        if !setBrightness(0.0) { blog("bar: 警告：首次设置亮度 0 失败") }
        startCaff()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if self?.blacked == true { setBrightness(0.0) }
        }
        RunLoop.main.add(t, forMode: .common)
        pinTimer = t
        scheduleTimeout()
        scheduleBatteryGuard()
        // 关屏与防睡眠联动：这是「屏幕黑着但机器保持可远程」的完整场景
        if cfg.autoNosleep { startNosleep(auto: true) }
        blog("bar: 进入黑屏，原亮度 \(saved)，电量下限 \(cfg.batteryFloor > 0 ? "\(cfg.batteryFloor)%" : "不限")")
        onStateChange?()
        return true
    }

    // 黑屏期间每 30s 复查电量，跌破下限立即恢复；这是硬保护，
    // 即使用户想保持黑屏也不放行——耗尽电池的代价比「被打断」大得多
    /// 电量守卫同时覆盖黑屏与防睡眠：合盖 + 电池 + 不睡眠是最容易耗尽电量的组合，
    /// 机器在包里持续发热直到没电，用户却毫不知情。
    /// 电池触底后的「彻底放手」：恢复屏幕 + 撤销防睡眠 + 退出合盖运行，
    /// 让 Mac 回到系统原本的省电行为（该睡就能睡）。
    /// 用户在设置里选「回到原本的电池行为」时走的就是这条路径。
    func releaseForBattery(_ reason: String) {
        blog("bar: \(reason) —— 撤销全部防睡眠，回到系统原本的电池行为")
        if blacked { restore() }
        stopNosleep(reason)
        if cfg.lidAwake { _ = setLidAwake(false) }
        // 方案也要一起归位为「合盖睡眠」：只停守护的话，周期巡检会在 15 秒后
        // 按方案把守护重新拉起来，「电量触底彻底放手」等于没做，机器照样在包里耗到关机
        rollbackPlanToSystemDefaults(reason: reason)
        cfg = loadConfig()          // setLidAwake / rollback 都写过配置，重读以免覆盖它们的结果
        syncKeepDisplayOn()
        syncKeepAwake()             // 方案里已清掉 keepAwake，这里会真正卸下断言
        onStateChange?()
    }

    /// 每 30s 复查电量，跌破下限后按用户选的动作处理。
    /// 覆盖黑屏、防睡眠与合盖运行——合盖 + 电池 + 不睡眠是最容易耗尽电量的组合，
    /// 机器在包里持续发热直到没电，用户却毫不知情。
    func scheduleBatteryGuard() {
        battTimer?.invalidate(); battTimer = nil
        battNotified = false
        guard cfg.batteryFloor > 0 else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            // 五种「正在耗电」的状态都要盯：漏掉任何一种，那条路径上的下限就形同虚设。
            // keepCaff 尤其容易漏——它是**独立于黑屏**长期持有的断言，
            // 掀盖息屏后机器会一直跑，正是最容易在包里放电到关机的形态。
            // displayCaff 同样独立于黑屏长期持有，且是唯一「屏幕整夜亮着」的形态：
            // 漏掉它的后果最直接——屏幕亮到电池耗尽、系统直接断电关机。
            guard let self = self,
                  self.blacked || self.nosleepOn || self.lidOn
                    || self.keepCaff != nil || self.displayCaff != nil else { return }
            let b = batteryStatus()
            guard b.onBattery && b.discharging, b.percent <= self.cfg.batteryFloor else {
                self.battNotified = false       // 插上电或充回来了，解除提醒锁
                return
            }
            guard !self.battNotified else { return }
            self.battNotified = true
            let m = (L("电量 ") + "\(b.percent)" + L("% 已达下限 ") + "\(self.cfg.batteryFloor)" + L("%，自动恢复"))
            blog("bar: \(m)")
            notifyUser(m)
            switch BatteryAction(rawValue: self.cfg.batteryAction) ?? .restoreOnly {
            case .restoreOnly:
                if self.blacked { self.restore() }
                // 「恢复屏幕」覆盖不到常亮：它本来就没黑屏，是独立于黑屏持有的断言。
                // 不在这里放手的话，默认动作在「只开了常亮」的场景下等于什么都没做 ——
                // 而那正是屏幕整夜亮着、放电到自动关机的那条路径。
                self.releaseKeepDisplayOn(reason: (L("电量已达下限 ") + "\(self.cfg.batteryFloor)" + "%"))
            case .restoreAndRelease:
                self.releaseForBattery((L("电量已达下限 ") + "\(self.cfg.batteryFloor)" + "%"))
            case .notifyOnly:
                break                            // 只提醒，状态原样保留
            }
        }
        RunLoop.main.add(t, forMode: .common)
        battTimer = t
    }

    func restore() {
        guard blacked else { return }
        blacked = false
        pinTimer?.invalidate(); pinTimer = nil
        timeoutTimer?.invalidate(); timeoutTimer = nil
        // 电量守卫**不**随恢复显示一起撤掉：它管的还有防睡眠与合盖守护，
        // 后两者的寿命长于一次黑屏。撤掉的话，用户「黑屏 → 手动恢复 → 合盖运行」时
        // 下限就没人看着了。守卫自己会判断该不该动作，闲置时零开销。
        // 联动开启的防睡眠随黑屏一起结束；用户手动开启的保持不动
        if nosleepAuto { stopNosleep(L("已恢复显示")) }
        // 防睡眠属于「黑屏期间」的临时断言，但「息屏后保持唤醒」是持久设置：
        // 屏幕回来了它依然要挡系统睡眠，所以这里必须把它的断言接回来
        syncKeepAwake()
        let target = cfg.restoreFixed ?? saved
        blog("bar: 恢复显示 \(target)")
        // 恢复失败不能就此罢休：屏幕会一直黑着。持续重试直到真的亮回来。
        if !restoreBrightness(target) {
            blog("bar: 错误：亮度恢复失败，转入持续重试")
            notifyUser(L("亮度恢复失败，正在持续重试"))
            restoreRetry?.invalidate()
            let rt = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
                guard let self = self else { t.invalidate(); return }
                if restoreBrightness(target) {
                    blog("bar: 重试成功，亮度已恢复 \(target)")
                    t.invalidate(); self.restoreRetry = nil
                }
            }
            RunLoop.main.add(rt, forMode: .common)
            restoreRetry = rt
        }
        caff?.terminate(); caff = nil
        try? fm.removeItem(atPath: stateFile)
        onStateChange?()
    }

    func toggle() { if blacked { restore() } else { _ = blackout() } }

    func scheduleTimeout() {
        timeoutTimer?.invalidate(); timeoutTimer = nil
        guard cfg.timeout > 0 else { return }
        let t = Timer.scheduledTimer(withTimeInterval: cfg.timeout, repeats: false) { [weak self] _ in
            blog("bar: 兜底超时，自动恢复")
            self?.restore()
        }
        RunLoop.main.add(t, forMode: .common)
        timeoutTimer = t
    }

    // MARK: 热键
    var hotkeyReady = false                  // Carbon 全局热键是否已注册成功
    var lastHotkeyStatus: OSStatus = noErr
    private var lastLoggedStatus: OSStatus = noErr

    func installHotkey() {
        carbonFire = { [weak self] in
            guard self?.selfTesting != true else { return }
            self?.toggle()
        }
        // 用户可以整个关掉热键：此时不注册，也不该报「注册失败」的警示
        guard cfg.hotkeyEnabled else {
            unregisterCarbonHotKey()
            hotkeyReady = false
            lastHotkeyStatus = noErr
            blog("bar: 全局热键已按设置停用")
            return
        }
        let st = registerCarbonHotKey(keyCode: cfg.keyCode, modFlags: cfg.modFlags)
        hotkeyReady = (st == noErr)
        lastHotkeyStatus = st
        if hotkeyReady {
            lastLoggedStatus = noErr
            blog("bar: 全局热键已注册 \(hotkeyText(cfg))（Carbon 链路，无需授权）")
        } else if st != lastLoggedStatus {
            lastLoggedStatus = st
            blog("bar: 全局热键注册失败 \(hotkeyText(cfg)) —— \(carbonStatusText(st))")
        }
    }

    func reloadHotkey() { installHotkey() }

    // MARK: 自检：验证真实按键能否送达本程序
    /// 先合成一次组合键自动验证（App 自身有事件循环，合成事件能走完真实链路），
    /// 通过则无需用户手动按键
    func selfTest(completion: @escaping (Bool) -> Void) {
        guard hotkeyReady else { completion(false); return }
        var got = false
        selfTesting = true                 // 自检期间只记录，不真的开关屏幕
        carbonProbe = { got = true }
        postSyntheticHotkey()
        let deadline = Date().addingTimeInterval(2.5)
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if got || Date() > deadline {
                timer.invalidate()
                self.selfTesting = false
                carbonProbe = nil
                blog("bar: 热键自检 \(got ? "通过" : "未收到按键") \(hotkeyText(self.cfg))")
                completion(got)
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    /// 合成一次配置中的组合键（自动化自检用）
    private func postSyntheticHotkey() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(cfg.keyCode), keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(cfg.keyCode), keyDown: false)
        else { return }
        var f = CGEventFlags()
        if cfg.modFlags & MOD_CMD   != 0 { f.insert(.maskCommand) }
        if cfg.modFlags & MOD_SHIFT != 0 { f.insert(.maskShift) }
        if cfg.modFlags & MOD_ALT   != 0 { f.insert(.maskAlternate) }
        if cfg.modFlags & MOD_CTRL  != 0 { f.insert(.maskControl) }
        down.flags = f
        up.flags = f
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: 生命周期
    func start() {
        takeoverServiceSlot()
        killSiblingInstances()   // 用 NSRunningApplication 枚举，不依赖 ps
        // 自愈：上次异常退出遗留的黑屏状态
        if let s = try? String(contentsOfFile: stateFile, encoding: .utf8),
           let v = Float(s.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0.001 {
            blog("bar: 发现遗留黑屏状态，自愈恢复到 \(v)")
            restoreBrightness(v)
        }
        try? fm.removeItem(atPath: stateFile)
        try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: serviceFile, atomically: true, encoding: .utf8)
        try? fm.removeItem(atPath: commandFile)
        installHotkey()

        // 先按当前电源来源把方案投影到生效值：上次退出时接着电源、这次开机用电池，
        // 三布尔还停在上一次的方案上，不投影就会「配置写着一套、机器按另一套跑」
        cfg = syncPlanToActive()
        lastPowerSourceWasBattery = onBatteryNow()

        // 合盖模式是持久标志：App 重启 / 电脑重启后自动恢复守护；
        // 助手缺失（如被手动卸载）则停用标志并明确告知，不留「以为开着其实没开」的状态
        if cfg.lidAwake {
            if let info = nosleepInfoStatus(), lidDaemonPid() != nil, info.level != "system" {
                // 守护在跑却是进程级：进程级 caffeinate 挡不住合盖睡眠，
                // 「合盖后不睡眠」此时名存实亡。常见成因是守护启动时 helper
                // 调用失败（授权过期 / 竞态）。重启一次把它拉回系统级，
                // 否则用户会一直带着「以为开着其实没开」的错觉合盖。
                blog("bar: 合盖守护降级为进程级（挡不住合盖睡眠），重启以恢复系统级")
                _ = setLidAwake(false)
                _ = setLidAwake(true)
            } else {
                // 缺助手 / 电量低都在这里被拦下并告知；方案保持不动，
                // 用户装好助手或插上电后由周期巡检自动补起，不必重新设置
                _ = ScreenController.shared.reconcileLidDaemon(want: true, why: "启动恢复")
            }
        } else if lidDaemonPid() != nil {
            // 当前方案不要求合盖运行，守护却还活着——可能是上一次在另一个电源来源下开的，
            // 也可能是用户手动 `lidkeep nosleep on --system` 起的。
            // 归属语义：以方案为准（对齐是既定行为），但**不能静默**撤销 ——
            // 手动敲的命令被 GUI 启动悄悄翻掉，用户只会认为「设置不管用」，
            // 而且他没有任何线索知道该去哪里改回来。
            blog("bar: 当前电源方案不要求合盖运行，停止遗留的合盖守护")
            _ = setLidAwake(false)
            cfg = loadConfig()
            notifyUser(L("已按当前电源方案停止「合盖不睡」。如需长期保留，请把该方案的「合盖时」设为「保持唤醒」。"))
        }

        // 「保持屏幕常亮」同样是持久标志：重启后按配置恢复，否则用户会以为还开着
        syncKeepDisplayOn()
        // 「息屏后保持唤醒」同理。这条必须由 App 自己持有：黑屏联动只在关屏期间
        // 才拉起断言，不点关屏就没人挡系统睡眠，开关等于空转。
        syncKeepAwake()
        startPowerSourceWatcher()
        // 电量守卫必须在这里就位，不能只在「黑屏」和「开始防睡眠」时才装。
        // 合盖守护是独立进程，App 重启带不走它：启动时它可能已经在跑，
        // 那条路径上若没有守卫，「电池掉到下限」就永远不会被触发——
        // 机器在包里一路放电到关机，而用户以为下限在保护他（实测踩过）。
        // 守卫自身每 30s 检查 blacked/nosleepOn/lidOn，都没有时直接返回，常驻无成本。
        scheduleBatteryGuard()

        // 指令走命令文件：SIGUSR1/USR2 必须显式忽略（默认行为是终止进程），
        // 真正的开关动作由下方 Timer 轮询 command 文件完成
        for sig in [SIGUSR1, SIGUSR2, SIGHUP] { signal(sig, SIG_IGN) }
        signal(SIGTERM) { _ in gotTerminate = true }
        signal(SIGINT)  { _ in gotTerminate = true }

        let ct = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.pumpCommand()
        }
        RunLoop.main.add(ct, forMode: .common)
        cmdTimer = ct
        blog("bar: 服务已启动 pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    /// 电源来源监听：拔掉 / 插上电源时自动切到对应的那套方案。
    /// 与电量守卫共用同一套 Timer 约定（挂 .common 模式），避免菜单滚动时停摆。
    private func startPowerSourceWatcher() {
        powerTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if switchPlanIfPowerSourceChanged() { self.onStateChange?() }
            self.patrolLidDaemon()
        }
        RunLoop.main.add(t, forMode: .common)
        powerTimer = t
    }

    /// 周期巡检合盖守护。只补不关：
    /// 守护可能被外部杀掉、或在电量触底时被停掉、或上次拉起失败（无助手），
    /// 而方案依然写着「合盖不睡」——不补的话用户合盖就睡，还以为设置生效着。
    /// 关闭动作交给方案变更路径，避免把用户手动 `lidkeep nosleep on` 起的守护误杀。
    private func patrolLidDaemon() {
        let p = activePlan(cfg)
        guard p.lid == .nothing else { return }
        // 上次失败的原因若已消失（插上电了 / 助手装好了），就地清掉退避、立刻重试。
        // 不这样的话用户插上电还要干等退避结束，观感就是「设置不管用」。
        if lidRetryAfter != nil {
            let cleared: Bool
            switch lidRetryBlocker {
            case "helper":  cleared = helperInstalled()
            case "battery": cleared = !batteryBlocksStart(cfg)
            default:        cleared = true
            }
            if cleared { lidRetryAfter = nil; lidRetryBlocker = nil }
        }
        if reconcileLidDaemon(want: true, why: "周期巡检") { onStateChange?() }
    }

    /// 指定 pid 名下的 caffeinate 子进程（强杀旧实例前记录，事后清理）。
    ///
    /// 进程内枚举（`allPids` + `procPpid`），不 spawn `pgrep -P`/`ps`：
    /// 受限环境（含本机 `make test`）拒绝执行 setuid 程序，`ps` 被拒时这里会静默返回空 ——
    /// 于是「旧实例遗留的 caffeinate」永远清理不掉，它带着 `-w <旧 pid>` 一直阻止系统睡眠。
    private func childCaffeinatePids(of parent: Int32) -> [Int32] {
        allPids().filter { procPpid($0) == parent && pidIsCaffeinate($0) }
    }

    /// 终止同 bundle 的其他实例 —— 比 takeoverServiceSlot 更彻底：
    /// 走 NSRunningApplication（进程内），不依赖 ps，也不依赖 service.pid 文件是否干净。
    private func killSiblingInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.lidkeep.bar")
            .filter { $0.processIdentifier != me }
        for app in others {
            let oldPid = app.processIdentifier
            blog("bar: 终止同 bundle 旧实例 pid=\(oldPid)")
            // 先记下旧实例的 caffeinate 子进程：SIGKILL 无法触发其清理逻辑
            let kids = childCaffeinatePids(of: oldPid)
            app.terminate()
            usleep(500_000)
            if app.isTerminated == false {
                blog("bar: 旧实例未响应，强制终止 pid=\(oldPid)")
                app.forceTerminate()
            }
            for k in kids where kill(k, 0) == 0 {
                blog("bar: 清理旧实例遗留的 caffeinate pid=\(k)")
                kill(k, SIGTERM)
            }
        }
    }

    private func takeoverServiceSlot() {
        guard let s = try? String(contentsOfFile: serviceFile, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid != ProcessInfo.processInfo.processIdentifier, kill(pid, 0) == 0 else { return }
        // 归属只能看可执行文件本身（proc_pidpath），不能看命令行——理由见 Sources/Shared/Ownership.swift。
        // 这里是在**给 pid 发信号**，判错就是误杀：pid 被系统复用后，任何「命令行里恰好提到过
        // LidKeep 路径」的进程（跑调试脚本的 shell、终端里的 grep）都会被当成本程序旧实例干掉。
        guard pidIsOurExecutable(pid) else {
            blog("bar: service.pid 记录的 pid=\(pid) 已不属于 lidkeep（pid 被复用或为无关进程），不接管")
            return
        }
        // 旧实例可能是 CLI daemon，也可能是上一个 LidKeep 实例——都应接管（单实例语义）
        let name = ((procExecutablePath(pid) ?? "") as NSString).lastPathComponent
        let which = (name == "LidKeep") ? L("上一个 LidKeep 实例") : "lidkeep daemon"
        blog("bar: 接管 service.pid，终止旧 \(which) pid=\(pid)")
        kill(pid, SIGTERM)
        usleep(800_000)
        if kill(pid, 0) == 0 { kill(pid, SIGKILL); usleep(200_000) }   // 顽固时升级
    }

    /// config.json 被改动（包括用 CLI 修改）时自动重载，无需重启
    private func reloadConfigIfChanged() {
        guard let a = try? fm.attributesOfItem(atPath: configFile),
              let m = a[.modificationDate] as? Date else { return }
        var stamp = m
        if let old = configMtime, m > old {
            var newCfg = loadConfig()
            // hotkeyEnabled 也算「需要重装热键」——installHotkey() 正是用它决定注不注册。
            // 只比 keyCode/modFlags 的话，`lidkeep config --hotkey off` 改完盘、App 也重载了
            // 配置，却不会去注销那个已注册的热键：用户以为关掉了，热键仍然生效，
            // 菜单栏也不会给出任何异常提示（hotkeyReady 仍为 true）。
            let keyChanged = newCfg.keyCode != cfg.keyCode || newCfg.modFlags != cfg.modFlags
                || newCfg.hotkeyEnabled != cfg.hotkeyEnabled
            // 外部（CLI / 手动编辑）可能改动了方案。三布尔是方案的投影，
            // 由常驻进程按自己的电源判断重新推导——否则两端判断不一致时
            // 就会留下「配置写着一套、机器按另一套跑」的分叉状态。
            let p = activePlan(newCfg)
            let before = (newCfg.autoNosleep, newCfg.keepDisplayOn, newCfg.lidAwake)
            projected(&newCfg, from: p)
            let wasOurs = cfg.lidAwake      // 取值须在 cfg 被覆盖之前，见 reconcileLidDaemon 注释
            if before != (newCfg.autoNosleep, newCfg.keepDisplayOn, newCfg.lidAwake) {
                blog("bar: 电源方案被外部改动，按当前电源来源重新对齐生效值")
                saveConfig(newCfg)
            }
            cfg = newCfg
            if keyChanged { installHotkey() }
            syncKeepDisplayOn()
            syncKeepAwake()
            reconcileLidDaemon(want: p.lid == .nothing, why: "外部改动配置", wasOurs: wasOurs)
            if !cfg.autoNosleep && nosleepOn && nosleepAuto { stopNosleep(L("切换运行方案")) }
            if blacked { scheduleTimeout(); scheduleBatteryGuard() }
            blog("bar: 配置已自动重载 \(hotkeyText(cfg))")
            // 设置面板若正开着，它的编辑副本必须跟着换新：留着旧值的话，
            // 用户下一次在面板里改动任何一项，提交时会把刚重载进来的外部改动整片盖回去。
            onConfigReloaded?()
            // 本轮里自己可能写过盘（投影落盘、守护开关都会写 config）。
            // 最后统一取一次 mtime 当基准，否则下一轮会把自己的写入当成外部改动，白白再重载一遍。
            if let a2 = try? fm.attributesOfItem(atPath: configFile),
               let m2 = a2[.modificationDate] as? Date { stamp = m2 }
        }
        configMtime = stamp
    }

    private func pumpCommand() {
        if gotTerminate { shutdown(); return }
        reloadConfigIfChanged()
        guard let s = try? String(contentsOfFile: commandFile, encoding: .utf8) else { return }
        try? fm.removeItem(atPath: commandFile)
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off", "black":   blog("bar: 收到指令 off"); blackout()
        case "on", "restore":  blog("bar: 收到指令 on"); restore()
        case "toggle":         blog("bar: 收到指令 toggle"); toggle()
        default: break
        }
    }

    func shutdown() {
        restore()
        // 系统级开关是持久的：退出前必须复位，否则退出后系统再也不会睡眠
        stopNosleep(L("程序退出"))
        stopKeepAwakeAssertion()
        try? fm.removeItem(atPath: serviceFile)
        blog("bar: 退出")
        exit(0)
    }
}

// MARK: - 设置面板

// MARK: - 布局辅助

/// 滚动容器默认把内容贴在底部（坐标系未翻转），内容比可视区矮时会留一大片空白。
/// 用翻转坐标系的容器把内容钉在顶部。
final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - 电池保护：触底时做什么


/// 电量是否低到「不该再启动」新的耗电动作（防睡眠 / 关屏 / 合盖运行）。
/// 「只提醒」模式下不拦截——那正是用户选择自己负责的含义。
func batteryBlocksStart(_ c: Config) -> Bool {
    guard c.batteryFloor > 0 else { return false }
    if BatteryAction(rawValue: c.batteryAction) ?? .restoreOnly == .notifyOnly { return false }
    let b = batteryStatus()
    return b.onBattery && b.discharging && b.percent <= c.batteryFloor
}

// MARK: - 热键录入控件
/// 点一下进入录制，直接按组合键即可写入。
/// 相比「修饰键勾选框 + 按键下拉框」，它能录入键盘上的任意键，而不只是预设表里的一小部分。
final class HotkeyRecorder: NSButton {
    var onCapture: ((UInt64, Int64) -> Void)?
    var onClear: (() -> Void)?
    /// 外部写入的展示文本
    var displayText: String = "" { didSet { if !recording { refreshTitle() } } }
    private(set) var recording = false { didSet { refreshTitle() } }
    /// 录制期间临时摘下的菜单快捷键，结束时要装回去
    private var savedEquivalents: [(NSMenuItem, String)] = []

    /// 纯修饰键的虚拟键码，只按这些键时不算录入完成
    private static let pureModifiers: Set<Int64> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    func startRecording() {
        guard !recording else { return }
        suspendMenuEquivalents()
        recording = true
        window?.makeFirstResponder(self)
    }

    /// 结束录制并恢复菜单快捷键。窗口关闭、焦点丢失都要走到这里，
    /// 否则菜单的 ⌘, / ⌘Q 会永久失效。
    func stopRecording() {
        guard recording else { return }
        recording = false
        restoreMenuEquivalents()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }
    override func cancelOperation(_ sender: Any?) { stopRecording() }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let code = Int64(event.keyCode)
        if code == 53 { stopRecording(); return }                  // Esc 取消
        if code == 51 { stopRecording(); onClear?(); return }      // ⌫ 清除
        if HotkeyRecorder.pureModifiers.contains(code) { return }  // 只按了修饰键，继续等

        var f: UInt64 = 0
        let m = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if m.contains(.control) { f |= MOD_CTRL }
        if m.contains(.option)  { f |= MOD_ALT }
        if m.contains(.command) { f |= MOD_CMD }
        if m.contains(.shift)   { f |= MOD_SHIFT }
        // 系统级全局热键必须带至少一个修饰键，否则 RegisterEventHotKey 直接失败
        guard f != 0 else { NSSound.beep(); return }
        stopRecording()
        onCapture?(f, code)
    }

    private func refreshTitle() {
        title = recording ? L("按下组合键…（Esc 取消）") : displayText
    }

    /// 菜单快捷键（⌘, 打开设置、⌘Q 退出）由 NSApp 在 keyDown 之前截走，
    /// 录制 ⌘, 这类组合时会永远收不到。录制期间先把它们摘掉。
    private func suspendMenuEquivalents() {
        savedEquivalents.removeAll()
        func walk(_ menu: NSMenu) {
            for it in menu.items {
                if !it.keyEquivalent.isEmpty {
                    savedEquivalents.append((it, it.keyEquivalent))
                    it.keyEquivalent = ""
                }
                if let sm = it.submenu { walk(sm) }
            }
        }
        if let mm = NSApp.mainMenu { walk(mm) }
    }
    private func restoreMenuEquivalents() {
        for (it, eq) in savedEquivalents { it.keyEquivalent = eq }
        savedEquivalents.removeAll()
    }
}

// MARK: - 设置面板
final class SettingsPanel: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private let ctl = ScreenController.shared
    private var cfg = loadConfig()          // 面板内的编辑副本，保存时才写回生效

    // 热键
    private var hkEnableBtn: NSButton!
    private var hkRecorder: HotkeyRecorder!
    private var hkStatusLabel: NSTextField!
    private var timeoutPop: NSPopUpButton!
    // 电池
    private var battSlider: NSSlider!
    private var battValueLabel: NSTextField!
    private var battActionBtns: [NSButton] = []
    // 通用：接通电源 / 使用电池两套方案
    private var modeBtns: [NSButton] = []
    private var acKeepBtn: NSButton!      // 息屏后保持唤醒（接通电源）
    private var acDispBtn: NSButton!      // 保持屏幕常亮（接通电源）
    private var acLidPop: NSPopUpButton!  // 合盖时（接通电源）
    private var battKeepBtn: NSButton!
    private var battDispBtn: NSButton!
    private var battLidPop: NSPopUpButton!
    private var planSummaryLabel: NSTextField!
    private var lidBlackoutBtn: NSButton!
    private var helperLabel: NSTextField!
    private var helperBtn: NSButton!
    private var restorePop: NSPopUpButton!
    private var restoreSlider: NSSlider!
    private var restoreValueLabel: NSTextField!
    // 其他
    private var loginBtn: NSButton!
    private var autoUpdateBtn: NSButton!

    private let timeoutChoices: [(String, Double)] = [
        (L("不启用（一直保持黑屏）"), 0),
        (L("30 分钟"), 1800), (L("1 小时"), 3600), (L("2 小时"), 7200),
        (L("4 小时"), 14400), (L("8 小时"), 28800), (L("12 小时"), 43200)
    ]

    func show() {
        if window == nil { window = build() }
        syncFromConfig()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 窗口关闭时若还在录制，菜单快捷键必须装回去
    func windowWillClose(_ notification: Notification) {
        hkRecorder?.stopRecording()
    }

    /// 供外部（配置被 CLI 改动）调用。窗口还没建或已关掉时直接返回：
    /// `syncFromConfig` 里有若干隐式解包控件（helperLabel / helperBtn 等），
    /// 界面尚未构建时调用会直接崩。
    func refreshIfVisible() {
        guard window != nil, window.isVisible else { return }
        syncFromConfig()
    }

    // MARK: 窗口骨架：分页 + 可滚动
    //
    // 原先是 470×830 的单列长窗：八个小节挤在一起、不能滚动，小屏上直接被截断。
    // 改成 4 个标签页后每页只装一两类设置，且每页可滚动——以后再加设置也不会撑破。
    private func build() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("LidKeep 设置")
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.center()

        let tab = NSTabView(frame: NSRect(x: 0, y: 0, width: 560, height: 560))
        tab.tabViewType = .topTabsBezelBorder
        tab.autoresizingMask = [.width, .height]
        tab.addTabViewItem(tabItem(L("通用"), buildGeneralTab()))
        tab.addTabViewItem(tabItem(L("热键"), buildHotkeyTab()))
        tab.addTabViewItem(tabItem(L("电池"), buildBatteryTab()))
        tab.addTabViewItem(tabItem(L("其他"), buildMiscTab()))
        w.contentView = tab
        return w
    }

    // MARK: 通用
    private func buildGeneralTab() -> NSView {
        let stack = column()

        // —— 电源方案：接通电源 / 使用电池两套，各自三个互不排斥的开关。
        //    借鉴 Windows「电源选项」：拔插电源是两种截然不同的场景，不该共用一套设置。
        //    「息屏后保持唤醒」与「合盖时：保持唤醒」可以同时开——前者管息屏期间
        //    的系统睡眠，后者管合盖这个动作，本来就是两件事。
        stack.addArrangedSubview(group(L("接通电源时"), planRows(
            keep: &acKeepBtn, disp: &acDispBtn, lid: &acLidPop, ac: true)))
        stack.addArrangedSubview(group(L("使用电池时"), planRows(
            keep: &battKeepBtn, disp: &battDispBtn, lid: &battLidPop, ac: false)))

        // 摘要直接作为页面说明行，不进分组盒：单行 label 独占一个 box 时
        // 高度会被算成 0、文字向上溢出与组标题重叠（截图核验实测，换 label 类型也一样）。
        let onBatInit = onBatteryNow()
        let initCfg = loadConfig()
        let initPlan = onBatInit ? initCfg.planBattery : initCfg.planAC
        // 摘要行必须能**换行**：英文文案在「三项全开」时约 479pt，超过卡内 440pt
        // 可用宽度，单行 label 会把尾巴直接截掉（实测：中文 358pt 安全、英文超 39pt）。
        // wrapLabel 内部已把宽度钉死 440，换行高度才算得准。
        planSummaryLabel = wrapLabel(L("当前：") + powerSourceTitle(battery: onBatInit)
                                     + L(" —— ") + initPlan.summary)
        stack.addArrangedSubview(planSummaryLabel)

        // —— 合盖运行的共同设置（不区分电源来源）
        lidBlackoutBtn = NSButton(checkboxWithTitle: L("合盖时熄灭内屏"), target: self, action: #selector(onLidBlackoutToggled(_:)))
        let helperRow = NSStackView(); helperRow.orientation = .horizontal; helperRow.spacing = 10
        helperBtn = NSButton(title: L("安装提权助手…"), target: self, action: #selector(onInstallHelper(_:)))
        helperRow.addArrangedSubview(helperBtn)
        helperLabel = wrapLabel("")
        let lidViews: [NSView] = [lidBlackoutBtn, wrapLabel(
            L("「合盖时熄灭内屏」由合盖守护执行，因此需要先把某套方案里的「合盖时」设为「保持唤醒」；") +
            L("个别机型熄屏后亮度回不来时，可单独关掉它作为退路。") +
            L("合盖运行建议接电源使用；电池放电低于电量下限会自动停止。需要提权助手（下方安装）。")),
            helperRow, helperLabel]
        stack.addArrangedSubview(group(L("合盖运行"), stackOf(lidViews)))

        // —— 恢复后的亮度
        restorePop = NSPopUpButton(frame: .zero, pullsDown: false)
        restorePop.addItems(withTitles: [L("恢复到关屏前的亮度"), L("固定为")])
        restorePop.target = self; restorePop.action = #selector(onRestoreModeChanged(_:))

        let sliderRow = NSStackView(); sliderRow.orientation = .horizontal; sliderRow.spacing = 8
        restoreSlider = NSSlider(value: 50, minValue: 5, maxValue: 100, target: self, action: #selector(onSliderChanged(_:)))
        restoreSlider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        restoreValueLabel = NSTextField(labelWithString: "50%")
        restoreValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        restoreValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sliderRow.addArrangedSubview(restoreSlider)
        sliderRow.addArrangedSubview(restoreValueLabel)

        // 缩进到与上方「策略」弹窗左缘对齐（标签 66 + 间距 12）
        let alignedSlider = NSStackView(); alignedSlider.orientation = .horizontal; alignedSlider.spacing = 0
        let pad = NSView(); pad.widthAnchor.constraint(equalToConstant: 78).isActive = true
        alignedSlider.addArrangedSubview(pad)
        alignedSlider.addArrangedSubview(sliderRow)

        stack.addArrangedSubview(group(L("恢复后的亮度"), stackOf([
            formRow(L("策略"), restorePop),
            alignedSlider
        ])))

        return scrollable(stack)
    }

    // MARK: 热键
    private func buildHotkeyTab() -> NSView {
        let stack = column()

        hkEnableBtn = NSButton(checkboxWithTitle: L("启用全局热键"), target: self, action: #selector(onHotkeyEnabledToggled(_:)))
        hkRecorder = HotkeyRecorder(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        hkRecorder.bezelStyle = .rounded
        hkRecorder.setButtonType(.momentaryPushIn)
        hkRecorder.font = .systemFont(ofSize: 13)
        hkRecorder.onCapture = { [weak self] mods, code in
            guard let self else { return }
            self.cfg.modFlags = mods
            self.cfg.keyCode = code
            self.commit()
        }
        hkRecorder.onClear = { [weak self] in
            guard let self else { return }
            self.cfg.modFlags = MOD_CTRL | MOD_ALT | MOD_CMD
            self.cfg.keyCode = 11
            self.commit()
        }

        hkStatusLabel = wrapLabel("")
        let checkBtn = NSButton(title: L("运行自检"), target: self, action: #selector(onCheck(_:)))
        let dfltBtn = NSButton(title: L("恢复默认"), target: self, action: #selector(onHotkeyReset(_:)))
        let hkBtnRow = NSStackView(); hkBtnRow.orientation = .horizontal; hkBtnRow.spacing = 10
        hkBtnRow.addArrangedSubview(dfltBtn)
        hkBtnRow.addArrangedSubview(checkBtn)

        stack.addArrangedSubview(group(L("恢复热键"), stackOf([
            hkEnableBtn,
            wrapLabel(L("关闭后只能用菜单栏点击操作。热键由系统级 Carbon 链路注册，不需要「辅助功能 / 输入监控」授权，也不会因重装 App 而失效。")),
            formRow(L("快捷键"), hkRecorder),
            wrapLabel(L("点按上面的按钮，再直接按下新组合键即可；⌫ 清除，Esc 取消。系统级热键必须包含 ⌘ / ⌃ / ⌥ / ⇧ 中的至少一个。")),
            hkBtnRow,
            hkStatusLabel
        ])))

        // —— 兜底超时
        timeoutPop = NSPopUpButton(frame: .zero, pullsDown: false)
        timeoutPop.addItems(withTitles: timeoutChoices.map { $0.0 })
        timeoutPop.target = self; timeoutPop.action = #selector(onTimeoutChanged(_:))
        stack.addArrangedSubview(group(L("自动恢复兜底"), stackOf([
            formRow(L("黑屏后"), timeoutPop),
            wrapLabel(L("热键失效时的安全网。设为「不启用」则一直保持黑屏，直到手动恢复或退出本程序。"))
        ])))

        return scrollable(stack)
    }

    // MARK: 电池
    private func buildBatteryTab() -> NSView {
        let stack = column()

        battSlider = NSSlider(value: 20, minValue: 0, maxValue: 100, target: self, action: #selector(onBatterySliderChanged(_:)))
        battSlider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        battValueLabel = NSTextField(labelWithString: "20%")
        battValueLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        battValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        battValueLabel.alignment = .right
        let sliderRow = NSStackView(); sliderRow.orientation = .horizontal; sliderRow.spacing = 10
        sliderRow.addArrangedSubview(battSlider)
        sliderRow.addArrangedSubview(battValueLabel)

        stack.addArrangedSubview(group(L("电量保护"), stackOf([
            wrapLabel(L("使用电池且正在放电时，剩余电量降到这个数值就触发下面的动作。拖到 0 表示不限制。插着电源时完全不干预。")),
            formRow(L("阈值"), sliderRow)
        ])))

        var actionViews: [NSView] = []
        for a in BatteryAction.allCases {
            let b = NSButton(radioButtonWithTitle: a.title, target: self, action: #selector(onBatteryActionSelected(_:)))
            b.tag = a.rawValue
            actionViews.append(b)
            actionViews.append(indent(wrapLabel(a.detail)))
            battActionBtns.append(b)
        }
        stack.addArrangedSubview(group(L("达到阈值后"), stackOf(actionViews)))

        return scrollable(stack)
    }

    // MARK: 其他
    private func buildMiscTab() -> NSView {
        let stack = column()

        loginBtn = NSButton(checkboxWithTitle: L("登录时自动启动（菜单栏常驻）"), target: self, action: #selector(onLoginToggled(_:)))
        autoUpdateBtn = NSButton(checkboxWithTitle: L("自动检查更新"), target: self, action: #selector(onAutoUpdateToggled(_:)))
        stack.addArrangedSubview(group(L("启动"), stackOf([
            loginBtn,
            autoUpdateBtn,
            wrapLabel(
                L("后台每 24 小时查一次 GitHub 上的最新版本号；发现新版只在菜单栏打标，不弹窗打断。") +
                L("请求只读取公开的版本号，不上传任何本机信息。手动「检查更新…」不受这个开关限制。"))
        ])))

        stack.addArrangedSubview(group(L("安全提醒"), stackOf([
            wrapLabel(
                L("关屏只是把背光调到 0，画面仍在渲染——这正是远程/屏幕共享仍能使用的原因。")
                + L("但同样意味着：关屏期间任何能碰到键盘鼠标的人仍可操作这台机器，只是看不见画面。")
                + L("离开座位前请手动锁屏（⌃⌘Q）。"))
        ])))

        let ver = NSTextField(labelWithString: "LidKeep v\(LK_VERSION)  (\(LK_COMMIT))")
        ver.font = .systemFont(ofSize: 11)
        ver.textColor = .tertiaryLabelColor
        let ghBtn = NSButton(title: L("在 GitHub 上查看"), target: self, action: #selector(onOpenGitHub(_:)))
        stack.addArrangedSubview(group(L("关于"), stackOf([ver, ghBtn])))

        return scrollable(stack)
    }

    // MARK: 构建辅助
    private func tabItem(_ label: String, _ view: NSView) -> NSTabViewItem {
        let it = NSTabViewItem(identifier: label as NSString)
        it.label = label
        it.view = view
        return it
    }
    private func column() -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 16
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
    private func stackOf(_ views: [NSView]) -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        for v in views { s.addArrangedSubview(v) }
        return s
    }
    /// 分组：小节标题放在盒外（13pt 半粗、主色），内容装进圆角填充卡片。
    /// 这是 macOS 系统设置（Ventura 起）的分组观感——默认 NSBox 把标题以 11pt 灰字
    /// 嵌进边框缺口，和卡片内的 11pt 说明文字几乎同一视觉重量，扫视时抓不到重点。
    private func group(_ title: String, _ content: NSStackView) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.fillColor = NSColor.systemGray.withAlphaComponent(0.18)  // 深/浅主题下都比背景深一档，但不抢内容
        box.borderWidth = 0
        box.cornerRadius = 10
        box.contentViewMargins = NSSize(width: 14, height: 12)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            content.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            content.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])

        let s = NSStackView(views: [header, box])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        s.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true
        return s
    }
    /// 可滚动容器。内容比可视区高时出现滚动条，比可视区矮时钉在顶部（靠 FlippedView）。
    private func scrollable(_ stack: NSStackView) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.autoresizingMask = [.width, .height]
        let holder = FlippedView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(stack)
        sv.documentView = holder
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: holder.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -16),
            // 文档视图宽度跟随可视区：分组盒才能撑满整列
            holder.widthAnchor.constraint(equalTo: sv.contentView.widthAnchor)
        ])
        // 所有分组等宽——扫视时左缘成一条线，而不是各自缩成一团
        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return sv
    }
    /// 换行标签。只设 preferredMaxLayoutWidth，不锁死宽度，
    /// 让它在分组盒里自然撑开（锁死宽度时窗口缩放会露馅）。
    private func wrapLabel(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        // 宽度必须显式钉死：只给 preferredMaxLayoutWidth 时，NSBox 里的高度
        // 按这个宽度算、实际宽度却由盒子决定，两者不一致就会把最后一行裁掉。
        l.preferredMaxLayoutWidth = 440
        l.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return l
    }
    /// 把说明文字缩进到与选项标题对齐（选项文字本身是从圆圈之后开始的）
    private func indent(_ view: NSView) -> NSStackView {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 0
        let pad = NSView()
        pad.widthAnchor.constraint(equalToConstant: 20).isActive = true
        s.addArrangedSubview(pad); s.addArrangedSubview(view)
        return s
    }
    /// 左标签 + 右控件。标签定宽右对齐，控件左对齐——扫视时控件成一条线。
    private func formRow(_ label: String, _ view: NSView) -> NSStackView {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 12
        s.alignment = .firstBaseline
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .labelColor
        l.widthAnchor.constraint(equalToConstant: 66).isActive = true
        l.alignment = .right
        s.addArrangedSubview(l)
        s.addArrangedSubview(view)
        return s
    }

    // MARK: 同步
    func syncFromConfig() {
        cfg = ctl.cfg
        hkEnableBtn?.state = cfg.hotkeyEnabled ? .on : .off
        hkRecorder?.displayText = hotkeyText(cfg)
        hkRecorder?.isEnabled = cfg.hotkeyEnabled
        timeoutPop?.selectItem(at: timeoutChoices.firstIndex { $0.1 == cfg.timeout }
                              ?? timeoutChoices.firstIndex { $0.1 == 43200 }!)

        let floor = cfg.batteryFloor
        battSlider?.intValue = Int32(floor)
        battValueLabel?.stringValue = floor == 0 ? L("不限制") : "\(floor)%"
        let action = BatteryAction(rawValue: cfg.batteryAction) ?? .restoreOnly
        for b in battActionBtns { b.state = (b.tag == action.rawValue) ? .on : .off }

        let fixed = cfg.restoreFixed
        restorePop?.selectItem(at: fixed == nil ? 0 : 1)
        restoreSlider?.isEnabled = fixed != nil
        restoreSlider?.doubleValue = Double((fixed ?? 0.5) * 100)
        restoreValueLabel?.stringValue = "\(Int(restoreSlider?.doubleValue ?? 50))%"
        loginBtn?.state = isLoginItemEnabled() ? .on : .off
        autoUpdateBtn?.state = cfg.autoCheckUpdate ? .on : .off
        syncNosleep()
        // 电源方案：两套各自回显。「当前生效」标出此刻按哪一套在跑，
        // 避免用户改了「使用电池」却在接电状态下看不到任何变化、以为没生效。
        acKeepBtn?.state = cfg.planAC.keepAwake ? .on : .off
        acDispBtn?.state = cfg.planAC.displayOn ? .on : .off
        acLidPop?.selectItem(at: LidAction.allCases.firstIndex(of: cfg.planAC.lid) ?? 0)
        battKeepBtn?.state = cfg.planBattery.keepAwake ? .on : .off
        battDispBtn?.state = cfg.planBattery.displayOn ? .on : .off
        battLidPop?.selectItem(at: LidAction.allCases.firstIndex(of: cfg.planBattery.lid) ?? 0)
        let onBat = onBatteryNow()
        let curPlan = onBat ? cfg.planBattery : cfg.planAC
        var sum = L("当前：") + powerSourceTitle(battery: onBat) + L(" —— ") + curPlan.summary
        // 与菜单栏标题同一口径：方案要求合盖不睡却没生效时必须显式说明。
        // 这里用短版「未生效」——摘要行是单行 label，写全「合盖不睡未生效」
        // 在三项全开时会顶到卡边缘被截断（宽度实测约 500px，可用只有 ~496px）。
        if curPlan.lid == .nothing && !ctl.lidOn { sum += L("（未生效）") }
        // 同一口径：「息屏后保持唤醒」也有装不上断言的时候（电量低于下限），
        // 用了比菜单更短的措辞，避免与上一个标记叠加后顶到卡边缘被截断
        if curPlan.keepAwake && !ctl.systemSleepBlocked { sum += L("（息屏唤醒未生效）") }
        // 同一口径：「保持屏幕常亮」同样会被电量下限拦下（见 startKeepDisplayOn），
        // 此时勾选框仍是打开的——不标注就等于面板在说谎
        if curPlan.displayOn && !ctl.keepDisplayOnActive { sum += L("（常亮未生效）") }
        planSummaryLabel?.stringValue = sum
        // 文案在 1 行与 2 行之间变化（英文长句会折行），必须让 label 重算固有高度，
        // 否则折行后仍按一行的高度排版，最后一行被裁掉
        planSummaryLabel?.invalidateIntrinsicContentSize()
        lidBlackoutBtn?.state = cfg.lidBlackout ? .on : .off
        // 熄屏由合盖守护执行，守护没开时这一项无从生效——禁用，避免「勾了却没反应」
        lidBlackoutBtn?.isEnabled = ctl.lidOn
        refreshPerm()
    }

    /// 提权助手状态。助手是「系统级防睡眠 / 合盖运行」的前提，必须让用户看得见当前能力边界。
    private func syncNosleep() {
        if helperInstalled() {
            helperBtn.title = L("卸载提权助手")
            // 过旧的助手缺少「多持有者记账」：关屏联动与手动防睡眠会互相踩掉对方的设置
            helperLabel.stringValue = helperOutdated()
                ? L("提权助手：版本过旧 —— 缺少多持有者记账，关屏联动与手动防睡眠会互相关掉对方。")
                  + L("请卸载后重新安装（需要输入一次登录密码）。")
                : L("提权助手：已安装 —— 防睡眠可覆盖电池供电与合盖。") +
                  L("（仅授权单个 root:wheel 脚本的四个固定参数）")
        } else {
            helperBtn.title = L("安装提权助手…")
            helperLabel.stringValue = L("提权助手：未安装 —— 此时防睡眠仅在本机接电源时有效，") +
                L("电池供电与合盖仍会睡眠。安装需输入登录密码，只授权一个脚本的四个固定参数。")
        }
        helperLabel.needsLayout = true
    }

    /// 一套电源方案的三行 UI。三项互不排斥，可任意组合：
    /// 前两项一个管系统睡眠、一个管显示器睡眠，合盖行为独立于两者。
    private func planRows(keep: inout NSButton!, disp: inout NSButton!,
                          lid: inout NSPopUpButton!, ac: Bool) -> NSStackView {
        let tag = ac ? 0 : 1
        keep = NSButton(checkboxWithTitle: L("息屏后保持唤醒"), target: self, action: #selector(onPlanToggled(_:)))
        keep.tag = tag; keep.font = .systemFont(ofSize: 13)
        disp = NSButton(checkboxWithTitle: L("保持屏幕常亮"), target: self, action: #selector(onPlanToggled(_:)))
        disp.tag = tag; disp.font = .systemFont(ofSize: 13)
        lid = NSPopUpButton(frame: .zero, pullsDown: false)
        lid.addItems(withTitles: LidAction.allCases.map { $0.title })
        lid.target = self; lid.action = #selector(onPlanLidChanged(_:))
        lid.tag = tag
        return stackOf([
            keep,
            indent(wrapLabel(L("屏幕照常熄灭，但系统不睡 —— 息屏期间远程桌面仍能连上"))),
            disp,
            indent(wrapLabel(L("显示器不熄、系统也不睡；屏幕一直亮着，较耗电"))),
            formRow(L("合盖时"), lid),
            indent(wrapLabel(ac ? L("接着电源时合盖常开，选「保持唤醒」即可。")
                             : L("用电池时建议保持「睡眠」，免得合上就在包里一直耗电。")))
        ])
    }

    /// 复选项改动：tag 0 = 接通电源，1 = 使用电池
    @objc private func onPlanToggled(_ sender: NSButton) {
        let on = sender.state == .on
        if sender.tag == 0 {
            if sender === acKeepBtn { cfg.planAC.keepAwake = on } else { cfg.planAC.displayOn = on }
        } else {
            if sender === battKeepBtn { cfg.planBattery.keepAwake = on } else { cfg.planBattery.displayOn = on }
        }
        commitPlansFromUI()
    }

    /// 「合盖时」弹窗：睡眠 / 保持唤醒
    @objc private func onPlanLidChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let a: LidAction = (idx >= 0 && idx < LidAction.allCases.count) ? LidAction.allCases[idx] : .sleep
        if sender.tag == 0 { cfg.planAC.lid = a } else { cfg.planBattery.lid = a }
        commitPlansFromUI()
    }

    /// 面板改动统一走这里：与菜单共用 commitPlans，避免两边逻辑漂移
    private func commitPlansFromUI() {
        _ = commitPlans((ac: cfg.planAC, battery: cfg.planBattery))
        cfg = ctl.cfg
        syncFromConfig()
    }

    /// 「合盖时熄灭内屏」。守护在启动时读一次该开关决定要不要熄屏，
    /// 所以改动后必须重启守护；关掉时重启也会顺带把亮度复位，
    /// 否则刚刚熄灭的屏幕会一直黑着。
    @objc private func onLidBlackoutToggled(_ sender: Any?) {
        cfg.lidBlackout = (lidBlackoutBtn.state == .on)
        ctl.cfg = cfg
        commit()
        guard ctl.lidOn else { return }
        _ = ctl.setLidAwake(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if self.ctl.setLidAwake(true) {
                self.cfg = self.ctl.cfg
                self.syncFromConfig()
            } else {
                self.lidBlackoutBtn.state = self.cfg.lidBlackout ? .on : .off
            }
            self.lidBlackoutBtn.isEnabled = self.ctl.lidOn
        }
    }

    /// 调用 CLI 完成提权安装：密码框由系统弹出，App 不接触凭据
    @objc private func onInstallHelper(_ sender: Any?) {
        let cands = ["/opt/homebrew/bin/lidkeep", "/usr/local/bin/lidkeep"]
        guard let cli = cands.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            let a = NSAlert(); a.messageText = L("未找到命令行工具")
            a.informativeText = L("请先在终端安装 lidkeep，或手动执行：\nlidkeep nosleep install-helper")
            a.runModal(); return
        }
        let uninstall = helperInstalled()
        helperBtn.isEnabled = false
        // 密码框会阻塞，必须放到后台线程；否则设置面板会卡住直到用户输入完成
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = ["nosleep", uninstall ? "uninstall-helper" : "install-helper"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            var out = ""
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                out = String(data: data, encoding: .utf8) ?? ""
            } else { out = (L("无法启动 ") + "\(cli)") }
            DispatchQueue.main.async {
                self.helperBtn.isEnabled = true
                self.syncNosleep()
                let a = NSAlert()
                a.messageText = uninstall ? L("卸载提权助手") : L("安装提权助手")
                a.informativeText = out.isEmpty ? L("已完成（无输出）") : out
                a.runModal()
            }
        }
    }
    private func refreshPerm() {
        let c = ctl.cfg
        guard hkEnableBtn.state == .on else {
            hkStatusLabel.stringValue = L("已按设置停用全局热键，仅能从菜单栏点击操作。")
            return
        }
        hkStatusLabel.stringValue = ctl.hotkeyReady
            ? ("\(hotkeyText(c))" + L("：✅ 已注册为系统全局热键"))
            : ("\(hotkeyText(c))" + L("：⚠️ ") + "\(carbonStatusText(ctl.lastHotkeyStatus))" + L("。请换一个组合（建议 ⇧⌘B 或 ⌃⌥⌘B）。"))
    }

    // MARK: 事件
    @objc private func onHotkeyEnabledToggled(_ sender: Any?) {
        cfg.hotkeyEnabled = (hkEnableBtn.state == .on)
        commit()
    }
    @objc private func onHotkeyReset(_ sender: Any?) {
        cfg.modFlags = MOD_CTRL | MOD_ALT | MOD_CMD
        cfg.keyCode = 11
        commit()
    }
    @objc private func onTimeoutChanged(_ sender: Any?) {
        cfg.timeout = timeoutChoices[timeoutPop.indexOfSelectedItem].1
        commit()
    }
    /// 滑块此刻是否正被拖动。
    ///
    /// NSSlider 默认 `isContinuous = true`：拖一次会触发几十次 action，而 `commit()` 要
    /// 写盘 + 注销并重新注册全局热键 + 重建整个面板 —— 全量执行会让拖动明显卡顿，
    /// 且热键在拖动期间被反复注销/注册，中间存在短暂的失效窗口。
    /// 所以拖动中只更新数值回显，松手那一次才落盘。
    ///
    /// 不用 `isContinuous = false` 代替：那样拖动过程中数值回显就不再更新了，
    /// 用户拖到哪一格完全看不见。
    private var isDraggingSlider: Bool {
        guard let e = NSApp.currentEvent else { return false }   // 非鼠标触发（如键盘）→ 直接提交
        return e.type == .leftMouseDown || e.type == .leftMouseDragged
    }

    @objc private func onBatterySliderChanged(_ sender: Any?) {
        cfg.batteryFloor = Int(battSlider.intValue)
        battValueLabel.stringValue = cfg.batteryFloor == 0 ? L("不限制") : "\(cfg.batteryFloor)%"
        guard !isDraggingSlider else { return }
        commit()
    }
    @objc private func onBatteryActionSelected(_ sender: NSButton) {
        cfg.batteryAction = sender.tag
        commit()
    }
    @objc private func onRestoreModeChanged(_ sender: Any?) {
        if restorePop.indexOfSelectedItem == 0 { cfg.restoreFixed = nil }
        else { cfg.restoreFixed = Float(restoreSlider.doubleValue / 100) }
        restoreSlider.isEnabled = cfg.restoreFixed != nil
        commit()
    }
    @objc private func onSliderChanged(_ sender: Any?) {
        restoreValueLabel.stringValue = "\(Int(restoreSlider.doubleValue))%"
        if restorePop.indexOfSelectedItem == 1 { cfg.restoreFixed = Float(restoreSlider.doubleValue / 100) }
        guard !isDraggingSlider else { return }
        commit()
    }
    @objc private func onAutoUpdateToggled(_ sender: Any?) {
        cfg.autoCheckUpdate = (autoUpdateBtn.state == .on)
        commit()
        // 立刻检查一次：让「打开开关」这个动作有即时反馈，而不是等下一个 24h 周期
        AppDelegate.shared?.checkUpdateSilently()
    }
    @objc private func onOpenGitHub(_ sender: Any?) {
        if let u = URL(string: "https://github.com/Hoodas101/lidkeep") {
            NSWorkspace.shared.open(u)
        }
    }
    /// 面板落盘。
    ///
    /// 面板可能开着几十分钟，而 config.json 是与 CLI 共享的：这期间 CLI 完全可能改过方案
    /// 或电量设置。若把面板内存里那份整份回写，那些改动会被静默抹掉。所以先重读磁盘，
    /// 再把**面板自己负责的字段**覆盖上去——面板没管的字段一律以磁盘为准。
    ///
    /// 「面板负责的字段」= 下面逐行列出的这些。刻意**不含** planAC / planBattery / lang：
    /// - 电源方案由 `commitPlansFromUI()`（走 commitPlans）单独负责，从不到这里；
    ///   在这里覆盖的话，反而会把面板内存里的旧方案写回去、盖掉 CLI 刚改的值；
    /// - lang 只由 CLI 与 `LIDKEEP_LANG` 决定，面板没有语言选择器。
    private func commit() {
        var c = loadConfig()
        c.keyCode = cfg.keyCode
        c.modFlags = cfg.modFlags
        c.hotkeyEnabled = cfg.hotkeyEnabled
        c.timeout = cfg.timeout
        c.restoreFixed = cfg.restoreFixed
        c.batteryFloor = cfg.batteryFloor
        c.batteryAction = cfg.batteryAction
        c.lidBlackout = cfg.lidBlackout
        c.autoCheckUpdate = cfg.autoCheckUpdate
        saveConfig(c)
        cfg = c
        ctl.cfg = c
        ctl.reloadHotkey()
        if ctl.blacked { ctl.scheduleTimeout() }
        ctl.scheduleBatteryGuard()
        syncFromConfig()
        AppDelegate.shared?.refreshUI()
    }

    @objc private func onCheck(_ sender: Any?) {
        AppDelegate.shared?.checkHotkey(sender)
        refreshPerm()
    }
    @objc private func onLoginToggled(_ sender: Any?) {
        setLoginItem(loginBtn.state == .on)
        loginBtn.state = isLoginItemEnabled() ? .on : .off
    }

    // MARK: 开机自启
    private var appPath: String {
        Bundle.main.bundlePath.hasSuffix(".app") ? Bundle.main.bundlePath
            : "/Applications/LidKeep.app"
    }

    private func setLoginItem(_ on: Bool) {
        guard on else {
            sh("/bin/launchctl", ["bootout", "gui/\(getuid())/\(barLabel)"])
            try? fm.removeItem(atPath: barPlist)
            blog("bar: 已关闭登录自启")
            return
        }
        let exe = appPath + "/Contents/MacOS/LidKeep"
        guard fm.fileExists(atPath: exe) else { return }
        let plist = loginItemPlist()
        try? plist.write(toFile: barPlist, atomically: true, encoding: .utf8)
        let gui = "gui/\(getuid())"
        sh("/bin/launchctl", ["bootout", "\(gui)/\(barLabel)"])
        let r = sh("/bin/launchctl", ["bootstrap", gui, barPlist])
        if r != 0 { sh("/bin/launchctl", ["load", "-w", barPlist]) }
        sh("/bin/launchctl", ["kickstart", "-k", "\(gui)/\(barLabel)"])
        if r != 0 {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = L("已写入配置，但未能注册到 launchd")
            a.informativeText = (L("请在「终端」中执行：\n\nlaunchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/") + "\(barLabel)" + L(".plist\n\n或在系统设置的「登录项」里手动添加 ") + "\(appPath)")
            a.addButton(withTitle: L("好"))
            a.runModal()
        }
        blog("bar: 登录自启 -> \(on)")
    }
}

// sh() / runCapture() 见 Sources/Shared/SystemState.swift

// MARK: - 菜单栏
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var toggleItem: NSMenuItem!
    private var modeItem: NSMenuItem!
    private var keepAwakeItem: NSMenuItem!       // 息屏后保持唤醒
    private var displayOnItem: NSMenuItem!       // 保持屏幕常亮
    private var lidItem: NSMenuItem!             // 合盖时（子菜单二选一）
    private var lidItems: [LidAction: NSMenuItem] = [:]
    private var lidRetryItem: NSMenuItem!        // 合盖不睡未生效时的「重试」入口
    private var setupItem: NSMenuItem!
    private var stateItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var permItem: NSMenuItem!
    private var hotkeyUnavailable = false
    private let ctl = ScreenController.shared
    private var settings: SettingsPanel?
    // 开源项目地址（检查更新 / 关于 / 跳转共用同一来源）
    private let repoURL = "https://github.com/Hoodas101/lidkeep"
    private let releasesURL = "https://github.com/Hoodas101/lidkeep/releases"
    private let latestAPI = "https://api.github.com/repos/Hoodas101/lidkeep/releases/latest"
    // 自动检查更新：后台静默轮询，发现新版只在菜单栏提示，不弹窗打断
    private var updateItem: NSMenuItem!
    private var updateSep: NSMenuItem!
    private var newVersion: String?          // 已知有新版、用户尚未处理
    private var newVersionURL: String?
    private var updateTimer: Timer?
    /// 自动检查的最小间隔。手动点「检查更新…」不受此限。
    private let autoCheckInterval: TimeInterval = 24 * 3600

    func applicationDidFinishLaunching(_ a: Notification) {
        AppDelegate.shared = self
        ctl.start()
        ctl.onStateChange = { [weak self] in self?.refreshUI() }
        // 外部改了 config.json：菜单要重画，已打开的设置面板也要换掉它的编辑副本
        ctl.onConfigReloaded = { [weak self] in
            self?.refreshUI()
            self?.settings?.refreshIfVisible()
        }

        // 用 variableLength 以便无授权时在图标旁显示警示标记
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = icon(blacked: false)
            b.image?.isTemplate = true
            b.toolTip = L("LidKeep —— 点击打开菜单")
        }
        menu = buildMenu()
        menu.delegate = self
        // 交给 AppKit 原生弹出菜单（左键/右键都弹），点击不再直接开关显示器
        statusItem.menu = menu
        // 热键走 Carbon 链路，不依赖辅助功能授权；这里只反映注册结果
        hotkeyUnavailable = ctl.cfg.hotkeyEnabled && !ctl.hotkeyReady
        refreshUI()

        // 自动检查更新：启动 20 秒后先来一次（避开启动瞬间的磁盘/网络争用），此后每 6 小时
        // 复核一次。真正决定是否发请求的是 maybeAutoCheckUpdate() 里的 24h 节流闸门。
        Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.maybeAutoCheckUpdate()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.maybeAutoCheckUpdate()
        }

        // 调试用：构建设置面板并打印布局树，验证无零尺寸 / 越界后自动退出
        // 顺带把菜单每一项的**实际文案**写进日志：菜单栏那一行是用户唯一常驻的界面，
        // 措辞/勾选/隐藏状态只靠读代码是验证不了的（曾经出现过「菜单上写着某个开关、
        // 实际点开根本不是那回事」）。这里给出一个可被脚本核对的落点。
        if CommandLine.arguments.contains("--uitest") {
            blog("bar: uitest 菜单文案 —— \(menuDump())")
            openSettings(nil)
            Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                if let w = NSApp.windows.first(where: { $0.title == L("LidKeep 设置") }) {
                    blog("bar: uitest 窗口 frame=\(w.frame)")
                    Self.dumpView(w.contentView!, depth: 0)
                } else { blog("bar: uitest 未找到设置窗口") }
                blog("bar: uitest 完成")
                exit(0)
            }
        }
        // 调试用：自动跑一次热键自检，结果写入日志后退出（不影响屏幕状态）
        if CommandLine.arguments.contains("--selftest") {
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.ctl.selfTest { ok in
                    blog("bar: selftest 结果=\(ok ? "通过" : "未通过")")
                    exit(0)
                }
            }
        }
    }

    private func icon(blacked: Bool) -> NSImage? {
        let name = blacked ? "moon.fill" : "sun.max.fill"
        // 显式定字号字重：SF Symbol 默认渲染在菜单栏里偏细、与其他图标视觉重量不一致
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return base.withSymbolConfiguration(cfg)
        }
        return NSImage(systemSymbolName: "display", accessibilityDescription: nil)
    }

    // MARK: 菜单
    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        // 发现新版本时的置顶提醒（默认隐藏）。不弹窗：菜单栏工具打断用户代价太高，
        // 徽标 + 置顶条目足以被看见，且不会在用户忙时抢焦点。
        updateItem = NSMenuItem(title: "", action: #selector(openPendingUpdate(_:)), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        m.addItem(updateItem)
        updateSep = .separator()
        updateSep.isHidden = true
        m.addItem(updateSep)
        // MARK: 三个核心功能，表述一一对应：
        //   ① 关闭显示器 —— 立即黑屏（机器保持运行）
        //   ② 息屏时不睡眠 —— 每次息屏/关屏期间自动阻止系统睡眠
        //   ③ 合盖后不睡眠 —— 合盖也持续运行（长期模式，重启自动恢复）
        stateItem = NSMenuItem(title: L("○ 屏幕正常"), action: nil, keyEquivalent: "")
        m.addItem(stateItem)
        m.addItem(.separator())
        toggleItem = NSMenuItem(title: L("关闭显示器"), action: #selector(toggle(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.toolTip = L("立即熄灭屏幕，机器保持运行；再点一次（或按热键）恢复")
        m.addItem(toggleItem)
        // 电源方案：三个互不排斥的开关 + 合盖行为二选一。
        // 改的是「当前电源来源」对应的那套——接电时改的就是接电方案。
        // 标题由 planStatusTitle 生成（与 refreshUI 同一来源），刷新时再补上「未生效」标记。
        modeItem = NSMenuItem(title: planStatusTitle(activePlan(ctl.cfg), battery: onBatteryNow()),
                              action: nil, keyEquivalent: "")
        let sub = NSMenu()
        // 只在「方案要求合盖不睡、守护却没起来」时出现的补救入口。
        // 巡检有 5 分钟退避，用户刚装好助手不该干等——给一个立即重试的手动通道。
        lidRetryItem = NSMenuItem(title: L("重试启用「合盖不睡」"), action: #selector(retryLidDaemon(_:)), keyEquivalent: "")
        lidRetryItem.target = self
        lidRetryItem.isHidden = true
        sub.addItem(lidRetryItem)
        sub.addItem(.separator())
        keepAwakeItem = NSMenuItem(title: L("息屏后保持唤醒"), action: #selector(toggleKeepAwake(_:)), keyEquivalent: "")
        keepAwakeItem.target = self
        keepAwakeItem.toolTip = L("屏幕照常熄灭，但系统不睡 —— 息屏期间远程桌面仍能连上")
        sub.addItem(keepAwakeItem)
        displayOnItem = NSMenuItem(title: L("保持屏幕常亮"), action: #selector(toggleDisplayOn(_:)), keyEquivalent: "")
        displayOnItem.target = self
        displayOnItem.toolTip = L("显示器不熄、系统也不睡；屏幕一直亮着，较耗电")
        sub.addItem(displayOnItem)
        lidItem = NSMenuItem(title: L("合盖时"), action: nil, keyEquivalent: "")
        let lidSub = NSMenu()
        for a in LidAction.allCases {
            let it = NSMenuItem(title: a.title, action: #selector(selectLidAction(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = a.rawValue
            it.toolTip = a.cost
            lidSub.addItem(it)
            lidItems[a] = it
        }
        lidItem.submenu = lidSub
        sub.addItem(lidItem)
        sub.addItem(.separator())
        let editOther = NSMenuItem(title: L("编辑另一套方案…"), action: #selector(openSettings(_:)), keyEquivalent: "")
        editOther.target = self
        sub.addItem(editOther)
        modeItem.submenu = sub
        modeItem.toolTip = L("按「接通电源 / 使用电池」分别设置，三项可同时开启")
        m.addItem(modeItem)
        // 首次使用装一次提权助手（弹系统密码框）；装好后此入口隐藏（设置面板仍可卸载）。
        setupItem = NSMenuItem(title: L("安装提权助手（首次使用）…"), action: #selector(runSetup(_:)), keyEquivalent: "")
        setupItem.target = self
        setupItem.toolTip = L("让「息屏时不睡眠」「合盖后不睡眠」覆盖电池与合盖（需 root，弹一次密码框）")
        m.addItem(setupItem)
        m.addItem(.separator())
        let set = NSMenuItem(title: L("设置…"), action: #selector(openSettings(_:)), keyEquivalent: ",")
        set.target = self; m.addItem(set)
        let chk = NSMenuItem(title: L("热键自检"), action: #selector(checkHotkey(_:)), keyEquivalent: "")
        chk.target = self; m.addItem(chk)
        permItem = NSMenuItem(title: "", action: #selector(openAuthorizeFromMenu(_:)), keyEquivalent: "")
        permItem.target = self; m.addItem(permItem)
        m.addItem(.separator())
        loginItem = NSMenuItem(title: L("登录时启动"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self; m.addItem(loginItem)
        let log = NSMenuItem(title: L("打开日志"), action: #selector(openLog(_:)), keyEquivalent: "")
        log.target = self; m.addItem(log)
        m.addItem(.separator())
        let upd = NSMenuItem(title: L("检查更新…"), action: #selector(checkUpdate(_:)), keyEquivalent: "")
        upd.target = self; m.addItem(upd)
        let about = NSMenuItem(title: L("关于 LidKeep"), action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self; m.addItem(about)
        let gh = NSMenuItem(title: L("在 GitHub 上查看"), action: #selector(openGitHub(_:)), keyEquivalent: "")
        gh.target = self; m.addItem(gh)
        m.addItem(.separator())
        let q = NSMenuItem(title: L("退出"), action: #selector(quit(_:)), keyEquivalent: "q")
        q.target = self; m.addItem(q)
        return m
    }

    func refreshUI() {
        let blacked = ctl.blacked
        statusItem.button?.image = icon(blacked: blacked)
        statusItem.button?.image?.isTemplate = true
        // 菜单栏徽标：快捷键异常优先于「有新版本」——前者会直接影响使用
        statusItem.button?.title = hotkeyUnavailable ? "⚠" : (newVersion != nil ? "⬆" : "")
        statusItem.button?.toolTip = hotkeyUnavailable
            ? (L("LidKeep —— 快捷键未生效：") + "\(carbonStatusText(ctl.lastHotkeyStatus))")
            : (L("LidKeep —— 快捷键 ") + "\(hotkeyText(ctl.cfg))" + L("，点击打开菜单"))
        stateItem.title = blacked ? L("● 屏幕已关闭 · 机器运行中") : L("○ 屏幕正常")
        toggleItem.title = blacked ? (L("恢复显示器  ") + "\(hotkeyText(ctl.cfg))") : (L("关闭显示器  ") + "\(hotkeyText(ctl.cfg))")
        // 电源方案：父项只写一行短状态（例：「状态：电源保持唤醒」），子项按当前那套方案打勾。
        // 旧写法把「电源来源 + 三项摘要 + 生效范围」全串进标题，三项全开时长达 40 余字，
        // 在菜单里被截成读不完的残句 —— 等于什么都没说。逐项明细就在子菜单里（带勾选），
        // 不必也不该挤在标题上。下面的「未生效」标记只在异常态才追加：正常时它就很短。
        let onBat = onBatteryNow()
        let plan = activePlan(ctl.cfg)
        var modeTitle = planStatusTitle(plan, battery: onBat)
        if plan.lid == .nothing && !ctl.lidOn {
            // 方案要合盖不睡、守护却没在跑：必须在这里说清楚。
            // 菜单是用户唯一的常驻视图，标题说「合盖不睡」而机器实际会睡，
            // 就是最典型的那种「UI 说一套、机器做一套」。
            modeTitle += L("（合盖不睡未生效）")
        }
        if plan.keepAwake && !ctl.systemSleepBlocked {
            // 同一条原则：方案要「息屏后保持唤醒」、断言却没持有（多半是电量低于下限），
            // 菜单上不说清楚，用户就会以为设置生效着，机器却在包里睡着了。
            modeTitle += L("（息屏保持唤醒未生效）")
        }
        if blacked && ctl.nosleepOn {
            modeTitle += ctl.nosleepSystemOn ? L("（已生效 · 系统级）") : L("（已生效 · 仅接电源）")
        }
        modeItem.title = modeTitle
        keepAwakeItem.state = plan.keepAwake ? .on : .off
        displayOnItem.state = plan.displayOn ? .on : .off
        lidItem.title = L("合盖时：") + plan.lid.title
        for (a, it) in lidItems { it.state = (a == plan.lid) ? .on : .off }
        lidRetryItem?.isHidden = !(plan.lid == .nothing && !ctl.lidOn)
        setupItem.isHidden = helperInstalled()
        loginItem?.state = isLoginItemEnabled() ? .on : .off
        if hotkeyUnavailable {
            permItem.title = L("⚠️ 快捷键未生效 —— 点击排查")
            permItem.isHidden = false
        } else {
            permItem.isHidden = true
        }
        if let v = newVersion {
            updateItem.title = L("⬆ 有新版本 ") + "v\(v)" + L(" —— 打开发布页")
            updateItem.isHidden = false
            updateSep.isHidden = false
        } else {
            updateItem.isHidden = true
            updateSep.isHidden = true
        }
    }

    /// 热键注册失败时（多为组合被系统占用），每次打开菜单重试一次
    func ensureHotkey() {
        guard !ctl.hotkeyReady else { return }
        ctl.installHotkey()
        hotkeyUnavailable = ctl.cfg.hotkeyEnabled && !ctl.hotkeyReady
        refreshUI()
    }
    func menuWillOpen(_ menu: NSMenu) { ensureHotkey() }

    /// 一键防睡眠：调 CLI `nosleep setup`（装助手弹系统密码框 + 开联动 + 立即防睡眠）
    @objc private func runSetup(_ sender: Any?) {
        let cands = ["/opt/homebrew/bin/lidkeep", "/usr/local/bin/lidkeep"]
        guard let cli = cands.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            let a = NSAlert(); a.messageText = L("未找到命令行工具")
            a.informativeText = L("请先安装 lidkeep 命令行工具（.pkg 安装包已包含）。")
            a.runModal(); return
        }
        setupItem.isEnabled = false
        // 密码框会阻塞，必须放后台线程，否则菜单会卡住直到用户输入完成
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = ["nosleep", "setup"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            var out = ""
            if (try? p.run()) != nil {
                out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            } else { out = (L("无法启动 ") + "\(cli)") }
            DispatchQueue.main.async {
                self.setupItem.isEnabled = true
                self.refreshUI()
                let a = NSAlert()
                a.messageText = L("一键防睡眠")
                a.informativeText = out.isEmpty ? L("已完成") : out
                a.runModal()
            }
        }
    }

    /// 菜单实际文案（调试用，见 --uitest）。把标题、勾选、隐藏状态一次摊平，
    /// 便于用脚本核对「菜单上写的就是实际生效的」。
    private func menuDump() -> String {
        var parts: [String] = []
        func walk(_ m: NSMenu, _ prefix: String) {
            for it in m.items where !it.isSeparatorItem && !it.isHidden {
                let mark = it.state == .on ? "[✓] " : (it.state == .off ? "[ ] " : "")
                parts.append("\(prefix)\(mark)\(it.title)")
                if let sub = it.submenu { walk(sub, prefix + "→") }
            }
        }
        walk(menu, "")
        return parts.joined(separator: " | ")
    }

    static func dumpView(_ v: NSView, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        blog("\(pad)\(type(of: v)) frame=\(v.frame)")
        for sub in v.subviews { dumpView(sub, depth: depth + 1) }
    }

    /// 菜单弹出前刷新状态（menuWillOpen 已负责重试热键监听）
    @objc func menuNeedsUpdate(_ menu: NSMenu) { refreshUI() }
    @objc private func toggle(_ sender: Any?) { ctl.toggle() }

    // MARK: 电源方案（三项可叠加）
    //
    // 改的始终是「当前电源来源」对应的那套方案。三项互不排斥：
    // 息屏保持唤醒管系统睡眠、屏幕常亮管显示器睡眠、合盖行为管合盖动作——
    // 三件不同的事，本来就该能同时设置（Windows 的电源选项也是这么分的）。
    private func currentPlans() -> (ac: PowerPlan, battery: PowerPlan) {
        let c = loadConfig()
        return (c.planAC, c.planBattery)
    }
    @objc private func toggleKeepAwake(_ sender: Any?) {
        var plans = currentPlans()
        let isBat = onBatteryNow()
        if isBat { plans.battery.keepAwake.toggle() } else { plans.ac.keepAwake.toggle() }
        let turningOn = isBat ? plans.battery.keepAwake : plans.ac.keepAwake
        _ = commitPlans(plans)
        // commitPlans 已经通过 syncKeepAwake 装好断言，这里只负责在**装不上**时说明原因：
        // 点了开关却毫无变化（多半是电量低于下限），不说清楚观感就是「开关坏了」。
        if turningOn && !ctl.systemSleepBlocked { ctl.startKeepAwakeAssertion(notifyOnBlock: true) }
        refreshUI()
    }
    @objc private func toggleDisplayOn(_ sender: Any?) {
        var plans = currentPlans()
        if onBatteryNow() { plans.battery.displayOn.toggle() } else { plans.ac.displayOn.toggle() }
        _ = commitPlans(plans)
        refreshUI()
    }
    @objc private func selectLidAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let a = LidAction(rawValue: raw) else { return }
        var plans = currentPlans()
        if onBatteryNow() { plans.battery.lid = a } else { plans.ac.lid = a }
        let ok = commitPlans(plans)
        // 明确选了「保持唤醒」却没起来，最常见的成因就是缺提权助手。
        // 只在菜单栏留一句「未生效」等于把人丢在半路——这里补一个安装出口。
        // 电量不足不弹窗：那是用户自己清楚的状态，插上电巡检会自动补起。
        if a == .nothing, !ok, !helperInstalled() { promptInstallHelper() }
        refreshUI()
    }

    /// 缺提权助手时的图形化引导。
    ///
    /// 安装是异步的（`nosleep setup` 会弹系统密码框，在后台线程跑），所以这里
    /// **不**抢着在安装返回后立刻复查 `helperInstalled()` —— 那一刻安装往往还没结束，
    /// 复查必然拿到 false，于是要么白提示一次要么误判失败（旧实现在这里踩过）。
    /// 方案早已随 commitPlans 落盘，装好后周期巡检会在 15 秒内自动把守护补起来。
    private func promptInstallHelper() {
        let alert = NSAlert()
        alert.messageText = L("「合盖后不睡眠」需要提权助手")
        alert.informativeText = L("合盖会触发系统级睡眠，只有 root 权限的 pmset 能阻止它。") +
            L("点击「一键防睡眠」安装（弹一次系统密码框，仅授权单个脚本的固定参数）。") +
            L("装好后「合盖不睡」会自动生效，无需再点。")
        alert.addButton(withTitle: L("一键安装并开启"))
        alert.addButton(withTitle: L("取消"))
        if alert.runModal() == .alertFirstButtonReturn { runSetup(nil) }
    }

    /// 手动重试启用合盖不睡（绕过巡检的失败退避）。
    /// 场景：用户刚装好提权助手，不想等下一次巡检。
    /// 失败要说清卡在哪一步——「点了没反应」比报错更让人困惑。
    @objc private func retryLidDaemon(_ sender: Any?) {
        let ok = ctl.reconcileLidDaemon(want: true, why: "菜单手动重试", force: true)
        if ok {
            notifyUser(L("「合盖不睡」已生效。"))
        } else if !helperInstalled() {
            promptInstallHelper()
        } else {
            notifyUser(L("「合盖不睡」未能生效：") +
                       L("可能原因：电池电量低于下限 / 守护启动未确认。\n详见「打开日志」。"))
        }
        refreshUI()
    }

    @objc private func openSettings(_ sender: Any?) {
        if settings == nil { settings = SettingsPanel() }
        settings?.show()
    }
    @objc func checkHotkey(_ sender: Any?) {
        ensureHotkey()
        guard ctl.hotkeyReady else {
            let a = NSAlert(); a.alertStyle = .warning
            a.messageText = L("快捷键未生效")
            a.informativeText = ("\(hotkeyText(ctl.cfg))" + L("：") + "\(carbonStatusText(ctl.lastHotkeyStatus))" + L("。\n\n本程序使用系统级全局热键，不需要「辅助功能 / 输入监控」授权。若组合被其他 App 占用，请在设置里换一个。"))
            a.addButton(withTitle: L("好")); a.runModal(); return
        }
        statusItem.button?.title = "⏳"
        ctl.selfTest { [weak self] ok in
            DispatchQueue.main.async {
                self?.hotkeyUnavailable = (self?.ctl.cfg.hotkeyEnabled ?? true) && !(self?.ctl.hotkeyReady ?? false)
                self?.refreshUI()
                let a = NSAlert()
                a.alertStyle = ok ? .informational : .warning
                a.messageText = ok ? L("热键可用") : L("热键未响应")
                a.informativeText = ok
                    ? (L("已确认系统把 ") + "\(hotkeyText(self?.ctl.cfg ?? Config()))" + L(" 投递给了本程序，可直接开关显示。"))
                    : (L("自检未收到 ") + "\(hotkeyText(self?.ctl.cfg ?? Config()))" + L("。\n\n可能原因：① 该组合被其他 App 抢先接管，换一个组合再试；② 本程序刚重装，系统热键表尚未刷新，退出重开一次。"))
                a.addButton(withTitle: L("好")); a.runModal()
            }
        }
    }
    @objc private func toggleLogin(_ sender: Any?) {
        let on = !(loginItem.state == .on)
        let exe = Bundle.main.bundlePath + "/Contents/MacOS/LidKeep"
        guard fm.fileExists(atPath: exe) else { return }
        let plist = loginItemPlist()
        if on {
            try? plist.write(toFile: barPlist, atomically: true, encoding: .utf8)
            let gui = "gui/\(getuid())"
            sh("/bin/launchctl", ["bootout", "\(gui)/\(barLabel)"])
            var r = sh("/bin/launchctl", ["bootstrap", gui, barPlist])
            if r != 0 { r = sh("/bin/launchctl", ["load", "-w", barPlist]) }
            if r != 0 {
                let a = NSAlert(); a.alertStyle = .warning
                a.messageText = L("已写入配置，但未能注册 launchd")
                a.informativeText = (L("请在终端执行：\nlaunchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/") + "\(barLabel)" + ".plist")
                a.addButton(withTitle: L("好")); a.runModal()
            }
        } else {
            sh("/bin/launchctl", ["bootout", "gui/\(getuid())/\(barLabel)"])
            try? fm.removeItem(atPath: barPlist)
        }
        refreshUI()
    }
    @objc private func openLog(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
    @objc private func quit(_ sender: Any?) { ctl.shutdown() }

    // MARK: 关于 / 检查更新 / 跳转开源仓库

    /// 打开开源仓库主页
    @objc private func openGitHub(_ sender: Any?) {
        guard let u = URL(string: repoURL) else { return }
        NSWorkspace.shared.open(u)
    }

    /// 软件详情：版本 / commit / 描述 / 许可证 / 仓库，并内置跳转按钮
    @objc private func showAbout(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "LidKeep"
        let lines = [
            L("关屏但不睡眠，合盖继续运行。"),
            "",
            L("版本") + ": \(LK_VERSION) (\(LK_COMMIT))",
            L("许可证") + ": MIT",
            L("开源仓库") + ": github.com/Hoodas101/lidkeep",
        ]
        a.informativeText = lines.joined(separator: "\n")
        a.addButton(withTitle: L("在 GitHub 上查看"))
        a.addButton(withTitle: L("好"))
        if a.runModal() == .alertFirstButtonReturn {
            openGitHub(nil)
        }
    }

    /// 检查更新：拉取 GitHub Releases 的最新 tag，与本机版本比较
    @objc private func checkUpdate(_ sender: Any?) {
        fetchLatestVersion { [weak self] latest, html, error in
            guard let self = self else { return }
            guard let latest = latest else {
                self.reportUpdateFailure(message: error ?? L("无法解析更新信息"))
                return
            }
            if self.isVersion(latest, newerThan: LK_VERSION) {
                self.reportUpdateAvailable(latest: latest, html: html)
            } else {
                self.reportUpdateUpToDate()
            }
        }
    }

    /// 拉取最新版本：成功回 (版本号, 发布页 URL, nil)，失败回 (nil, nil, 原因)。
    /// 手动检查与后台自动检查共用这一处，避免两份请求逻辑各自演化。
    private func fetchLatestVersion(completion: @escaping (String?, String?, String?) -> Void) {
        guard let url = URL(string: latestAPI) else {
            completion(nil, nil, L("发布页地址无效")); return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        // GitHub API 对未带 User-Agent 的请求会返回 403，必须设置
        req.setValue("LidKeep", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err = err { completion(nil, nil, err.localizedDescription); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    completion(nil, nil, L("无法解析更新信息")); return
                }
                completion(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                           json["html_url"] as? String, nil)
            }
        }.resume()
    }

    /// 自动检查的节流闸门：开关关闭、或距上次**成功**检查不足 24h 时直接返回。
    private func maybeAutoCheckUpdate() {
        let c = ctl.cfg
        guard c.autoCheckUpdate else { return }
        guard Date().timeIntervalSince1970 - c.lastUpdateCheckAt >= autoCheckInterval else { return }
        checkUpdateSilently()
    }

    /// 静默检查一次（只记状态、不弹窗）。开关刚打开时也调它，让动作有即时反馈。
    /// 时间戳只在**成功**后落盘：失败留给下一个 6h 心跳重试，否则离线一次就整天不再检查。
    func checkUpdateSilently() {
        fetchLatestVersion { [weak self] latest, html, error in
            guard let self = self else { return }
            // 后台功能最怕静默失败：三个分支各留一条日志，事后能查
            guard let latest = latest else {
                blog("bar: 自动检查更新 失败：\(error ?? L("无法解析更新信息"))")
                return
            }
            // 网络请求回来时可能已过好几秒，这期间 CLI 可能改过配置。
            // 回写内存里那份快照会把对方的改动一起抹掉，所以只重读后改这一个时间戳。
            updateConfig { $0.lastUpdateCheckAt = Date().timeIntervalSince1970 }
            self.ctl.cfg = loadConfig()
            guard self.isVersion(latest, newerThan: LK_VERSION) else {
                blog("bar: 自动检查更新 已是最新（本机 v\(LK_VERSION)）")
                return
            }
            // 只记住、不改动屏幕状态：等用户自己点置顶条目前往发布页
            self.newVersion = latest
            self.newVersionURL = html
            self.refreshUI()
            blog("bar: 自动检查更新 发现新版本 v\(latest)")
        }
    }

    /// 点击置顶的「有新版本」：打开发布页。不清除标记 —— 提醒会一直留在菜单栏
    /// 直到真的装上新版（LK_VERSION 追平），避免「看了一眼就再也想不起来」。
    @objc private func openPendingUpdate(_ sender: Any?) {
        if let u = URL(string: newVersionURL ?? releasesURL) { NSWorkspace.shared.open(u) }
    }

    /// 语义化版本比较：a 是否比 b 新（仅比 major.minor.patch 数字）
    /// 先截掉预发布/构建元数据（`-beta.1`、`+build`）：若不截，`Int("0-beta")` 解析失败会被
    /// compactMap 丢弃，导致后续数字**下标错位**，把 `2.2.0-beta.1` 误判成比 `2.2.0` 更新。
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = releaseParts(a)
        let pb = releaseParts(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 把 `2.2.0-beta.1` / `2.2.0+build3` 这类版本串归一化成 `[2, 2, 0]`。
    /// 只在第一个 `-` 或 `+` 处截断，非数字段一律丢弃。
    private func releaseParts(_ s: String) -> [Int] {
        let core = s.prefix { $0 != "-" && $0 != "+" }
        return core.split(separator: ".").compactMap { Int($0) }
    }

    private func reportUpdateUpToDate() {
        let a = NSAlert()
        a.messageText = L("已是最新版本")
        a.informativeText = L("你正在使用最新版本 ") + "v\(LK_VERSION)。"
        a.addButton(withTitle: L("好"))
        a.runModal()
    }

    private func reportUpdateAvailable(latest: String, html: String?) {
        let a = NSAlert()
        a.messageText = L("发现新版本")
        a.informativeText = L("当前版本 ") + "v\(LK_VERSION)，" + L("最新版本 ") + "v\(latest)。\n" + L("点击「打开发布页」前往下载。")
        a.addButton(withTitle: L("打开发布页"))
        a.addButton(withTitle: L("好"))
        if a.runModal() == .alertFirstButtonReturn {
            if let u = URL(string: html ?? releasesURL) { NSWorkspace.shared.open(u) }
        }
    }

    private func reportUpdateFailure(message: String) {
        let a = NSAlert()
        a.messageText = L("检查更新失败")
        a.alertStyle = .warning
        a.informativeText = message + "\n" + L("你可以手动前往发布页查看。")
        a.addButton(withTitle: L("打开发布页"))
        a.addButton(withTitle: L("好"))
        if a.runModal() == .alertFirstButtonReturn {
            if let u = URL(string: releasesURL) { NSWorkspace.shared.open(u) }
        }
    }

    /// 热键未生效时的排查入口。刻意不弹模态对话框挡住主线程，只给提示 + 重试
    @objc private func openAuthorizeFromMenu(_ sender: Any?) {
        ensureHotkey()
        if ctl.hotkeyReady {
            blog("bar: 排查后热键已恢复 \(hotkeyText(ctl.cfg))")
            return
        }
        let a = NSAlert(); a.alertStyle = .warning
        a.messageText = L("快捷键未生效")
        let hotkeyHelp: String
        if L10n.isEN {
            hotkeyHelp = """
            \(hotkeyText(ctl.cfg)): \(carbonStatusText(ctl.lastHotkeyStatus))

            This app uses the system-level global hotkey (Carbon), so it needs no Accessibility or Input Monitoring grant.
            When it doesn't work, it is usually one of these three:
            1. Another app owns the combo — pick a different one in Settings, e.g. ⇧⌘B or ⌃⌥⌘B;
            2. The combo has no modifier — macOS requires at least one of ⌘ / ⌃ / ⌥ / ⇧;
            3. The app was just reinstalled and macOS has not refreshed its hotkey table — quit and relaunch once.
            """
        } else {
            hotkeyHelp = """
            \(hotkeyText(ctl.cfg))：\(carbonStatusText(ctl.lastHotkeyStatus))

            本程序使用系统级全局热键（Carbon），不需要「辅助功能 / 输入监控」授权。
            未生效通常是这三种情况：
            1. 组合被其他 App 占用 —— 在设置里换一个，例如 ⇧⌘B、⌃⌥⌘B；
            2. 组合没带修饰键 —— 系统要求 ⌘ / ⌃ / ⌥ / ⇧ 至少一个；
            3. App 刚重装，系统热键表未刷新 —— 退出本程序重开一次。
            """
        }
        a.informativeText = hotkeyHelp
        a.addButton(withTitle: L("打开设置"))
        a.addButton(withTitle: L("好"))
        if a.runModal() == .alertFirstButtonReturn { openSettings(nil) }
    }
}

// MARK: - 入口
if CommandLine.arguments.contains("--version") {
    print("LidKeep \(LK_VERSION) (\(LK_COMMIT))")
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)          // 不显示 Dock 图标
let delegate = AppDelegate()
app.delegate = delegate
app.run()
