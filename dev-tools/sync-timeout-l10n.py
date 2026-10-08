#!/usr/bin/env python3
# 把新的 --timeout 校验文案同步进6 份语言表。
# 逐行做，不用正则：key 本身含中文标点与冒号，任何正则都容易把锚点行和新增行一起吃掉。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]

OLD_KEY = "错误：--timeout 需要非负秒数（0 = 不启用兜底），收到: "
NEW_KEY = "错误：--timeout 需要 0 到 31536000 之间的秒数（0 = 不启用兜底），收到: "

# (zh_key, en, ja, ko, de, fr, es)
NEW_ROWS = [
    ("错误：--timeout 需要 0 到 31536000 之间的秒数（0 = 永久运行），收到: ",
     "Error: --timeout needs a number of seconds between 0 and 31536000 (0 = run forever), got: ",
     "エラー: --timeout には 0 から 31536000 までの秒数（0 = 無期限で実行）が必要です。受信値: ",
     "오류: --timeout 에는 0 부터 31536000 까지 의 초(0 = 무제한 실행)가 필요합니다. 입력값: ",
     "Fehler: --timeout erwartet eine Sekundenzahl zwischen 0 und 31536000 (0 = unbegrenzt laufen), erhalten: ",
     "Erreur : --timeout attend un nombre de secondes entre 0 et 31536000 (0 = exécution illimitée), reçu : ",
     "Error: --timeout requiere un número de segundos entre 0 y 31536000 (0 = ejecución indefinida), recibido: "),
    ("daemon: --timeout 取值非法: ",
     "daemon: invalid --timeout value: ",
     "daemon: --timeout の値が無効です: ",
     "daemon: --timeout 값이 잘못되었습니다: ",
     "daemon: ungültiger Wert für --timeout: ",
     "daemon : valeur de --timeout invalide : ",
     "daemon: valor de --timeout no válido: "),
    ("nosleep-daemon: --timeout 取值非法: ",
     "nosleep-daemon: invalid --timeout value: ",
     "nosleep-daemon: --timeout の値が無効です: ",
     "nosleep-daemon: --timeout 값이 잘못되었습니다: ",
     "nosleep-daemon: ungültiger Wert für --timeout: ",
     "nosleep-daemon : valeur de --timeout invalide : ",
     "nosleep-daemon: valor de --timeout no válido: "),
]

IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}

# 旧 key 对应的旧译文，换key 时必须连value 一起换，否则会出现
# 「key 说要 0-31536000、译文还是「非负数」」这种自相矛盾的提示。
OLD_VALUES = {
    "EN": "Error: --timeout needs a non-negative number of seconds (0 = no fallback), got: ",
    "JA": "エラー: --timeout には 0 以上の秒数（0 = フォールバックなし）が必要です。受信値: ",
    "KO": "오류: --timeout 에는 0 이상의 초(0 = 대체 사용 안 함)가 필요합니다. 입력값: ",
    "DE": "Fehler: --timeout erwartet eine nicht negative Sekundenzahl (0 = kein Rückfall), erhalten: ",
    "FR": "Erreur : --timeout attend un nombre de secondes positif ou nul (0 = pas de repli), reçu : ",
    "ES": "Error: --timeout requiere un número de segundos no negativo (0 = sin recurso alternativo), recibido: ",
}

NEW_VALUES = {
    "EN": "Error: --timeout needs a number of seconds between 0 and 31536000 (0 = no fallback), got: ",
    "JA": "エラー: --timeout には 0 から 31536000 までの秒数（0 = フォールバックなし）が必要です。受信値: ",
    "KO": "오류: --timeout 에는 0 부터 31536000 까지 의 초(0 = 대체 사용 안 함)가 필요합니다. 입력값: ",
    "DE": "Fehler: --timeout erwartet eine Sekundenzahl zwischen 0 und 31536000 (0 = kein Rückfall), erhalten: ",
    "FR": "Erreur : --timeout attend un nombre de secondes entre 0 et 31536000 (0 = pas de repli), reçu : ",
    "ES": "Error: --timeout requiere un número de segundos entre 0 y 31536000 (0 = sin recurso alternativo), recibido: ",
}

for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    at = None
    for i, line in enumerate(lines):
        if '"%s"' % OLD_KEY in line:
            at = i
            break
    if at is None:
        print("%s: 锚点未找到，跳过" % lg)
        sys.exit(1)

    indent = lines[at][:len(lines[at]) - len(lines[at].lstrip())]

    # 1) 整行替换。key 与 value 必须一起换：只换 key 会留下
# 「key 说要 0-31536000、译文还是「非负数」」这种自相矛盾的提示。
    new_line = '%s"%s": "%s",' % (indent, NEW_KEY, NEW_VALUES[lg])
    assert '"%s":' % OLD_KEY in lines[at], "%s: 锚点行 key 不符: %r" % (lg, lines[at])
    assert OLD_VALUES[lg] in lines[at], "%s: 锚点行译文不符: %r" % (lg, lines[at])
    lines[at] = new_line

    # 2) 在其后插入三条新条目
    block = []
    for row in NEW_ROWS:
        zh = row[0]
        val = row[IDX[lg]]
        block.append('%s"%s": "%s",' % (indent, zh, val))
    lines[at + 1:at + 1] = block

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 改1 行 + 新增 %d 行" % (lg, len(block)))