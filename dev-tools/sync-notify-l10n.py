#!/usr/bin/env python3
"""同步「通知收缩 + 文案瘦身」这一轮改动带来的文案表变更。

做两件事：
  1. 删掉 REMOVE 里的死键 —— 改文案后旧键没有任何调用点了，
     check-l10n.py 会把它们当死键直接判失败（这是对的：留着会让人以为功能还在）。
  2. 把 ADD 里的新键写进全部七张表（EN 是基线，必须最先有）。

为什么写成脚本而不是手改：一共 23 个新键 × 6 种语言 = 138 条译文 + 30 条删除，
手改必然漏行，而漏翻的表现是「中文环境完全正常、外文环境露出中文」——
作者自测发现不了，只能靠 check-l10n.py 事后抓。一次写对省一轮返工。

用法：python3 dev-tools/sync-notify-l10n.py [仓库根目录]
"""
import pathlib
import re
import sys

LANGS = ["EN", "DE", "ES", "FR", "JA", "KO"]

# 死键：本轮改文案后已经没有调用点。逐行删。
REMOVE = [
    "（未生效）",
    "（合盖不睡未生效）",
    "（息屏保持唤醒未生效）",
    "（息屏唤醒未生效）",
    "（常亮未生效）",
    "已按当前电源方案停止「合盖不睡」。如需长期保留，请把该方案的「合盖时」设为「保持唤醒」。",
    "（合盖不睡未生效，将在条件满足后自动重试）",
    "「合盖不睡」未能生效：需要提权助手，且电量需高于下限。详见「打开日志」。",
    "电源方案：",
    "「合盖时熄灭内屏」由合盖守护执行，因此需要先把某套方案里的「合盖时」设为「保持唤醒」；",
    "但同样意味着：关屏期间任何能碰到键盘鼠标的人仍可操作这台机器，只是看不见画面。",
    "关屏只是把背光调到 0，画面仍在渲染——这正是远程/屏幕共享仍能使用的原因。",
    # 注意这条不是 raw string：源码里写的是 `\n` 转义，比对前会先还原成真正的换行。
    "可能原因：电池电量低于下限 / 守护启动未确认。\n详见「打开日志」。",
    "提权助手：已安装 —— 防睡眠可覆盖电池供电与合盖。",
    "提权助手：未安装 —— 此时防睡眠仅在本机接电源时有效，",
    "提权助手：版本过旧 —— 缺少多持有者记账，关屏联动与手动防睡眠会互相关掉对方。",
    "点击「一键防睡眠」安装（弹一次系统密码框，仅授权单个脚本的固定参数）。",
    "装好后「合盖不睡」会自动生效，无需再点。",
    "热键失效时的安全网。设为「不启用」则一直保持黑屏，直到手动恢复或退出本程序。",
    "电池供电与合盖仍会睡眠。安装需输入登录密码，只授权一个脚本的四个固定参数。",
    "离开座位前请手动锁屏（⌃⌘Q）。",
    "请卸载后重新安装（需要输入一次登录密码）。",
    "（仅授权单个 root:wheel 脚本的四个固定参数）",
    "个别机型熄屏后亮度回不来时，可单独关掉它作为退路。",
    "合盖运行建议接电源使用；电池放电低于电量下限会自动停止。需要提权助手（下方安装）。",
    "后台每 24 小时查一次 GitHub 上的最新版本号；发现新版只在菜单栏打标，不弹窗打断。",
    "请求只读取公开的版本号，不上传任何本机信息。手动「检查更新…」不受这个开关限制。",
    "关闭后只能用菜单栏点击操作。热键由系统级 Carbon 链路注册，不需要「辅助功能 / 输入监控」授权，也不会因重装 App 而失效。",
    "点按上面的按钮，再直接按下新组合键即可；⌫ 清除，Esc 取消。系统级热键必须包含 ⌘ / ⌃ / ⌥ / ⇧ 中的至少一个。",
    "使用电池且正在放电时，剩余电量降到这个数值就触发下面的动作。拖到 0 表示不限制。插着电源时完全不干预。",
    # 面板最终改成「每项各自带原因」，这个整体前缀没有调用点了。
    " —— 未生效：",
]

# 新键 → 各语言译文。顺序即写入顺序（EN 表先写，作为基线）。
ADD = [
    ("缺少命令行工具", {
        "EN": "Command-line tool missing",
        "DE": "Kommandozeilen-Werkzeug fehlt",
        "ES": "Falta la herramienta de línea de comandos",
        "FR": "Outil en ligne de commande manquant",
        "JA": "コマンドラインツールが見つかりません",
        "KO": "명령줄 도구가 없습니다",
    }),
    ("需要先安装提权助手", {
        "EN": "Install the privileged helper first",
        "DE": "Zuerst den privilegierten Helfer installieren",
        "ES": "Instala primero el asistente con privilegios",
        "FR": "Installez d'abord l'assistant privilégié",
        "JA": "先に特権ヘルパーをインストールしてください",
        "KO": "먼저 권한 도우미를 설치하세요",
    }),
    ("提权助手失效，需重装", {
        "EN": "The privileged helper stopped working, reinstall it",
        "DE": "Der privilegierte Helfer funktioniert nicht mehr, bitte neu installieren",
        "ES": "El asistente con privilegios dejó de funcionar, reinstálalo",
        "FR": "L'assistant privilégié ne fonctionne plus, réinstallez-le",
        "JA": "特権ヘルパーが無効になりました。再インストールしてください",
        "KO": "권한 도우미가 작동하지 않습니다. 다시 설치하세요",
    }),
    ("电量低于下限", {
        "EN": "Battery below the floor",
        "DE": "Akku unter dem Mindestwert",
        "ES": "Batería por debajo del mínimo",
        "FR": "Batterie sous le seuil",
        "JA": "バッテリーが下限を下回っています",
        "KO": "배터리가 하한 미만",
    }),
    ("启动失败", {
        "EN": "Failed to start",
        "DE": "Start fehlgeschlagen",
        "ES": "No se pudo iniciar",
        "FR": "Échec du démarrage",
        "JA": "起動に失敗しました",
        "KO": "시작 실패",
    }),
    ("正在重试", {
        "EN": "Retrying",
        "DE": "Neuer Versuch läuft",
        "ES": "Reintentando",
        "FR": "Nouvelle tentative",
        "JA": "再試行中",
        "KO": "다시 시도 중",
    }),
    ("未知原因", {
        "EN": "Unknown reason",
        "DE": "Unbekannte Ursache",
        "ES": "Motivo desconocido",
        "FR": "Raison inconnue",
        "JA": "原因不明",
        "KO": "알 수 없는 원인",
    }),
    ("。点菜单可查看与重试。", {
        "EN": ". Open the menu to check and retry.",
        "DE": ". Öffne das Menü zum Prüfen und für einen neuen Versuch.",
        "ES": ". Abre el menú para comprobarlo y reintentar.",
        "FR": ". Ouvrez le menu pour vérifier et réessayer.",
        "JA": "。メニューで確認・再試行できます。",
        "KO": ". 메뉴에서 확인하고 다시 시도하세요.",
    }),
    ("（未生效：", {
        "EN": " (not active: ",
        "DE": " (nicht aktiv: ",
        "ES": " (no activo: ",
        "FR": " (non actif : ",
        "JA": "（未適用：",
        "KO": " (적용 안 됨: ",
    }),
    ("需先在某套方案里把「合盖时」设为「保持唤醒」；建议接电源使用。", {
        "EN": "First set \"When the lid closes\" to \"Keep awake\" in one power plan; AC power recommended.",
        "DE": "Setze in einem Energiesparmodus zuerst \"Beim Schließen des Deckels\" auf \"Wach bleiben\"; Netzbetrieb empfohlen.",
        "ES": "Primero pon «Al cerrar la tapa» en «Mantenerse despierto» en un plan de energía; se recomienda corriente.",
        "FR": "Réglez d'abord « À la fermeture du capot » sur « Rester éveillé » dans un plan d'alimentation ; secteur recommandé.",
        "JA": "先にいずれかの電源プランで「蓋を閉じたとき」を「スリープさせない」にしてください。電源接続を推奨します。",
        "KO": "먼저 한 전원 플랜에서 「덮개를 닫으면」을 「잠자지 않기」로 설정하세요. 전원 연결을 권장합니다.",
    }),
    ("关闭后只能用菜单栏点击操作。无需「辅助功能」授权，重装 App 也不会失效。", {
        "EN": "When off, use the menu bar only. No Accessibility permission needed, and reinstalling the app will not break it.",
        "DE": "Wenn aus, nur über die Menüleiste bedienen. Keine Bedienungshilfen-Berechtigung nötig, und eine Neuinstallation macht es nicht ungültig.",
        "ES": "Si se desactiva, usa solo la barra de menús. No requiere permiso de Accesibilidad y no se pierde al reinstalar la app.",
        "FR": "Désactivé, passez par la barre de menus. Aucune autorisation Accessibilité requise, et une réinstallation ne l'invalide pas.",
        "JA": "オフにするとメニューバーからのみ操作できます。アクセシビリティ権限は不要で、アプリを再インストールしても無効になりません。",
        "KO": "끄면 메뉴 막대에서만 조작할 수 있습니다. 손쉬운 사용 권한이 필요 없고, 앱을 다시 설치해도 유지됩니다.",
    }),
    ("按下新组合键即可；⌫ 清除，Esc 取消。必须含 ⌘ / ⌃ / ⌥ / ⇧ 至少一个。", {
        "EN": "Press the new combination; ⌫ clears, Esc cancels. At least one of ⌘ / ⌃ / ⌥ / ⇧ is required.",
        "DE": "Neue Kombination drücken; ⌫ löscht, Esc bricht ab. Mindestens eines von ⌘ / ⌃ / ⌥ / ⇧ ist nötig.",
        "ES": "Pulsa la nueva combinación; ⌫ borra, Esc cancela. Se requiere al menos uno de ⌘ / ⌃ / ⌥ / ⇧.",
        "FR": "Appuyez sur la nouvelle combinaison ; ⌫ efface, Esc annule. Au moins un de ⌘ / ⌃ / ⌥ / ⇧ est requis.",
        "JA": "新しい組み合わせを押してください。⌫ で消去、Esc で取消。⌘ / ⌃ / ⌥ / ⇧ のいずれかが最低一つ必要です。",
        "KO": "새 조합을 누르세요. ⌫ 지우기, Esc 취소. ⌘ / ⌃ / ⌥ / ⇧ 중 최소 하나가 필요합니다.",
    }),
    ("设为「不启用」则一直保持黑屏，直到手动恢复或退出。", {
        "EN": "\"Off\" keeps the screen black until you restore it or quit.",
        "DE": "\"Aus\" hält den Bildschirm schwarz, bis du ihn zurückholst oder beendest.",
        "ES": "«Desactivado» mantiene la pantalla en negro hasta que la restaures o salgas.",
        "FR": "« Désactivé » garde l'écran noir jusqu'à restauration manuelle ou fermeture.",
        "JA": "「無効」にすると、手動で戻すか終了するまで黒画面のままになります。",
        "KO": "「사용 안 함」으로 두면 직접 복구하거나 종료할 때까지 화면이 검은 상태로 유지됩니다.",
    }),
    ("用电池放电时，降到这个数值就触发下面的动作；拖到 0 不限制。接电源时不干预。", {
        "EN": "On battery while discharging, the action below triggers at this level; 0 means no limit. AC power is never affected.",
        "DE": "Im Akkubetrieb beim Entladen löst diese Schwelle die folgende Aktion aus; 0 bedeutet kein Limit. Am Netzteil greift sie nie.",
        "ES": "Con batería y descargando, la acción de abajo se activa en este nivel; 0 significa sin límite. Con corriente no interviene.",
        "FR": "Sur batterie en décharge, l'action ci-dessous se déclenche à ce niveau ; 0 signifie aucune limite. Sur secteur, aucune intervention.",
        "JA": "バッテリー放電中にこの値まで下がると下の動作を実行します。0 で無制限。電源接続時は何もしません。",
        "KO": "배터리 방전 중 이 값에 도달하면 아래 동작을 실행합니다. 0이면 제한 없음. 전원 연결 시에는 개입하지 않습니다.",
    }),
    ("每 24 小时查一次版本号；发现新版只在菜单栏打标，不弹窗、不上传任何本机信息。", {
        "EN": "Checks the version once every 24 hours; a new version only adds a menu bar badge — no popup, no local data uploaded.",
        "DE": "Prüft die Version alle 24 Stunden; eine neue Version setzt nur eine Markierung in der Menüleiste — kein Popup, keine lokalen Daten werden gesendet.",
        "ES": "Comprueba la versión cada 24 horas; una versión nueva solo marca la barra de menús — sin avisos y sin subir datos locales.",
        "FR": "Vérifie la version toutes les 24 heures ; une nouvelle version ajoute juste un repère dans la barre de menus — sans popup ni envoi de données locales.",
        "JA": "24 時間ごとにバージョンを確認します。新しい版ではメニューバーに印を付けるだけで、ポップアップも本機情報の送信もありません。",
        "KO": "24시간마다 버전을 확인합니다. 새 버전은 메뉴 막대에 표시만 하고, 팝업도 로컬 정보 전송도 없습니다.",
    }),
    ("关屏只是把背光调到 0，画面仍在渲染：远程桌面因此可用，也让能碰到键鼠的人能盲操作。", {
        "EN": "Blackout only drops the backlight to 0 — the screen keeps rendering. That is why remote desktop still works, and why anyone with physical access can still operate the Mac blind.",
        "DE": "Ausschalten setzt nur die Hintergrundbeleuchtung auf 0 — das Bild wird weiter gerendert. Deshalb funktioniert Remote-Desktop, und deshalb kann jeder mit Zugriff zum Gerät den Mac blind bedienen.",
        "ES": "Apagar solo baja el brillo a 0: la imagen sigue renderizándose. Por eso funciona el escritorio remoto, y por eso quien tenga acceso físico puede operar el Mac a ciegas.",
        "FR": "Éteindre l'écran ne fait que mettre le rétroéclairage à 0 : l'image continue d'être rendue. C'est pourquoi le bureau à distance fonctionne, et pourquoi une personne ayant accès au clavier peut piloter le Mac sans voir l'écran.",
        "JA": "画面オフはバックライトを 0 にするだけで、描画は続いています。だからリモートデスクトップが使え、だからこそ本体に触れられる人は画面が見えなくても操作できます。",
        "KO": "화면 끄기는 백라이트를 0으로 낮출 뿐 그리기는 계속됩니다. 그래서 원격 데스크톱이 되고, 그래서 키보드에 손이 닿는 사람은 화면 없이도 조작할 수 있습니다.",
    }),
    ("离开前请锁屏（⌃⌘Q）。", {
        "EN": "Lock the screen (⌃⌘Q) before you walk away.",
        "DE": "Bildschirm vor dem Weggehen sperren (⌃⌘Q).",
        "ES": "Bloquea la pantalla (⌃⌘Q) antes de irte.",
        "FR": "Verrouillez l'écran (⌃⌘Q) avant de partir.",
        "JA": "離席前に画面をロックしてください（⌃⌘Q）。",
        "KO": "자리를 뜨기 전에 화면을 잠그세요(⌃⌘Q).",
    }),
    ("提权助手：版本过旧，请卸载后重装（关屏联动与手动防睡眠会互相干扰）。", {
        "EN": "Privileged helper: too old, reinstall it (blackout linking and manual anti-sleep interfere with each other).",
        "DE": "Privilegierter Helfer: zu alt, bitte neu installieren (Bildschirm-Kopplung und manuelles Wachhalten stören sich gegenseitig).",
        "ES": "Asistente con privilegios: demasiado antiguo, reinstálalo (el vínculo con el apagado y el anti-suspensión manual se estorban).",
        "FR": "Assistant privilégié : trop ancien, réinstallez-le (le lien avec l'extinction et l'anti-veille manuel se gênent).",
        "JA": "特権ヘルパー：古すぎます。アンインストールして再インストールしてください（画面オフ連動と手動のスリープ防止が干渉します）。",
        "KO": "권한 도우미: 너무 오래되었습니다. 삭제 후 다시 설치하세요(화면 끄기 연동과 수동 잠자기 방지가 서로 간섭합니다).",
    }),
    ("提权助手：已安装（可覆盖电池与合盖；仅授权一个脚本的四个固定参数）", {
        "EN": "Privileged helper: installed (covers battery and a closed lid; only four fixed arguments of one script are authorized)",
        "DE": "Privilegierter Helfer: installiert (deckt Akku und geschlossenen Deckel ab; nur vier feste Argumente eines Skripts sind autorisiert)",
        "ES": "Asistente con privilegios: instalado (cubre batería y tapa cerrada; solo se autorizan cuatro argumentos fijos de un script)",
        "FR": "Assistant privilégié : installé (couvre la batterie et le capot fermé ; seuls quatre arguments fixes d'un script sont autorisés)",
        "JA": "特権ヘルパー：インストール済み（バッテリーと蓋閉じに対応。スクリプト 1 本の固定引数 4 つのみを許可）",
        "KO": "권한 도우미: 설치됨(배터리와 덮개 닫힘까지 적용. 스크립트 하나의 고정 인수 4개만 허용)",
    }),
    ("提权助手：未安装（防睡眠仅接电源时有效，电池与合盖仍会睡眠；安装需输入登录密码）", {
        "EN": "Privileged helper: not installed (anti-sleep works on AC power only; the Mac still sleeps on battery or with the lid closed. Installing asks for your login password)",
        "DE": "Privilegierter Helfer: nicht installiert (Wachhalten wirkt nur am Netzteil; im Akkubetrieb und bei geschlossenem Deckel schläft der Mac weiter. Zum Installieren ist das Anmeldepasswort nötig)",
        "ES": "Asistente con privilegios: no instalado (el anti-suspensión solo funciona con corriente; con batería o tapa cerrada el Mac sigue suspendiéndose. Instalar pide tu contraseña de inicio de sesión)",
        "FR": "Assistant privilégié : non installé (l'anti-veille n'agit que sur secteur ; sur batterie ou capot fermé, le Mac dort encore. L'installation demande votre mot de passe de session)",
        "JA": "特権ヘルパー：未インストール（スリープ防止は電源接続時のみ有効。バッテリー時や蓋を閉じた状態ではスリープします。インストールにはログインパスワードが必要です）",
        "KO": "권한 도우미: 설치되지 않음(잠자기 방지는 전원 연결 시에만 적용되고, 배터리 사용이나 덮개를 닫으면 여전히 잠자기 상태가 됩니다. 설치하려면 로그인 암호가 필요합니다)",
    }),
    ("安装会弹一次系统密码框，装好后自动生效，无需再点。", {
        "EN": "Installing shows one system password prompt; it takes effect automatically afterwards.",
        "DE": "Die Installation zeigt einmal die System-Passwortabfrage; danach wirkt es automatisch.",
        "ES": "La instalación muestra una vez el cuadro de contraseña del sistema; después se aplica solo.",
        "FR": "L'installation affiche une fois la demande de mot de passe système ; ensuite, tout s'applique automatiquement.",
        "JA": "インストール時にシステムのパスワード入力が 1 回だけ表示され、その後は自動で有効になります。",
        "KO": "설치할 때 시스템 암호 입력창이 한 번 뜨고, 그 뒤에는 자동으로 적용됩니다.",
    }),
]

# 单行条目：四个空格缩进 + 字符串键 + 冒号 + 字符串值 + 逗号
ENTRY_RE = re.compile(r'^    ("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*"),\s*$')


def esc(s: str) -> str:
    """转成 Swift 字符串字面量的转义形式。"""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unesc(lit: str) -> str:
    """还原字面量，便于与纯文本键比较。"""
    body = lit[1:-1]
    out, i = [], 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            n = body[i + 1]
            out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"', "0": "\0"}.get(n, n))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def sync(root: pathlib.Path) -> int:
    remove = set(REMOVE)
    added_total, removed_total = 0, 0

    for lang in LANGS:
        p = root / "Sources" / "Shared" / f"L10n{lang}.swift"
        if not p.exists():
            print(f"  ! 找不到 {p}")
            return 1
        lines = p.read_text(encoding="utf-8").split("\n")

        # 现有键（用于幂等：已存在的键不重复插入）
        present = set()
        for l in lines:
            m = ENTRY_RE.match(l)
            if m:
                present.add(unesc(m.group(1)))

        kept, removed = [], 0
        for l in lines:
            m = ENTRY_RE.match(l)
            if m and unesc(m.group(1)) in remove:
                removed += 1
                continue
            kept.append(l)

        # 在收尾的 `]` 之前插入新键
        new_lines = [f"    {esc(k)}: {esc(v[lang])}," for k, v in ADD if k not in present]
        if new_lines:
            idx = next((i for i in range(len(kept) - 1, -1, -1)
                        if kept[i].strip() == "]"), None)
            if idx is None:
                print(f"  ! {p} 找不到收尾的 ']'")
                return 1
            kept[idx:idx] = new_lines

        p.write_text("\n".join(kept), encoding="utf-8")
        print(f"  ✓ L10n{lang}: 删 {removed} 条死键，加 {len(new_lines)} 条新译文")
        added_total += len(new_lines)
        removed_total += removed

    print(f"\n合计：删 {removed_total} 条，加 {added_total} 条。"
          f"（删=X 因为每张表各有一份）")
    return 0


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    print(f"仓库根目录：{root}")
    sys.exit(sync(root))
