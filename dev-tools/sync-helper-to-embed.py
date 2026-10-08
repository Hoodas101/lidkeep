#!/usr/bin/env python3
# 把 packaging/helper/com.lidkeep.pmset 的改动同步进 CLI/main.swift 内嵌的那份。
#
# 方向很重要：项目注释写的是「资产内嵌在二进制里，packaging/helper 下的同名文件
# 由 `lidkeep nosleep write-assets` 生成」，所以**内嵌版本是真相源**，
# write-assets 是从内嵌版本往 packaging 写。
#
# 于是修 bug 时改哪一份都行，但**必须**让两份一致 —— smoke.sh 会 diff。
# 本脚本做的是「packaging → 内嵌」这个方向，前提是你刚改完 packaging。
# 反方向请直接跑 `lidkeep nosleep write-assets`（它需要重新构建 CLI 才生效）。
#
# 内嵌用的是 Swift 原始多行字符串（#""" … """#），因此反斜杠与双引号都不需要转义。
#
# 用法：python3 dev-tools/sync-helper-to-embed.py
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "packaging/helper/com.lidkeep.pmset")
SWIFT = os.path.join(ROOT, "Sources/CLI/main.swift")

BEGIN = 'let helperScript = #"""\n'
END = '\n"""#'


def main():
    with open(SRC, encoding="utf-8") as f:
        disk = f.read().strip()

    # 原始字符串里不能出现 """#，否则字面量提前结束
    if '"""#' in disk:
        sys.exit('脚本里出现了 \'"""#\'，会截断 Swift 原始字符串字面量')

    with open(SWIFT, encoding="utf-8") as f:
        swift = f.read()

    i = swift.find(BEGIN)
    if i < 0:
        sys.exit("找不到 `let helperScript = #\"\"\"` 起始标记")
    i += len(BEGIN)
    j = swift.find(END, i)
    if j < 0:
        sys.exit("找不到 `\"\"\"#` 结束标记")

    embedded = swift[i:j].strip()
    if embedded == disk:
        print("两处已一致，无需改动")
        return 0

    import difflib
    print("正在同步内嵌版本（%d 行 → %d 行）：" % (len(embedded.split("\n")), len(disk.split("\n"))))
    for line in list(difflib.unified_diff(
            embedded.split("\n"), disk.split("\n"),
            fromfile="内嵌（旧）", tofile="packaging（新）", lineterm=""))[:40]:
        print("  " + line)

    swift = swift[:i] + disk + swift[j:]
    with open(SWIFT, "w", encoding="utf-8") as f:
        f.write(swift)
    print("\n已同步。下一步：make cli && ./build/lidkeep nosleep write-assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())