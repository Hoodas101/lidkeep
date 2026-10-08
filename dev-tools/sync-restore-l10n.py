#!/usr/bin/env python3
"""补 `已发送恢复指令（3s 内仍在黑屏，请查看 ` 的六语翻译。

起因：这轮给 `lidkeep on` 的「守护没真死」分支补了退出码 1，中文文案写了，
六语表没跟上 —— `make test` 报「缺失 1 条译文」。

key 含中文标点与全角括号，只能整行插入，不要用正则编辑。
收尾的 `）` 是独立一条（同族文案都是这个形态：前缀 + 运行时插入的路径 + 收尾）。
"""
import pathlib
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
# 插在同族那条之后，保持这一段聚在一起
ANCHOR = '"已发送进入黑屏指令（3s 内未确认，请查看 "'

ROWS = {
    "已发送恢复指令（3s 内仍在黑屏，请查看 ": {
        "EN": "Restore command sent (still black after 3s, see ",
        "JA": "復帰コマンドを送信しました（3秒後まだ画面が暗転しています。確認先: ",
        "KO": "복구 명령을 보냈습니다 (3초 후에도 화면이 꺼져 있습니다. 확인: ",
        "DE": "Wiederherstellungsbefehl gesendet (nach 3s weiterhin schwarz, siehe ",
        "FR": "Commande de restauration envoyée (toujours noir après 3 s, voir ",
        "ES": "Orden de restauración enviada (sigue negro tras 3 s, ver ",
    },
    "）": {
        "EN": ")",
        "JA": "）",
        "KO": ")",
        "DE": ")",
        "FR": ")",
        "ES": ")",
    },
}


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    for lg in LANGS:
        p = root / "Sources" / "Shared" / f"L10n{lg}.swift"
        s = p.read_text(encoding="utf-8")
        added = 0
        for zh, tr in ROWS.items():
            if f'"{esc(zh)}"' in s:
                continue                      # 幂等：已存在就不重复插
            a = ANCHOR
            i = s.find(a)
            if i < 0:
                print(f"  {lg}: 锚点未找到，跳过 {zh}", file=sys.stderr)
                continue
            # 锚点是单行条目，找到该行行尾，在其后插入
            eol = s.find("\n", i)
            eol = len(s) if eol < 0 else eol
            ins = f'\n    "{esc(zh)}": "{esc(tr[lg])}",'
            s = s[:eol] + ins + s[eol:]
            added += 1
        p.write_text(s, encoding="utf-8")
        print(f"  L10n{lg}.swift  新增 {added} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
