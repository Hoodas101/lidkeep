// 列出本程序自己持有的 caffeinate 断言及其参数（-d / -is / -dis）。
//
// 为什么需要它：smoke.sh 的【13】【14】要区分「保持屏幕常亮」(-d) 与
// 「息屏后保持唤醒」(-is)，原来的实现靠 `ps -o command=`，而受限环境会拒绝执行
// setuid 程序（本机 `make test` 里就报 Operation not permitted），于是这两组用例
// 长期以「本环境 ps 不可用」被跳过 —— 而它们守的是「电量放到自动关机而保护不介入」
// 这类真实故障。守护唯一性、遗留清理这些守卫当初改用 sysctl 就是同一个理由。
//
// 这里直接复用 Sources/Shared/Ownership.swift 的 procCommandLine()：走
// KERN_PROCARGS2，进程内读，不 spawn 任何外部命令。判据也只用 pidIsOurExecutable()
// （严格读 proc_pidpath 的 basename）—— 绝不按命令行里的路径字样判「是不是我们的」，
// 那条纪律的教训见 Ownership.swift 顶部注释。
//
// 用法:  caff-args            列出全部
//        caff-args -d         只列出 -d（不含 -dis）
//        caff-args -is        只列出 -is
//        caff-args -dis       只列出 -dis
// 输出: 每行一个 pid + 规范化后的参数串；无匹配时输出为空且退出码 1，
//       调用方据此判定「断言已释放」。退出码 1 不是错误，是「现在没有」。

// Swift 的 `import` 是**文件作用域**，不跨文件传递：Ownership.swift 里的
// `import Foundation` 不会让本文件用到 FileHandle / exit。
import Foundation

// ⚠️ 写 `if hits.isEmpty()`（带括号）在本机的 Swift 6.4 + macOS 27.2 SDK 上会报
// "cannot call value of non-function type 'Bool'"，而 `if hits.isEmpty {`（不带）
// 正常通过。`isEmpty` 是属性不是方法，带括号被解析成「调用这个 Bool」——
// 在 Linux Swift 5.x 与本机旧 SDK 上都不会报，是个纯环境相关的编译器怪癖。
// 下面全部用不带括号的写法，别"顺手修正"成带括号。
//
// Ownership.swift 里的 procCommandLine / pidIsCaffeinate 原样复用，
// 不在这里重写一份 —— 重写就等于多一处会走偏的实现。

/// 从命令行里抽出 caffeinate 的参数部分。
///
/// `procCommandLine` 返回的是 exec 路径 + argv + 环境变量拍平的一整段（那是它
/// 「只做子串判断」的定位）。这里要的是精确的参数，所以按 argv 的分隔规律再切一次：
/// 环境变量里也可能有空格，但 caffeinate 的参数都在 argv 里、且紧跟可执行文件，
/// 因此取「可执行文件之后、下一个看起来像路径的 token 之前」这一段。
func caffinateArgs(_ cmdline: String) -> String {
    let toks = cmdline.split(whereSeparator: { $0 == " " || $0 == "\0" }).map(String.init)
    guard let exeIdx = toks.firstIndex(where: { $0.hasSuffix("/caffeinate") }) else { return "" }
    var args: [String] = []
    for t in toks[(exeIdx + 1)...] {
        // argv 到此结束：环境变量以「KEY=VALUE」形态出现，或出现明显不是参数的东西。
        // 判据用「含 = 」而不是「以 - 开头」—— caffeinate 的参数本来就都是 -x。
        if t.contains("=") { break }
        args.append(t)
    }
    return args.joined(separator: " ")
}

let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
// 不要叫 found：那是 Collection.find(where:) 的名字。顶层局部变量会遮蔽它，
// 后面 found.isEmpty() 被解析成「调用这个方法」，报
// "cannot call value of non-function type 'Bool'"。
var hits: [String] = []

for pid in allPids() {
    // 严格准入：可执行文件必须是 caffeinate 本身。命令行里出现 "caffeinate" 字样的
    // 无关进程（shell、grep、编辑器）在这里就进不来。
    guard pidIsCaffeinate(pid) else { continue }
    let args = caffinateArgs(procCommandLine(pid))
    guard !args.isEmpty else { continue }
    if !want.isEmpty {
        // 精确匹配单个参数：-d 不匹配 -dis，-dis 不匹配 -d。
        // 用「按空格切开后包含该 token」判定，不做子串匹配。
        let toks = args.split(separator: " ").map(String.init)
        guard toks.contains(want) else { continue }
    }
    hits.append("\(pid) \(args)")
}

if hits.isEmpty {
    exit(1)
}
for h in hits { print(h) }
exit(0)