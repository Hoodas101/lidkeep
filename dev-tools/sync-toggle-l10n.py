#!/usr/bin/env python3
# 补 P1-2 引入的 toggle 未确认提示的六语翻译。
# key 含中文冒号，只能整行插入，不要用正则（见 sync-timeout-l10n.py 的教训）。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}
ANCHOR = '"部分屏幕未能熄屏："'

ROWS = [
    (
        "切换指令未被常驻服务响应（3s 内状态未变化，请查看 ",
        "Toggle was not acknowledged by the resident service (state unchanged within 3s; check ",
        "常駐サービスがトグル要求に応答しませんでした（3秒以内に状態が変わらず。確認してください: ",
        "상주 서비스가 토글 요청에 응답하지 않았습니다 (3초 이내에 상태가 변하지 않음, 확인: ",
        "Der Dienst hat den Wechsel nicht quittiert (Zustand binnen 3s unverändert; siehe ",
        "Le service résident n’a pas acquitté la bascule (état inchangé sous 3s ; voir ",
        "El servicio residente no confirmó el cambio (estado sin variar en 3s; consulte ",
    ),
]
# 结尾的 "）" 六张表里都有（见 L10nJA.swift 的 `    "）": "）",`），复用不重复插。

for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    at = next((i for i, l in enumerate(lines) if ANCHOR in l), None)
    if at is None:
        print("%s: 锚点未找到" % lg)
        sys.exit(1)
    indent = lines[at][: len(lines[at]) - len(lines[at].lstrip())]
    for key, *vals in reversed(ROWS):
        lines.insert(at, '%s"%s": "%s",' % (indent, key, vals[IDX[lg] - 1]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 已插入 %d 条" % (lg, len(ROWS)))