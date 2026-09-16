import Foundation
import Darwin

// MARK: - 进程归属判定（Bar 与 CLI 共用）
//
// 这个判定的用途是**决定要不要给某个 pid 发信号**，判错就是误杀别人的进程，所以单独抽出来。
//
// 曾经的做法是在 `ps -o command=`（**整条命令行**）里找 "lidkeep" / "LidKeep" 子串。
// 问题在于：任何**只是提到过这个路径**的进程都会命中 —— 正在跑 LidKeep 脚本的 shell、
// 在终端里 grep 这个路径的动作、把路径当参数传给别的命令的构建脚本。
// 而这些恰好就是「用户正在操作 LidKeep」时最常存在的进程。
//
// 实测后果：App 启动接管 service.pid 时，会把 pid 被系统回收后落到这类进程上的那个
// 无关进程 SIGTERM 掉。本机真的撞了两次 —— 执行调试脚本的 shell 被自己刚拉起的 App 杀掉，
// 表现为「命令莫名其妙被掐断、没有任何输出」，极难联想回这个原因。
//
// 正确的身份信号是**可执行文件本身**：`proc_pidpath()` 返回真正被 exec 的映像路径，
// 完全不受命令行参数影响。于是判定改为「basename 是否就是我们自己的二进制名」。

/// 本程序家族的可执行文件名。历史名 blankscreen 已拆除，不再纳入。
private let ourExecutableNames: Set<String> = ["lidkeep", "LidKeep"]

/// 真正被 exec 的可执行文件路径；读不到（无权限 / 进程已退出）返回 nil。
func procExecutablePath(_ pid: Int32) -> String? {
    var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : nil
}

/// 该路径的 basename 是否为本程序的可执行文件
func executablePathIsOurs(_ path: String) -> Bool {
    ourExecutableNames.contains((path as NSString).lastPathComponent)
}

/// **严格**归属判定：拿不到可执行文件路径一律判否。
/// 用于任何「准备给这个 pid 发信号」的场合 —— 拿不准就不要动手。
func pidIsOurExecutable(_ pid: Int32) -> Bool {
    guard let p = procExecutablePath(pid) else { return false }
    return executablePathIsOurs(p)
}

/// 这个 pid 是不是 `caffeinate`。
///
/// ⚠️ 单独用它**不能**判归属：用户自己/其他 App 起的 caffeinate 完全一样。
/// 必须再叠一层亲缘关系（父进程是我们、或 `-w` 盯着我们的 pid）才能当作自家断言。
func pidIsCaffeinate(_ pid: Int32) -> Bool {
    guard let p = procExecutablePath(pid) else { return false }
    return (p as NSString).lastPathComponent == "caffeinate"
}

/// 宽松归属判定：拿不到路径时**保守地判是**（保持早期行为，避免权限受限让功能整体不可用）。
/// 只允许用于「要不要相信自家 pid 文件里记着的那个 pid」，不得用于批量 kill。
func pidIsProbablyOurs(_ pid: Int32) -> Bool {
    guard let p = procExecutablePath(pid) else { return true }
    return executablePathIsOurs(p)
}

/// 进程的完整命令行。只用来**读角色**（例如参数里有没有 `nosleep-daemon`），
/// 绝不能单独拿它判归属 —— 那正是文件开头那段注释里的坑。
///
/// 实现读内核里的 argv（`sysctl KERN_PROCARGS2`），**全程进程内、不 spawn 任何外部命令**。
///
/// ⚠️ **不要把它改成 spawn `/bin/ps`**（历史上就是这样写的，踩过大坑）。
/// 受限运行环境会**拒绝执行 setuid 程序**（`/bin/ps` 与 `/usr/bin/sudo` 都是 `-rws`，
/// 而同机的 `pgrep` 不带 setuid 所以照常可用）——这也正是本机 `make test` 跑起来
/// `ps` 报 `Operation not permitted` 的原因，不是本机装坏了。被拒时这里会恒返回空串：
/// 角色判定对**每一个**进程都失败 → `ourDaemonPids()` 静默返回空 →
/// 「守护唯一性」「遗留清理」这些守卫集体空转，而 `nosleep off` 仍然打印「防睡眠已关闭」
/// （它只看枚举结果是否为空）、退出码 0。后果是守护越积越多、每个都持有 caffeinate /
/// disablesleep，机器再也睡不着，而界面上一切正常 —— 本项目最危险的一类故障。
/// 走 sysctl 之后，连受限环境里也能照常判定，测试里那几条「ps 不可用就跳过」才有机会收紧。
func procCommandLine(_ pid: Int32) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return "" }
    // 缓冲区开头是 exec 路径 + NUL 填充，argv 紧随其后（末尾还有环境变量）。
    // 本函数只用于「子串包含」判断，所以整段拍平即可，无需精确切分 argv。
    return String(decoding: buf, as: UTF8.self).replacingOccurrences(of: "\0", with: " ")
}

/// 当前所有活着的 pid。**进程内枚举**（`proc_listpids`），不 spawn 外部命令 ——
/// 同理不要改成 spawn `pgrep`：exec 被策略拒掉时它会静默返回空，
/// 校验逻辑会误判成「一个都不存在」，比报错更难查。
func allPids() -> [Int32] {
    let need = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard need > 0 else { return [] }
    let cap = Int(need) / MemoryLayout<Int32>.size + 64   // 留余量：枚举期间还会有进程新建
    var buf = [Int32](repeating: 0, count: cap)
    let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buf, Int32(cap * MemoryLayout<Int32>.size))
    guard got > 0 else { return [] }
    return buf.prefix(Int(got) / MemoryLayout<Int32>.size).filter { $0 > 0 }
}

/// 父进程 pid。读 `sysctl KERN_PROC_PID`，**进程内完成**。
/// pid 不存在 / 已退出返回 nil；pid 1（launchd）的父进程是 0，属正常值。
///
/// 与 `procCommandLine` 同理，**不要改成 spawn `/bin/ps -o ppid=`**：受限环境下 setuid
/// 程序会被拒绝执行，读到的不是「父进程是 0」而是「什么都没读到」，
/// 而调用方（doctor 的断言归属、Bar 的旧实例收尾）全都把「读不到」当成「不是我们的」——
/// 于是本程序自己持有的 caffeinate 会被当成第三方，界面与事实相反。
func procPpid(_ pid: Int32) -> Int32? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
}
