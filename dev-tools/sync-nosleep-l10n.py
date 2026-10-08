#!/usr/bin/env python3
# 补本轮 P2 收尾引入的两条文案的六语翻译：
#   ① 「disablesleep 复位失败」—— recoverStaleNosleep / stop 两处原本 `_ = helperExec("off")`
#      之后无条件打印「已复位」，助手授权失效时会报成功；改回读校验后多出这条失败文案。
#   ② 「状态文件写不进去就取消关屏」—— 原先 stateFile 用 `try?` 写，磁盘满时静默失败，
#      进程照样把亮度设成 0 且不留记录；改成写失败即拒绝关屏后多出这条。
# key 含中文冒号与括号，只能整行插入，不要用正则（见 sync-timeout-l10n.py 的教训）。
import sys

LANGS = ["EN", "JA", "KO", "DE", "FR", "ES"]
IDX = {lg: i + 1 for i, lg in enumerate(LANGS)}

# (锚点行片段, [(key, EN, JA, KO, DE, FR, ES), ...])；新条目插在锚点**之后**
SECTIONS = [
    (
        '"nosleep: 检测到 disablesleep 仍开启但无守护进程，已自动复位"',
        [
            (
                "nosleep: disablesleep 复位失败，系统仍不会睡眠（提权助手授权可能已失效，重装可修复）",
                "nosleep: could not reset disablesleep — the system still will not sleep "
                "(the privileged helper's authorization may have expired; reinstalling fixes it)",
                "nosleep: disablesleep のリセットに失敗しました。システムはまだスリープしません"
                "（特権ヘルパーの認証が失効している可能性があります。再インストールで修復できます）",
                "nosleep: disablesleep 초기화에 실패했습니다. 시스템은 여전히 잠들지 않습니다"
                " (권한 도우미의 인증이 만료되었을 수 있습니다. 재설치하면 복구됩니다)",
                "nosleep: disablesleep konnte nicht zurückgesetzt werden — das System schläft weiterhin nicht"
                " (die Autorisierung des privilegierten Helfers ist möglicherweise abgelaufen;"
                " eine Neuinstallation behebt das)",
                "nosleep: échec de la réinitialisation de disablesleep — le système ne se mettra toujours pas"
                " en veille (l’autorisation de l’assistant privilégié a peut-être expiré ;"
                " une réinstallation corrige le problème)",
                "nosleep: no se pudo restablecer disablesleep — el sistema seguirá sin dormir"
                " (la autorización del asistente con privilegios puede haber caducado;"
                " reinstalarlo lo soluciona)",
            ),
        ],
    ),
    (
        '"daemon 启动 pid="',  # daemon 启动那一段，与状态文件写入点相邻
        [
            (
                "无法写入状态文件（磁盘可能已满），已取消关屏以免亮度无法恢复",
                "cannot write the state file (the disk may be full); blanking was cancelled so the "
                "brightness can still be restored",
                "状態ファイルに書き込めません（ディスクが満杯の可能性）。輝度を復元できなくなるのを避けるため、"
                "消灯を中止しました",
                "상태 파일에 쓸 수 없습니다 (디스크가 가득 찼을 수 있음). 밝기를 복원할 수 없게 되는 것을 막기 위해"
                " 화면 끄기를 취소했습니다",
                "die Statusdatei lässt sich nicht schreiben (die Festplatte ist möglicherweise voll);"
                " das Abdunkeln wurde abgebrochen, damit die Helligkeit noch wiederhergestellt werden kann",
                "impossible d’écrire le fichier d’état (le disque est peut-être plein) ; l’extinction a été"
                " annulée pour que la luminosité puisse encore être restaurée",
                "no se puede escribir el archivo de estado (puede que el disco esté lleno); se canceló el"
                " apagado de pantalla para que el brillo aún pueda restaurarse",
            ),
        ],
    ),
]

failed = False
for lg in LANGS:
    path = "Sources/Shared/L10n%s.swift" % lg
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for anchor, rows in SECTIONS:
        at = next((i for i, l in enumerate(lines) if anchor in l), None)
        if at is None:
            print("%s: 锚点未找到 -> %s" % (lg, anchor))
            failed = True
            continue
        indent = lines[at][: len(lines[at]) - len(lines[at].lstrip())]
        for key, *vals in reversed(rows):
            if any('"%s"' % key in l for l in lines):
                print("%s: 已存在，跳过「%s」" % (lg, key[:16]))
                continue
            lines.insert(at + 1, '%s"%s": "%s",' % (indent, key, vals[IDX[lg] - 1]))
            print("%s: 已插入「%s」" % (lg, key[:16]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

sys.exit(1 if failed else 0)
