#!/usr/bin/env python3
# 补「未知参数 / 漏值」两条报错的六语翻译。
# 起因：P2-4「未知参数一律静默忽略，退出码仍是 0」。`lidkeep config --battary 50`
# （少一个 e）整条被跳过、命令正常走完、配置一个字节没改。
# key 含中文冒号，只能整行插入，不要用正则（见 sync-timeout-l10n.py 的教训）。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}
ANCHOR = '"错误：--restore 需要 original（关屏前亮度）或 0.0-1.0 的数值，收到: "'

ROWS = [
    (
        "错误：未知参数 ",
        "Error: unknown option ",
        "エラー：不明なオプション ",
        "오류: 알 수 없는 옵션 ",
        "Fehler: unbekannte Option ",
        "Erreur : option inconnue ",
        "Error: opción desconocida ",
    ),
    (
        " 可用选项：",
        " available options: ",
        " 利用可能なオプション：",
        " 사용 가능한 옵션: ",
        " verfügbare Optionen: ",
        " options disponibles : ",
        " opciones disponibles: ",
    ),
    (
        "完整说明：lidkeep help",
        "Full help: lidkeep help",
        "詳しい説明：lidkeep help",
        "전체 도움말: lidkeep help",
        "Vollständige Hilfe: lidkeep help",
        "Aide complète : lidkeep help",
        "Ayuda completa: lidkeep help",
    ),
    (
        "错误：",
        "Error: ",
        "エラー：",
        "오류: ",
        "Fehler: ",
        "Erreur : ",
        "Error: ",
    ),
    (
        " 需要一个值",
        " needs a value",
        " には値が必要です",
        " 값이 필요합니다",
        " braucht einen Wert",
        " nécessite une valeur",
        " necesita un valor",
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
            print("%s: 已存在，跳过「%s」" % (lg, key))
            continue
        lines.insert(at + 1, '%s"%s": "%s",' % (indent, key, vals[IDX[lg] - 1]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 已处理 %d 条" % (lg, len(ROWS)))

sys.exit(1 if failed else 0)
