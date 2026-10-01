import Foundation

// MARK: - 本地化（多语言）
//
// 界面语言跟随系统，可用 LIDKEEP_LANG 或 config.json 的 lang 字段覆盖。
// 覆盖顺序（前者优先）：
//   1. 环境变量 LIDKEEP_LANG=zh|en|ja|ko|de|fr|es
//   2. config.json 里的 lang 字段：auto / 上述任一语言代码
//   3. 系统首选语言（AppleLanguages）
//
// 为什么不用 Bundle 本地化：CLI 与菜单栏 App 共用同一批字符串，而 CLI 不是 bundle，
// 拿不到 .lproj 资源；用代码表可以让两个 target 共用一份文案，且不会漏翻。
//
// 表按语言拆成独立文件（L10nEN / L10nJA / …），key 统一是源码里的**中文原文**。
// 这个约定有两个好处：调用点写成 L("关闭显示器") 仍然一眼能读；漏翻时 L() 能按
// 当前语言 → 英文 → 中文 三级降级，永远退得到有内容的东西，而不会出现空白或 key 泄漏。

enum L10n {
    /// 支持的语言代码。新增语言要动两处：这里，以及加一份 L10nXX.swift
    /// （构建侧用 wildcard 收 Sources/Shared/L10n*.swift，不用改 Makefile）。
    static let supported = ["zh", "en", "ja", "ko", "de", "fr", "es"]

    /// 当前语言。惰性求值一次，之后不再变。
    static let lang: String = {
        if let v = ProcessInfo.processInfo.environment["LIDKEEP_LANG"], let m = normalize(v) {
            return m
        }
        if let v = configuredLang(), let m = normalize(v) { return m }
        return systemPreferred() ?? "en"
    }()

    /// 界面语言是否为中文。给「只有中/英两套」的长帮助文本用（那些是多行字面量，
    /// 不走文案表）。判据必须是 isChinese 而不是 isEN —— 若写成「是英文吗」，
    /// 日语、德语用户会被判进 else 分支拿到**中文**帮助，比拿到英文更糟。
    static var isChinese: Bool { lang == "zh" }

    /// 拼接短句时要不要留分隔符。
    /// 中/日/韩可以直连（「状态：电源保持唤醒」），拉丁字母语言必须留，
    /// 否则会连成 "Status: PowerKeep awake"。
    static var needsWordSeparator: Bool { !["zh", "ja", "ko"].contains(lang) }

    /// 语言代码的显示名（用当前界面语言书写）。CLI 的 `config` 回显与设置面板共用。
    /// 代码 → 名字的映射只有这一处，免得 CLI 与 App 各拼一套、加语言时漏改一边。
    static func displayName(_ code: String) -> String {
        switch code {
        case "auto": return L("跟随系统")
        case "zh":   return L("中文")
        case "en":   return L("英文")
        case "ja":   return L("日文")
        case "ko":   return L("韩文")
        case "de":   return L("德文")
        case "fr":   return L("法文")
        case "es":   return L("西班牙文")
        default:     return code
        }
    }

    /// 可选的 --lang 取值清单，供帮助文本与错误提示复用
    static var langList: String { "auto/" + supported.joined(separator: "/") }

    /// 把任意语言标签归一化成支持列表里的一个；不支持则返回 nil。
    /// 例：zh-Hans / zh_CN → zh，en-GB → en，ja-JP → ja，nl-NL → nil。
    static func normalize(_ raw: String) -> String? {
        let s = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        guard !s.isEmpty else { return nil }
        // 中文先判：zh-Hans / zh-Hant / zh-CN 都归到同一套简体界面
        if s.hasPrefix("zh") { return "zh" }
        for code in supported where code != "zh" {
            if s == code || s.hasPrefix(code + "-") { return code }
        }
        return nil
    }

    /// 读 config.json 的 lang 字段（不依赖 Config 结构，避免初始化循环）。
    /// 返回 nil = auto 或取值不认识 → 交给系统语言。
    private static func configuredLang() -> String? {
        let p = NSHomeDirectory() + "/Library/Application Support/LidKeep/config.json"
        guard let d = FileManager.default.contents(atPath: p),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = o["lang"] as? String else { return nil }
        return s.lowercased() == "auto" ? nil : normalize(s)
    }

    /// 系统首选语言里第一个「我们支持的」。CLI 不是 bundle，读全局 AppleLanguages 更可靠。
    ///
    /// 整份列表都不在支持列表里时返回 nil（调用方默认英文）：此时**不能**再退回
    /// Locale.current，否则中国区域码会把荷兰语、瑞典语等系统误判成中文界面
    /// （实测踩过：模拟系统语言 ja 时输出过中文）。
    private static func systemPreferred() -> String? {
        var list: [String] = []
        if let v = CFPreferencesCopyAppValue("AppleLanguages" as CFString,
                                             kCFPreferencesAnyApplication) as? [String] {
            list = v
        }
        if list.isEmpty { list = Locale.preferredLanguages }
        for l in list { if let m = normalize(l) { return m } }
        if !list.isEmpty { return nil }
        // 只有连语言列表都拿不到（极少数 CLI 环境）才退回区域语言
        if let code = Locale.current.language.languageCode?.identifier { return normalize(code) }
        return nil
    }
}

/// 取本地化文案。查找顺序：**当前语言 → 英文 → 中文原文**。
///
/// 三级降级是刻意的：漏翻只会退成英文（既不是空白，也不是中文 key），
/// 所以「翻译不全」永远弄不坏界面，只会少一点本地化 —— 这正是新增语言时
/// 可以分批补译、而不必一次到位的依据。
func L(_ zh: String) -> String {
    switch L10n.lang {
    case "zh": return zh
    case "ja": if let v = L10nJA[zh] { return v }
    case "ko": if let v = L10nKO[zh] { return v }
    case "de": if let v = L10nDE[zh] { return v }
    case "fr": if let v = L10nFR[zh] { return v }
    case "es": if let v = L10nES[zh] { return v }
    default: break
    }
    return L10nEN[zh] ?? zh
}
