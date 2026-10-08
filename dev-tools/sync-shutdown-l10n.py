#!/usr/bin/env python3
# 补 shutdown() 自愈记录写失败那条通知的六语翻译。
# 起因：那一支原来是 `try? String(target).write(toFile: stateFile…)` 之后无条件
# notify「下次启动会自动恢复」。写失败时磁盘上什么都没有，下次启动什么也不会发生，
# 而用户手里只有那条通知 —— 在唯一一条会永久黑屏的路径上骗他。
# key 含中文标点，只能整行插入，不要用正则（见 sync-timeout-l10n.py 的教训）。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}
ANCHOR = '"退出前亮度恢复失败，下次启动会自动恢复"'

ROWS = [
    (
        "退出前亮度恢复失败，记录也没写进去，请手动把亮度调回 ",
        "Brightness could not be restored before quitting, and the recovery note could not be "
        "written either. Please set the brightness back to ",
        "終了前に明るさを復元できず、復帰用の記録も書けませんでした。明るさを ",
        "종료 전에 밝기를 복원하지 못했고 복구 기록도 남기지 못했습니다. 밝기를 ",
        "Die Helligkeit konnte beim Beenden nicht wiederhergestellt werden und es konnte auch kein "
        "Wiederherstellungsvermerk geschrieben werden. Bitte die Helligkeit zurücksetzen auf ",
        "La luminosité n’a pas pu être restaurée avant la fermeture et la note de reprise n’a pas pu "
        "être écrite. Remettez la luminosité à ",
        "No se pudo restaurar el brillo antes de salir y tampoco se pudo escribir el registro de "
        "recuperación. Devuelve el brillo a ",
    ),
    (
        "（否则屏幕会一直黑着）",
        " (otherwise the screen stays black)",
        " に戻してください（このままだと画面が真っ暗のままです）",
        " 으로 직접 설정해 주세요 (그대로 두면 화면이 계속 꺼져 있습니다)",
        " (sonst bleibt der Bildschirm schwarz)",
        " (sinon l’écran reste noir)",
        " (si no, la pantalla se queda en negro)",
    ),
]

failed = False
for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    at = next((i for i, l in enumerate(lines) if ANCHOR in l), None)
    if at is None:
        print("%s: 锚点未找到" % lg)
        failed = True
        continue
    indent = lines[at][: len(lines[at]) - len(lines[at].lstrip())]
    for key, *vals in reversed(ROWS):
        if any('"%s"' % key in l for l in lines):
            print("%s: 已存在，跳过「%s」" % (lg, key[:14]))
            continue
        lines.insert(at + 1, '%s"%s": "%s",' % (indent, key, vals[IDX[lg] - 1]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 已处理 %d 条" % (lg, len(ROWS)))

sys.exit(1 if failed else 0)
