#!/usr/bin/env python3
# 把「部分屏幕未能熄屏」相关的新文案同步进 6 份语言表。
# 逐行处理，不用正则：key 含中文标点与冒号，正则容易把相邻行一起吃掉。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}

# 插在哪个已有 key 之后（用来定位插入点，不改动它）
ANCHOR = '"警告：首次设置亮度 0 失败"'

# (zh_key, en, ja, ko, de, fr, es)
NEW_ROWS = [
    ("部分屏幕未能熄屏：",
     "Some displays could not be blanked: ",
     "一部のディスプレイを消光できませんでした: ",
     "일부 디스플레이를 끄지 못했습니다: ",
     "Einige Displays konnten nicht abgeschaltet werden: ",
     "Certains écrans n’ont pas pu être éteints : ",
     "Algunas pantallas no se pudieron apagar: "),
    ("（外接显示器通常不支持软件调亮度）",
     " (external displays usually have no software brightness control)",
     " （外付けディスプレイはソフトウェアの輝度調整に対応していないことがよくあります）",
     " (외부 디스플레이는 일반적으로 소프트웨어 밝기 조정을 지원하지 않습니다)",
     " ( externe Displays bieten meist keine softwaregesteuerte Helligkeitsregelung)",
     " (les écrans externes ne gèrent généralement pas la luminosité logicielle)",
     " (los monitores externos suelen no admitir control de brillo por software)"),
    ("读不到当前亮度（DisplayServices 无返回），恢复时将用 0.35；结束后可自行调回原亮度",
     "Current brightness could not be read (DisplayServices returned nothing); 0.35 will be used on restore, adjust it back yourself afterwards",
     "現在の明るさを読み取れません（DisplayServices が値を返しませんでした）。復元には 0.35 を使うので、完了後に元の明るさへ戻してください",
     "현재 밝기를 읽을 수 없습니다(DisplayServices 가 값을 반환하지 않음). 복원 시 0.35 를 사용하며, 작업 후 원래 밝기로 되돌리세요",
     "Aktuelle Helligkeit konnte nicht gelesen werden (DisplayServices lieferte nichts); es wird 0.35 verwendet, danach bitte selbst zurückstellen",
     "La luminosité actuelle n’a pas pu être lue (DisplayServices n’a rien renvoyé) ; 0.35 sera utilisé, ajustez ensuite vous-même",
     "No se pudo leer el brillo actual (DisplayServices no devolvió nada); se usará 0.35 y podrás ajustarlo después"),
]

for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    at = None
    for i, line in enumerate(lines):
        if ANCHOR in line:
            at = i
            break
    if at is None:
        print("%s:锚点未找到" % lg)
        sys.exit(1)

    indent = lines[at][: len(lines[at]) - len(lines[at].lstrip())]
    block = []
    for row in NEW_ROWS:
        block.append('%s"%s": "%s",' % (indent, row[0], row[IDX[lg]]))
    lines[at + 1 : at + 1] = block

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("%s: 新增 %d 行（插在第 %d 行后）" % (lg, len(block), at + 1))