#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""审计多语言**拼接**缺陷 —— 不是 CI 用例，是改文案 / 加语言时手动跑的工具。

为什么需要它：L() 的键是**片段**，源码里用 `+` 拼起来。中文原文用全角标点，
片段之间天然有间距；换成拉丁字母语言后，边界必须显式留空格，漏一个就会拼出
`power;on battery` 或 `Status: PowerKeep awake` 这种东西。这类缺陷：

  - 在中文界面下永远不出现 —— 作者自己测不出来
  - 编译期不报错，swiftc / bash -n 都不管
  - 只影响某一种语言的观感，极易在 review 里滑过去

`dev-tools/check-l10n.py` 只查**结构**（漏翻、孤儿键、重复键），查不出这类
「键都在、但拼起来是错的」问题。本脚本补的正是这一段。

什么时候跑：
  - 新增一门语言之后
  - 批量改动文案之后
  - 改动 CLI / Bar 里任何 `L(...) + … + L(...)` 之后

检查项（前两项是硬缺陷，第三项需人工判断）：
  1. 边界粘连 —— 两个片段拼起来后，交界处会不会粘成一个词
  2. 键内粘连 —— 单个译文的半角右括号后直接贴了文字（`)복원` 这种）
  3. 引号边界 —— 片段首/末字符是引号或括号的，列出来人工核对配对。这类错位
     不产生粘连，只能靠人看：德语曾把 `zulässt` 提到用户名前面，引号内容整个
     错位，而字符数完全正常，任何机械检查都发现不了。

用法：python3 dev-tools/audit-l10n-concat.py [仓库根目录]
"""
import pathlib
import re
import sys

LANGS = ["en", "ja", "ko", "de", "fr", "es"]
QUOTES = "「」『』\"'«»（）()［］【】"
# 半角标点里，这些之后若紧跟文字就该有空格。`,` 刻意排除：
# CLI 示例里的 `cmd,shift` 是参数语法，逗号后本就不该有空格。
GLUE_AFTER = set(")]};!?")
# 半角标点之后，出现这些字符都算正常收尾：空格、行尾、另一个标点、全角标点
# （CJK 用全角标点，本身自带间距，不必再补空格）、以及 `/`（A/B 这种分隔符）。
OK_NEXT = set(" )]}.%,;:!?…»\n、。，：；！？（）「」『』/")
# 韩语的格助词 / 添意助词：紧贴前词书写是**正确**写法（한글 맞춤법 제41항），
# 所以右括号后面直接跟这些字不算粘连；跟实词（`)복원` 这种）才算。
KO_PARTICLES = ("이", "가", "을", "를", "은", "는", "의", "에", "와", "과", "도",
                "만", "께", "로", "으로", "부터", "까지", "보다", "처럼", "마다", "뿐")

TOKEN_RE = re.compile(r'L\(\s*"((?:[^"\\]|\\.)*)"\s*\)|"((?:[^"\\]|\\.)*)"|\\\(([^()]*)\)')
# 只认「纯 + 连接」：gap 里出现 ? 或 : 说明是三元/字典字面量，两侧是互斥分支
GAP_RE = re.compile(r"[\s+()]*")
CALL_RE = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')


def unescape(s: str) -> str:
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


PAIR_RE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)",?\s*$', re.M)


def parse_table(path: pathlib.Path):
    return {unescape(k): unescape(v)
            for k, v in PAIR_RE.findall(path.read_text(encoding="utf-8"))}


def is_lat(c: str) -> bool:
    return ("a" <= c <= "z") or ("A" <= c <= "Z") or ("0" <= c <= "9")


def value(tables, key, lang):
    """三级降级：当前语言 → 英文 → 中文原文。"""
    if lang == "zh":
        return key
    return tables[lang].get(key) or tables["en"].get(key) or key


def glue_reason(a: str, b: str):
    """交界处 a 的末字符 + b 的首字符 是否会粘连。"""
    if not a or not b:
        return None
    ca, cb = a[-1], b[0]
    if is_lat(ca) and is_lat(cb):
        return "字母/数字直接相连"
    if ca in ";:!?" and is_lat(cb):
        return "半角标点后缺空格"
    if ca == "," and is_lat(cb):
        return "半角逗号后缺空格"
    return None


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    shared = root / "Sources/Shared"
    tables = {}
    for p in sorted(shared.glob("L10n*.swift")):
        m = re.match(r"^L10n([A-Z]{2})\.swift$", p.name)
        if m:
            tables[m.group(1).lower()] = parse_table(p)
    if "en" not in tables:
        print(f"找不到英文表（键的唯一基线）：{shared}/L10nEN.swift", file=sys.stderr)
        return 2

    sources = [f for f in sorted(root.glob("Sources/**/*.swift"))
               if not re.match(r"^L10n[A-Z]{2}\.swift$", f.name)]

    # ---- 收集：拼接键集合 + 拼接边界 ----
    concat_keys, boundaries = set(), []
    for f in sources:
        text = f.read_text(encoding="utf-8")
        toks = []
        for m in TOKEN_RE.finditer(text):
            if m.group(1) is not None:
                toks.append(("L", unescape(m.group(1)), m.start(), m.end()))
            elif m.group(2) is not None:
                toks.append(("lit", unescape(m.group(2)), m.start(), m.end()))
            else:
                toks.append(("expr", None, m.start(), m.end()))
        for i in range(len(toks) - 1):
            a, b = toks[i], toks[i + 1]
            if not GAP_RE.fullmatch(text[a[3]:b[2]]):
                continue
            boundaries.append((f.name, text.count("\n", 0, a[2]) + 1, a, b))
        for m in CALL_RE.finditer(text):
            key = unescape(m.group(1))
            before = text[:m.start()].rstrip()
            after = re.sub(r"^[\s)]*", "", text[m.end():])
            if before.endswith("+") or after.startswith("+"):
                concat_keys.add(key)

    rc = 0

    # ---- 1. 边界粘连 ----
    hits = []
    for fname, line, a, b in boundaries:
        bad = {}
        for lang in LANGS:
            r = glue_reason(value(tables, a[1], lang) if a[0] == "L" else (a[1] or "Z"),
                            value(tables, b[1], lang) if b[0] == "L" else (b[1] or "Z"))
            if r:
                bad[lang] = r
        if bad:
            hits.append((fname, line, a, b, bad))
    if hits:
        rc = 1
        print(f"✗ 边界粘连 {len(hits)} 处（拼起来会粘成一个词）：")
        for fname, line, a, b, bad in hits:
            print(f"  {fname}:{line}  左={a[1]!r}  右={b[1]!r}")
            for lang in LANGS:
                va = value(tables, a[1], lang) if a[0] == "L" else (a[1] or "Z")
                vb = value(tables, b[1], lang) if b[0] == "L" else (b[1] or "Z")
                mark = "  ✗ " + bad[lang] if lang in bad else "    "
                print(f"    {lang}{mark} …{va[-32:]!r} + {vb[:32]!r}…")
    else:
        print("✓ 边界粘连：0 处")

    # ---- 2. 键内粘连 ----
    inner = []
    for lang in LANGS:
        for k, v in tables[lang].items():
            for i, c in enumerate(v[:-1]):
                if c in GLUE_AFTER and v[i + 1] not in OK_NEXT:
                    if lang == "ko" and v[i + 1:].startswith(KO_PARTICLES):
                        continue        # 韩语助词紧贴前词是正确写法，不是粘连
                    inner.append((lang, k, v, i))
                    break
    if inner:
        rc = 1
        print(f"\n✗ 键内粘连 {len(inner)} 处（半角右括号后直接贴了文字）：")
        for lang, k, v, i in inner:
            print(f"  [{lang}] {k!r}")
            print(f"       {v!r}")
            print(f"       位置 {i}: …{v[max(0, i - 14):i + 14]!r}…")
    else:
        print("\n✓ 键内粘连：0 处")

    # ---- 3. 引号边界（人工核对） ----
    quoted = []
    for k in sorted(concat_keys):
        vals = {L: value(tables, k, L) for L in LANGS}
        if any(v and (v[0] in QUOTES or v[-1] in QUOTES) for v in vals.values()):
            quoted.append((k, vals))
    print(f"\n—— 引号/括号边界片段 {len(quoted)} 个（需人工核对配对，非失败项）——")
    for k, vals in quoted:
        print(f"  {k!r}")
        for L in LANGS:
            v = vals[L]
            head = "␣" if v.startswith(" ") else ""
            tail = "␣" if v.endswith(" ") else ""
            print(f"    {L}: {head}{v}{tail}")

    print()
    print("✓ 无硬缺陷" if rc == 0 else "✗ 存在硬缺陷，见上")
    return rc


if __name__ == "__main__":
    sys.exit(main())
