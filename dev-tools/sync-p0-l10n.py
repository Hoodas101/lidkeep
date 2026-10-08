#!/usr/bin/env python3
# 补P0-2 引入的退出失败通知的六语翻译。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}
ANCHOR = '"部分屏幕未能熄屏："'

ROW = (
    "退出前亮度恢复失败，下次启动会自动恢复",
    "Brightness could not be restored before exit; it will recover on next launch",
    "終了前に明るさを復元できませんでした。次回起動時に自動復元します",
    "종료 전에 밝기를 복원하지 못했습니다. 다음 실행 시 자동으로 복구됩니다",
    "Helligkeit konnte vor dem Beenden nicht wiederhergestellt werden; beim nächsten Start erfolgt die Wiederherstellung automatisch",
    "La luminosité n’a pas pu être restaurée avant la fermeture ; elle le sera au prochain lancement",
    "No se pudo restaurar el brillo antes de salir; se restaurará automáticamente en el próximo inicio",
)

for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    at = next((i for i, l in enumerate(lines) if ANCHOR in l), None)
    if at is None:
        print("%s: 锚点未找到" % lg)
        sys.exit(1)
    indent = lines[at][: len(lines[at]) - len(lines[at].lstrip())]
    lines.insert(at, '%s"%s": "%s",' % (indent, ROW[0], ROW[IDX[lg]]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 已插入 1 条（第 %d 行）" % (lg, at + 1))