import Foundation
import CoreGraphics
import Carbon.HIToolbox
import Darwin

// MARK: - 系统状态的读写（Bar 与 CLI 共用的唯一一份实现）
//
// 这里放的都是「问系统 / 叫系统做事」的东西：路径、屏幕亮度、电池、提权助手、按键表。
//
// 为什么必须合成一份：这些查询在两个 target 里都被调用，历史上各写一遍，
// 于是同一条路径、同一个判定在两处慢慢长歪 —— 实测已经出现过按键表不一致
// （菜单栏 App 认识 F5，CLI 把同一个键显示成 `keyCode 96`）。
// 两份实现的唯一好处是「改起来自由」，代价是「总有一份是错的」，不值。

// MARK: - 路径
let fm = FileManager.default
let home = NSHomeDirectory()
let base = home + "/Library/Application Support/LidKeep"
let stateFile = base + "/brightness.state"     // 存在即表示处于黑屏（同时保存待恢复亮度）
let serviceFile = base + "/service.pid"        // 常驻进程（菜单栏 App 或 CLI 服务）的 pid
let configFile = base + "/config.json"
let logPath = base + "/LidKeep.log"
let commandFile = base + "/command"            // CLI → 菜单栏 App 的指令文件（比信号可靠）
let rejectFile = base + "/reject"              // 关屏被拒（电量过低 / 亮度接口不可用）时回传原因
let nosleepPidFile = base + "/nosleep.pid"     // 防睡眠守护进程
/// 电量仿真钩子（仅测试用）。内容同 `LK_SIMULATE_BATTERY`：`电量,batt|ac,discharging|charging`。
/// 环境变量只在进程启动时读一次，测「运行中拔插电源」必须靠一个能被外部改写的位置；
/// 而且由 App 拉起的守护拿不到 App 的环境变量。文件不存在时完全走真实 pmset。
let simBatteryFile = base + "/_sim-battery"
// 防睡眠 Level 2（覆盖电池与合盖）所需：caffeinate -s 按 man page 明写「仅 AC 有效」，
// 电池与合盖只能靠 pmset disablesleep，而它需要 root。
let helperPath = "/Library/PrivilegedHelperTools/com.lidkeep.pmset"
let sudoersPath = "/etc/sudoers.d/lidkeep"

// MARK: - 通用子进程调用
/// 捕获 stdout。必须先读再 waitUntilExit：子进程输出超过管道缓冲时，
/// 先等待会与子进程互相阻塞形成死锁。
///
/// stderr 一律**丢弃**（nullDevice），不要接一个从不读取的 Pipe ——
/// 那正是同一个死锁的另一种写法：子进程把 stderr 写满缓冲后卡在 write 上，
/// waitUntilExit 永远不返回，调用方（App 或 CLI）就此整体挂死。
/// 本函数只消费 stdout，没有任何调用方解析 stderr。
func runCapture(_ exe: String, _ a: [String]) -> String? {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = a
    p.standardInput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    let pipe = Pipe(); p.standardOutput = pipe
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)
}

/// 只跑不管输出，返回退出状态。用于「执行一个副作用动作，只关心成没成」的场合
/// （拉起/停止守护、复位 disablesleep 之类）。
@discardableResult
func sh(_ exe: String, _ a: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = a
    p.standardOutput = nil; p.standardError = nil; p.standardInput = nil
    try? p.run(); p.waitUntilExit(); return p.terminationStatus
}

// MARK: - 亮度读写（DisplayServices 私有框架）
let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
typealias DSGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias DSSet = @convention(c) (UInt32, Float) -> Int32

/// DisplayServices 是可移除的私有框架：一旦 Apple 在新系统里拿掉它，所有亮度操作都会静默失效。
/// 显式暴露可用状态，让 status / 关屏入口都能明确报错，而不是「命令成功但屏幕没变化」。
var dsAvailable: Bool {
    guard let h = dsHandle else { return false }
    return dlsym(h, "DisplayServicesGetBrightness") != nil
        && dlsym(h, "DisplayServicesSetBrightness") != nil
}

/// 所有在线显示器。只操作 CGMainDisplayID() 会漏掉外接屏——用户要的是「关屏」，即全部。
func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [CGMainDisplayID()] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetOnlineDisplayList(count, &ids, &count)
    return ids.prefix(Int(count)).isEmpty ? [CGMainDisplayID()] : Array(ids.prefix(Int(count)))
}

/// 上一次设置亮度时失败的显示器（多数 HDMI/DVI/DP 外接屏不支持软件亮度）。
/// 这类屏关不掉，必须让用户看见，而不是让他以为一切正常。
var lastFailedDisplays: [CGDirectDisplayID] = []

func setOneBrightness(_ id: CGDirectDisplayID, _ v: Float) -> Bool {
    guard let h = dsHandle, let p = dlsym(h, "DisplayServicesSetBrightness") else { return false }
    return unsafeBitCast(p, to: DSSet.self)(id, v) == 0
}

func readBrightness() -> Float {
    guard let h = dsHandle, let p = dlsym(h, "DisplayServicesGetBrightness") else { return -1 }
    let f = unsafeBitCast(p, to: DSGet.self)
    var v: Float = -1
    return f(CGMainDisplayID(), &v) == 0 ? v : -1
}

/// 返回 false = 设置失败（实测成功时返回 0）。失败必须可见，否则用户会以为关屏成功、
/// 实际屏幕还亮着。遍历所有在线显示器：只关主屏会让外接屏继续亮着，等于没关。
@discardableResult
func setBrightness(_ v: Float) -> Bool {
    var ok = false
    var failed: [CGDirectDisplayID] = []
    for id in onlineDisplays() {
        if setOneBrightness(id, v) { ok = true } else { failed.append(id) }
    }
    lastFailedDisplays = failed
    return ok
}

/// 恢复必须尽最大努力成功：失败意味着用户永远看不见屏幕，因此多次重试而非「设一次就走」
@discardableResult
func restoreBrightness(_ v: Float) -> Bool {
    for i in 0..<6 {
        var ok = false
        for id in onlineDisplays() { if setOneBrightness(id, v) { ok = true } }
        if ok { return true }
        usleep(UInt32(150_000 * (i + 1)))
    }
    return false
}

// MARK: - 电池状态（pmset -g batt，免授权）
struct Battery { var onBattery = false, discharging = false, percent = 100 }

func batteryStatus() -> Battery {
    var b = Battery()
    // 测试钩子：优先环境变量，再读文件钩子（两者格式相同）。
    // 例: LK_SIMULATE_BATTERY="15,batt,discharging" lidkeep off
    // 仅供验证电量保护路径（插电的机器无法真实触发），正式使用不读取它。
    let sims = [ProcessInfo.processInfo.environment["LK_SIMULATE_BATTERY"],
                try? String(contentsOfFile: simBatteryFile, encoding: .utf8)]
    for case let sim? in sims {
        let parts = sim.lowercased().split(separator: ",").map(String.init)
        if let p = parts.first, let v = Int(p), (0...100).contains(v) {
            b.percent = v
            b.onBattery = parts.contains("batt")
            b.discharging = parts.contains("discharging")
            return b
        }
    }
    guard let out = runCapture("/usr/bin/pmset", ["-g", "batt"]), !out.isEmpty else { return b }
    b.onBattery = out.contains("Battery Power")
    b.discharging = out.range(of: "discharging", options: .caseInsensitive) != nil
    for tok in out.split(whereSeparator: { " \t\n;".contains($0) }) {
        if tok.hasSuffix("%"), let v = Int(tok.dropLast()) { b.percent = v; break }
    }
    return b
}

// MARK: - 提权助手（pmset disablesleep 的唯一通道）
/// 两个文件齐全才算已安装。只查文件会出现「装了一半」却静默降级的情况。
/// 注意 sudoers 只判存在、不能读内容：0440 root:wheel 对普通用户不可读，读会误判未安装。
func helperInstalled() -> Bool {
    fm.isExecutableFile(atPath: helperPath) && fm.fileExists(atPath: sudoersPath)
}

/// 经 sudo -n 调用 helper。arg 走白名单，杜绝参数注入。
/// 返回 nil = 不可用（未安装 / 授权失效 / pmset 已移除该选项），调用方必须据此降级并告知用户。
func helperExec(_ arg: String) -> String? {
    guard ["on", "off", "status", "detect"].contains(arg), helperInstalled() else { return nil }
    return runCapture("/usr/bin/sudo", ["-n", helperPath, arg])?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 系统级防睡眠当前是否真的生效（回读真实状态，不靠自己记的标志）。
///
/// 直接读 `pmset -g`（普通用户就能读），**不要改成问提权助手**：助手必须经 `sudo`，
/// 而受限环境（含本机 `make test`）会拒绝执行 setuid 程序 —— 那条路一旦走不通，
/// 这里就恒为 false，于是 doctor 对着一个真的开着（`SleepDisabled 1`）的系统
/// 报「系统级开关: 关闭」，`recoverStaleNosleep` 也永远不去复位残留的 disablesleep。
/// 口诀：**读事实走无权限通道，改事实才需要 root**（改的那一步仍旧走 helperExec）。
func systemSleepDisabled() -> Bool {
    guard let out = runCapture("/usr/bin/pmset", ["-g"]) else { return false }
    for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
        // 形如 ` SleepDisabled\t\t1`；取最后一个字段，非 0 即为「已禁用睡眠」
        guard let v = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last else { return false }
        return String(v) != "0"
    }
    return false   // 该系统已移除 disablesleep（未文档化选项）→ 视为未开启
}

/// 提权助手版本是否过旧：带「持有者记账」的版本 detect 输出会带 owners= 字段。
/// 旧版没有记账 —— 关屏联动与手动防睡眠会互相踩掉对方的 disablesleep，需要重装助手。
func helperOutdated() -> Bool {
    guard helperInstalled(), let d = helperExec("detect") else { return false }
    return !d.contains("owners=")
}

// MARK: - 按键表（菜单栏与 CLI 必须认同一个键名）
/// 支持作为全局热键的按键。**只此一份**：曾经两端各有一张表，菜单栏那份是全的，
/// CLI 那份只到 A–Z + F13 + Space —— 于是同一个 `⌃⌥F5` 在菜单里叫「F5」，
/// 在 `lidkeep doctor` 里叫「keyCode 96」，用户以为设置坏了。
let keyTable: [(String, Int64)] = [
    ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4),
    ("I", 34), ("J", 38), ("K", 40), ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35),
    ("Q", 12), ("R", 15), ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
    ("Y", 16), ("Z", 6),
    ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97),
    ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
    ("F13", 105), ("F14", 107), ("F15", 113), ("F16", 106), ("F17", 64), ("F18", 79),
    ("F19", 80), ("F20", 90),
    ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("5", 23),
    ("6", 22), ("7", 26), ("8", 28), ("9", 25),
    ("-", 27), ("=", 24), ("[", 33), ("]", 30), ("\\", 42), (";", 41),
    ("'", 39), (",", 43), (".", 47), ("/", 44), ("`", 50),
    ("←", 123), ("→", 124), ("↓", 125), ("↑", 126),
    ("Home", 115), ("End", 119), ("PgUp", 116), ("PgDn", 121),
    ("Space", 49), ("Esc", 53), ("Return", 36), ("Tab", 48), ("Delete", 51)
]

func keyName(_ code: Int64) -> String { keyTable.first { $0.1 == code }?.0 ?? "keyCode \(code)" }

func modsText(_ flags: UInt64) -> String {
    var s = ""
    if flags & MOD_CTRL  != 0 { s += "⌃" }
    if flags & MOD_ALT   != 0 { s += "⌥" }
    if flags & MOD_SHIFT != 0 { s += "⇧" }
    if flags & MOD_CMD   != 0 { s += "⌘" }
    return s.isEmpty ? L("（无修饰键）") : s
}

// MARK: - 全局热键：Carbon Event Manager（唯一的注册实现）
//
// 说明（important）：本程序此前用 CGEventTap 监听全局按键，那条链路强制要求
// 「输入监控 / 辅助功能」授权；而二进制是 ad-hoc 签名（无 Team ID），每次重新
// 编译 cdhash 都会变化，TCC 授权随之失效，导致用户反复勾选仍无效。
// Carbon RegisterEventHotKey 由 WindowServer 直接派发，不需要任何 TCC 权限，
// 因此作为热键主路径。
//
// 这一段也必须是同一份：两端各写一遍时已经长出差异（CLI 那份注册失败后没有清空
// `carbonHotKeyRef`，Bar 那份清了）。注册动作本身不依赖任何一端的日志实现 ——
// 它只返回 OSStatus，由调用方决定怎么记录，所以能安全地共享。
var carbonHotKeyRef: EventHotKeyRef?
var carbonHandlerRef: EventHandlerRef?
var carbonFire: (() -> Void)?        // 热键按下时执行的动作
var carbonProbe: (() -> Void)?       // 自检旁路，只记录不执行动作
let hotKeySignature: OSType = 0x424C4E4B        // 'BLNK'

/// NSEvent 修饰键位 -> Carbon 修饰键位
func carbonModifiers(_ flags: UInt64) -> UInt32 {
    var m: UInt32 = 0
    if flags & MOD_CMD   != 0 { m |= UInt32(cmdKey) }
    if flags & MOD_SHIFT != 0 { m |= UInt32(shiftKey) }
    if flags & MOD_ALT   != 0 { m |= UInt32(optionKey) }
    if flags & MOD_CTRL  != 0 { m |= UInt32(controlKey) }
    return m
}

/// 注册全局热键，返回 OSStatus（`noErr` = 成功）。事件处理器只装一次，之后复用。
@discardableResult
func registerCarbonHotKey(keyCode: Int64, modFlags: UInt64) -> OSStatus {
    if carbonHandlerRef == nil {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let st = InstallEventHandler(GetEventDispatcherTarget(),
            { _, _, _ -> OSStatus in
                // Carbon 回调在事件线程，切回主线程执行 UI / 亮度操作
                DispatchQueue.main.async { carbonProbe?(); carbonFire?() }
                return noErr
            }, 1, &spec, nil, &carbonHandlerRef)
        guard st == noErr else { return st }
    }
    if let old = carbonHotKeyRef { UnregisterEventHotKey(old); carbonHotKeyRef = nil }
    let hid = EventHotKeyID(signature: hotKeySignature, id: 1)
    let st = RegisterEventHotKey(UInt32(keyCode), carbonModifiers(modFlags), hid,
                                 GetEventDispatcherTarget(), 0, &carbonHotKeyRef)
    if st != noErr { carbonHotKeyRef = nil }
    return st
}

/// 注销全局热键（用户关掉「启用全局热键」时调用）。
/// 只摘掉热键本身，事件处理器留着复用。
func unregisterCarbonHotKey() {
    if let old = carbonHotKeyRef { UnregisterEventHotKey(old); carbonHotKeyRef = nil }
}

/// OSStatus -> 人话。注册结果只在这一处措辞，两端提示才不会各说各的。
func carbonStatusText(_ st: OSStatus) -> String {
    switch st {
    case noErr:                               return L("已注册")
    case OSStatus(eventHotKeyExistsErr):      return L("已被系统或其他 App 占用，请换一个组合")
    case OSStatus(eventHotKeyInvalidErr):     return L("组合无效（全局热键需要至少一个修饰键）")
    default:                                  return (L("注册失败（OSStatus ") + "\(st)" + L("）"))
    }
}
