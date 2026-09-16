#!/usr/bin/env python3
"""校验 L10n 文案表与调用点**双向**对齐。

为什么需要这个：漏翻的后果是**中文环境下完全正常**（L 找不到键就原样返回），
英文环境才吐出中文。这种 bug 作者自己永远测不出来，只能靠机器查。
`make test` 会先跑本脚本，缺键直接失败。

反方向同样要查：**字典里没人用的死键**。改名 / 改版之后旧文案留在表里，
既不会被显示、也不会被任何人发现，只会让后来读代码的人以为还有那些功能
（实测积累过 54 条：「运行模式」「四选一」这类已删除特性的文案）。
键是"中文原文 → 英文译文"，每行一条，删掉一行就完事，所以死键一律当失败报出。

用法：python3 dev-tools/check-l10n.py [仓库根目录]
"""
import pathlib
import re
import sys


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
    """去掉注释：注释里提到某段文案不算"还在用"。"""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", ln) for ln in src.split("\n"))


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    l10n_path = root / "Sources/Shared/L10n.swift"
    if not l10n_path.is_file():
        print(f"找不到 {l10n_path}", file=sys.stderr)
        return 2

    l10n_src = l10n_path.read_text(encoding="utf-8")
    # 字典键形如   "原文": "译文",   每行一条
    keys = [unescape(raw)
            for raw in re.findall(r'^\s*"((?:[^"\\]|\\.)*)":', l10n_src, re.M)]

    missing, total, code = [], 0, []
    for f in sorted(root.glob("Sources/**/*.swift")):
        if f.name == "L10n.swift":
            continue
        src = f.read_text(encoding="utf-8")
        code.append(strip_comments(src))
        for m in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', src):
            total += 1
            lit = unescape(m.group(1))
            if lit not in keys:
                line = src[: m.start()].count("\n") + 1
                missing.append(f"{f}:{line}: {lit!r}")

    haystack = "\n".join(code)
    dead = [k for k in keys
            if not any(f'"{r}"' in haystack for r in {k, swift_escape(k)})]

    print(f"L() 调用点 {total} 处，L10n 键 {len(keys)} 条")
    rc = 0
    if missing:
        print(f"\n✗ 缺失 {len(missing)} 条译文（英文界面会露出中文）：")
        for x in missing:
            print("   " + x)
        rc = 1
    if dead:
        print(f"\n✗ 死键 {len(dead)} 条（没有任何调用点使用，改名/改版后的残留）：")
        for k in dead:
            print("   " + repr(k))
        print("   → 逐行删掉即可（键=中文原文，删行不影响译文配对）")
        rc = 1
    if rc == 0:
        print("✓ 双向对齐：无漏翻、无死键")
    return rc


if __name__ == "__main__":
    sys.exit(main())
