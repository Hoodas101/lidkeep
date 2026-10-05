#!/usr/bin/env python3
"""校验 L10n 文案表与调用点**双向**对齐，并报告各语言覆盖率。

为什么需要这个：漏翻的后果是**中文环境下完全正常**（L 找不到键就原样返回），
其它语言环境才吐出中文。这种 bug 作者自己永远测不出来，只能靠机器查。
`make test` 会先跑本脚本，结构性错误直接失败。

键的**唯一基线**是 `Sources/Shared/L10nEN.swift`（英文表）：
调用点写 `L("中文原文")`，键就是那串中文原文。新增语言只需再加一份
`L10nXX.swift`，键必须与英文表逐字一致 —— 本脚本负责证明这一点。

检查项分两类：

  【失败】结构性问题，一定是 bug：
    1. 调用点的字面量不在英文表里 —— 其它语言会露出中文
    2. 英文表里的死键 —— 改名/改版后的残留，会让读者误以为功能还在
    3. 某语言表出现英文表里没有的键 —— 键抄错或基线漂移
    4. 某语言表内重复键 —— Swift 字典字面量重复键会在运行期随机取一个
    5. 译文与中文键**逐字相同**，且不在 SAME_OK 白名单里 —— 十有八九是漏翻。

  第 5 条为什么必须失败：漏翻的表现是「中文环境完全正常、外文环境露出中文」，
  作者自测发现不了。早先它只打 ⚠ 不改退出码，于是「未译=10」也能让 CI 全绿 ——
  这正是「看起来在拦、其实没拦」。要保留一条**确实该与中文同形**的条目
  （标点、共用汉字、单位），必须把它加进 SAME_OK 并写明理由，改的是白名单而不是判据。

  【报告】不失败，但需要人看：
    6. 各语言覆盖率（未覆盖的条目按设计降级为英文，不会坏界面）

用法：python3 dev-tools/check-l10n.py [仓库根目录]
"""
import pathlib
import re
import sys

# 语言表文件：L10nEN.swift / L10nJA.swift / …；L10n.swift 是引擎，不算表。
TABLE_RE = re.compile(r"^L10n([A-Z]{2})\.swift$")

# 允许「译文与中文键逐字相同」的条目白名单。
#
# 判据只有一条：这个字符/片段在中文与目标语言里本来就是同一种写法。
# 每次往里加东西，都要能说出「为什么同形是对的」；说不出就说明是漏翻，去翻译。
SAME_OK = {
    "、",         # 顿号：中文/日文同形
    "）",         # 全角右括号：中文/日文同形
    "：",         # 全角冒号：中文/日文同形
    "；",         # 全角分号：中文/日文同形
    "：⚠️ ",      # 同上，后缀 emoji
    "（--lang ",  # 全角左括号：中文/日文同形
    " 秒",        # 「秒」是中文/日文共用汉字
    " 秒（",      # 同上，再带一个全角左括号
    "s\u3000",    # 日文用表意空格对齐，与中文同形；韩文已改为半角（L10nKO）
}


def unescape(s: str) -> str:
    """把 Swift 字符串字面量里的转义还原成真实字符，便于和字典键比对。"""
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def swift_escape(s: str) -> str:
    """真实字符 → Swift 源码里会出现的转义写法。"""
    return (s.replace("\\", "\\\\").replace('"', '\\"')
             .replace("\n", "\\n").replace("\t", "\\t"))


def strip_comments(src: str) -> str:
    """去掉注释：注释里提到某段文案不算「还在用」。"""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", ln) for ln in src.split("\n"))


PAIR_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)",?\s*$', re.M)


def parse_table(path: pathlib.Path):
    """解析一份文案表，返回 [(键, 译文)]（按出现顺序，保留重复项以便查重）。"""
    return [(unescape(k), unescape(v))
            for k, v in PAIR_RE.findall(path.read_text(encoding="utf-8"))]


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    shared = root / "Sources/Shared"
    en_path = shared / "L10nEN.swift"
    if not en_path.is_file():
        print(f"找不到 {en_path}（英文表是键的唯一基线）", file=sys.stderr)
        return 2

    en_pairs = parse_table(en_path)
    keys = [k for k, _ in en_pairs]
    key_set = set(keys)
    rc = 0

    # ---- 1/2. 调用点 ↔ 英文表 双向对齐 ----
    missing, total, code = [], 0, []
    for f in sorted(root.glob("Sources/**/*.swift")):
        if TABLE_RE.match(f.name):
            continue                      # 表文件里没有 L() 调用点
        src = f.read_text(encoding="utf-8")
        code.append(strip_comments(src))
        for m in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', src):
            total += 1
            lit = unescape(m.group(1))
            if lit not in key_set:
                line = src[: m.start()].count("\n") + 1
                missing.append(f"{f}:{line}: {lit!r}")

    haystack = "\n".join(code)
    dead = [k for k in keys
            if not any(f'"{r}"' in haystack for r in {k, swift_escape(k)})]

    dup_en = sorted({k for k in keys if keys.count(k) > 1})
    print(f"英文表 {len(keys)} 条键（唯一 {len(key_set)}），L() 调用点 {total} 处")

    if missing:
        print(f"\n✗ 缺失 {len(missing)} 条译文（非中文界面会露出中文原文）：")
        for x in missing:
            print("   " + x)
        rc = 1
    if dead:
        print(f"\n✗ 死键 {len(dead)} 条（没有任何调用点使用，改名/改版后的残留）：")
        for k in dead:
            print("   " + repr(k))
        print("   → 逐行删掉即可（键=中文原文，删行不影响译文配对）")
        rc = 1
    if dup_en:
        print(f"\n✗ 英文表重复键 {len(dup_en)} 条（字典字面量重复键会随机取一个）：")
        for k in dup_en:
            print("   " + repr(k))
        rc = 1

    # ---- 3/4/5/6. 各语言表 ----
    tables = sorted((p for p in shared.glob("L10n??.swift") if p.name != "L10nEN.swift"),
                    key=lambda p: p.name)
    if tables:
        print(f"\n各语言表（基线 {len(keys)} 条）：")
        for p in tables:
            pairs = parse_table(p)
            tkeys = [k for k, _ in pairs]
            orphan = sorted(set(tkeys) - key_set)
            dup = sorted({k for k in tkeys if tkeys.count(k) > 1})
            same = [k for k, v in pairs if v == k]
            untranslated = [k for k in same if k not in SAME_OK]
            cover = len([k for k in tkeys if k in key_set])
            pct = cover * 100 // len(keys) if keys else 0
            flag = "✓" if (cover == len(keys) and not orphan and not dup
                           and not untranslated) else "⚠"
            print(f"  {flag} {p.name:<14} {cover}/{len(keys)} ({pct}%)"
                  f"  同形={len(same)}  漏翻={len(untranslated)}"
                  f"  孤儿键={len(orphan)}  重复={len(dup)}")
            if orphan:
                print(f"      ✗ 英文表里没有这些键（键抄错或基线漂移），共 {len(orphan)} 条：")
                for k in orphan[:10]:
                    print("         " + repr(k))
                if len(orphan) > 10:
                    print(f"         …另有 {len(orphan) - 10} 条")
                rc = 1
            if dup:
                print(f"      ✗ 表内重复键 {len(dup)} 条：")
                for k in dup[:10]:
                    print("         " + repr(k))
                rc = 1
            if untranslated:
                print(f"      ✗ 译文与中文键逐字相同 {len(untranslated)} 条"
                      f"（非中文界面会露出中文原文；确认同形合理就加进 SAME_OK 并写明理由）：")
                for k in untranslated[:15]:
                    print("         " + repr(k))
                if len(untranslated) > 15:
                    print(f"         …另有 {len(untranslated) - 15} 条")
                rc = 1
            if same and not untranslated:
                print(f"      ℹ 与中文同形 {len(same)} 条，均在白名单内（标点/共用汉字/对齐空格）")

    if rc == 0:
        print("\n✓ 结构检查通过：无漏翻调用点、无死键、无孤儿键、无重复键、无漏翻同形条目")
    return rc


if __name__ == "__main__":
    sys.exit(main())
