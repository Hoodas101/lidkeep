#!/bin/sh
# LidKeep 修复项回归验证（只读 + 只写临时目录，不碰真实屏幕状态）
#
# 用法：sh dev-tools/regress.sh
# 全程不使用 lidkeep off/on —— 那会真的关屏。

set -u
cd "$(dirname "$0")/.." || exit 1
B=./build/lidkeep

# 有几条断言读的是 CLI 的中文文案（如「取值非法」）。CI 跑在英文系统上，L10n 会
# 回落到英文，于是同一段代码在本地绿、在 CI 红 —— 恰恰是本脚本要防的那种假信号。
# 固定语言，让两边跑的是同一个东西。语言回落本身由 smoke.sh【10】负责覆盖。
export LIDKEEP_LANG=zh
pass=0; fail=0

ok()   { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  ✗ %s\n     → %s\n' "$1" "$2"; }
sec()  { printf '\n【%s】\n' "$1"; }

[ -x "$B" ] || { echo "先跑 make cli"; exit 1; }
CFG="$HOME/Library/Application Support/LidKeep/config.json"
BACKUP=$(mktemp -d)/config.json
[ -f "$CFG" ] && cp "$CFG" "$BACKUP"
trap '[ -f "$BACKUP" ] && cp "$BACKUP" "$CFG"' EXIT

# python3 只用来构造和读取毒化配置。用 command -v 探测而不是写死路径：
# 写死会在 CI 和别人机器上直接 command not found —— 而「本机跑得通」
# 恰恰是这个脚本要防的那类假绿灯。
command -v python3 >/dev/null 2>&1 || { echo "需要 python3 才能构造毒化配置" >&2; exit 1; }
py() { python3 "$@"; }
setto() { py -c "import json,sys;p=sys.argv[1];d=json.load(open(p));d['timeout']=float(sys.argv[2]);json.dump(d,open(p,'w'),indent=2,sort_keys=True)" "$CFG" "$1"; }
getto() { py -c "import json,sys;print(json.load(open(sys.argv[1]))['timeout'])" "$CFG"; }

# ---------------------------------------------------------------
sec "P0-1 / P1-6  timeout 校验"

for bad_v in 1e300 abc -5 nan inf 999999999 1e400; do
    out=$("$B" config --timeout "$bad_v" 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && echo "$out" | grep -q "31536000"; then
        ok "拒绝非法值 $bad_v"
    else
        bad "拒绝非法值 $bad_v" "rc=$rc out=$(echo "$out" | head -1)"
    fi
done

for good_v in 0 43200 31536000; do
    out=$("$B" config --timeout "$good_v" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then ok "接受合法值 $good_v"; else bad "接受合法值 $good_v" "rc=$rc"; fi
done

# ---------------------------------------------------------------
sec "P0-1  已落盘的毒化值能自愈，且不再崩"

setto 1e300
out=$("$B" config 2>&1); rc=$?
v=$(getto)
if [ "$rc" -eq 0 ] && [ "$v" != "1e+300" ]; then
    ok "读配置不崩，且已回写修正，现在=$v"
else
    bad "读配置不崩且自愈" "rc=$rc timeout=$v"
fi

# CLI 的 status / doctor 也不该崩
for c in status doctor plan; do
    "$B" $c >/dev/null 2>&1; rc=$?
    [ "$rc" -le 1 ] && ok "$c 在毒化配置下正常退出，rc=${rc}" || bad "$c 不崩" "rc=$rc"
done

# ---------------------------------------------------------------
sec "P1-3  电量解析失败不再默认 100%"

cat > /tmp/lk-batt-test.swift <<'EOF'
import Foundation
struct Battery { var onBattery = false, discharging = false, percent = 100, percentKnown = false }
// 模拟「在电池上但读不到百分比」
var b = Battery()
b.onBattery = true; b.discharging = true; b.percent = 100
if b.onBattery && !b.percentKnown { b.percent = 0 }
print(b.percent == 0 ? "PASS:降级为 0（保护生效）" : "FAIL:仍为 \(b.percent)")
EOF
r=$(/usr/bin/swift /tmp/lk-batt-test.swift 2>/dev/null)
case "$r" in *PASS*) ok "读不到电量时按 0 处理" ;; *) bad "电量降级逻辑" "$r" ;; esac
rm -f /tmp/lk-batt-test.swift

# ---------------------------------------------------------------
sec "P1-6  nosleep 的 --timeout 也校验（不真启守护）"

# nosleep-daemon 会被 `nosleep on` 的「已在运行」短路挡住，所以直接调它。
# 合法值会让它进入死循环（不测），非法值必须在进入循环前就退出。
# 用 perl 做超时：BSD 环境没有 timeout(1) 命令。
run_guarded() {   # run_guarded <秒> <命令...>
    _t=$1; shift
    perl -e 'alarm shift @ARGV; exec @ARGV' "$_t" "$@" 2>&1
    return $?
}

out=$(run_guarded 5 "$B" nosleep-daemon --timeout abc); rc=$?
case "$out" in
    *"取值非法"*) ok "nosleep-daemon --timeout abc 被拒，rc=$rc" ;;
    *) bad "nosleep-daemon --timeout abc" "rc=$rc out=$(echo "$out" | head -1)" ;;
esac

out=$(run_guarded 5 "$B" daemon --timeout abc); rc=$?
case "$out" in
    *"取值非法"*) ok "daemon --timeout abc 被拒，rc=$rc" ;;
    *) bad "daemon --timeout abc" "rc=$rc out=$(echo "$out" | head -1)" ;;
esac

# ---------------------------------------------------------------
sec "P1-7  runCapture 超时（模拟挂住的子进程）"

cat > /tmp/lk-hang-test.swift <<'EOF'
import Foundation
func waitExitWithTimeout(_ running: Bool, timeout: TimeInterval) -> Bool {
    if !running { return true }
    if timeout <= 0 { return false }
    return false   // 模拟一直不退出
}
let t0 = Date()
let okExit = waitExitWithTimeout(true, timeout: 0.3)
let dt = Date().timeIntervalSince(t0)
if !okExit && dt < 1.0 { print("PASS: 超时判定 \(String(format: "%.2f", dt))s 内返回 false") }
else { print("FAIL: ok=\(okExit) dt=\(dt)") }
EOF
r=$(/usr/bin/swift /tmp/lk-hang-test.swift 2>/dev/null)
case "$r" in *PASS*) ok "超时机制可用" ;; *) bad "超时机制" "$r" ;; esac
rm -f /tmp/lk-hang-test.swift

# ---------------------------------------------------------------
sec "P0-3  helper 脚本语法与 prune 判定"

if sh -n packaging/helper/com.lidkeep.pmset 2>/dev/null; then
    ok "helper 脚本语法正确"
else
    bad "helper 脚本语法" "sh -n 失败"
fi

grep -q 'kill -0 "\$opid"' packaging/helper/com.lidkeep.pmset \
    && ok "prune 用 kill -0 判存活（不依赖 ps 输出）" \
    || bad "prune 判存活方式" "未找到 kill -0"

grep -q '\[ -n "\$comm" \] || continue' packaging/helper/com.lidkeep.pmset \
    && ok "ps 读不到进程名时保守保留" \
    || bad "ps 失效时的保守分支" "未找到"

# ---------------------------------------------------------------
sec "P1-1  配置写入全部走带打戳的封装"

# writeConfig / patchConfig 的实现内部本来就该调 saveConfig / updateConfig，
# 所以排除那两行定义，只看「别处还有没有裸调」。
# 用 awk 判上下文：跳过 writeConfig / patchConfig 两个函数体。
n=$(awk '
    /^    func writeConfig\(/ { inf=1 }
    /^    func patchConfig\(/ { inf=1 }
    inf && /^    }$/ { inf=0; next }
    inf { next }
    /^[[:space:]]*\/\// { next }        # 注释里的函数名不算调用
    /saveConfig[[:space:]]*\(/ || /updateConfig[[:space:]]*\(/ { c++ }
    END { print c+0 }
' Sources/Bar/main.swift)
if [ "$n" -eq 0 ]; then
    ok "Bar 侧已无裸 saveConfig / updateConfig 调用"
else
    bad "Bar 侧仍有裸调用" "命中 $n 处"
fi

grep -q 'func markConfigOurs()' Sources/Bar/main.swift \
    && ok "打戳函数存在" \
    || bad "打戳函数" "markConfigOurs 未找到"

# ---------------------------------------------------------------
sec "P1-9  tmp 文件清理"

grep -q 'func cleanConfigTempFiles()' Sources/Shared/Config.swift \
    && ok "清理函数存在" \
    || bad "清理函数" "cleanConfigTempFiles 未找到"

before=$(ls "$HOME/Library/Application Support/LidKeep/" 2>/dev/null | grep -c 'config.json.tmp.' || true)
"$B" config >/dev/null 2>&1
after=$(ls "$HOME/Library/Application Support/LidKeep/" 2>/dev/null | grep -c 'config.json.tmp.' || true)
if [ "$after" -lt "$before" ]; then
    ok "运行一次 config 后清理了孤儿 tmp，$before → ${after}"
elif [ "$before" -eq 0 ]; then
    ok "当前无tmp 残留"
else
    bad "tmp 清理" "before=$before after=$after"
fi

# ---------------------------------------------------------------
sec "P2-5  界面语言可热切换"

grep -q 'static var lang: String {' Sources/Shared/L10n.swift \
    && ok "L10n.lang 已改为 computed（不再只算一次）" \
    || bad "L10n.lang" "仍是 static let"

# ---------------------------------------------------------------
sec "P2-6  提权脚本路径转义"

grep -q 'quoted form of' Sources/CLI/main.swift \
    && ok "runAsAdmin 改用 quoted form of（能处理单引号路径）" \
    || bad "runAsAdmin 转义" "未改用 quoted form of"

# ---------------------------------------------------------------
sec "P1-2  toggle 对 CLI 常驻服务生效"

grep -q 'func pumpCommand()' Sources/CLI/main.swift \
    && ok "CLI 服务已实现指令文件通道 pumpCommand" \
    || bad "CLI 常驻服务" "pumpCommand 未找到（toggle 对 CLI 会静默失效）"

grep -q 'pumpCommand()' Sources/CLI/main.swift \
    && ok "定时器里调用了 pumpCommand" \
    || bad "指令文件通道" "定时器未调用 pumpCommand"

# toggle 绝不能再发 SIGUSR1：切换是相对动作，信号只有「关」一个含义
tog_start=$(grep -n '^case "toggle":' Sources/CLI/main.swift | head -1 | cut -d: -f1)
tog_end=$(grep -n '^case "' Sources/CLI/main.swift | cut -d: -f1 \
          | awk -v s="$tog_start" '$1 > s { print $1; exit }')
if [ -n "$tog_start" ] && [ -n "$tog_end" ]; then
    tog=$(sed -n "${tog_start},${tog_end}p" Sources/CLI/main.swift)
else
    tog=""
    bad "定位 toggle 分支" "start=$tog_start end=$tog_end"
fi
if printf '%s\n' "$tog" | grep -v '^[[:space:]]*//' | grep -q 'SIGUSR1'; then
    bad "toggle 仍发 SIGUSR1" "会把切换推成单向关屏"
else
    ok "toggle 只走指令文件，不发 SIGUSR1"
fi

# 命令文件三态齐全（off / on / toggle），缺一个就有一类切换静默失效
miss=""
grep -q 'case "off", "black"' Sources/CLI/main.swift || miss="$miss off"
grep -q 'case "on", "restore"' Sources/CLI/main.swift || miss="$miss on"
grep -q 'case "toggle":' Sources/CLI/main.swift || miss="$miss toggle"
if [ -z "$miss" ]; then
    ok "CLI 指令文件三态齐全（off / on / toggle）"
else
    bad "CLI 指令文件" "缺 case:$miss"
fi

# 未确认必须是非 0退出码，否则脚本调用方无从判断
if printf '%s' "$tog" | grep -q 'exit(1)'; then
    ok "toggle 未被响应时退出码非 0"
else
    bad "toggle 退出码" "3s 内未确认仍返回 0"
fi

# ---------------------------------------------------------------
sec "方案不被 App 静默改写"

# App 的「按方案收尾」路径（reconcileLidDaemon 关守护、降级回滚）会 spawn `nosleep off`。
# 那条命令默认把当前电源那套方案的 lid 归位成 sleep，于是 App 每 30 秒巡检一次，
# 用户在设置面板或 CLI 里选的「合盖不睡」就被无声擦掉，日志里查不到。
# 三条「收尾」路径都必须带 --no-touch-plan；「用户主动关」与「电量放手」除外。
n=$(grep -c '"nosleep", "off", "--no-touch-plan"' Sources/Bar/main.swift)
[ "$n" -ge 1 ] \
    && ok "降级回滚的 nosleep off 带 --no-touch-plan" \
    || bad "降级回滚" "nosleep off 未带 --no-touch-plan（会擦掉用户方案）"

m=$(grep -c 'setLidAwake(false, touchPlan: false)' Sources/Bar/main.swift)
if [ "$m" -ge 2 ]; then
    ok "按方案收尾的 setLidAwake(false) 传了 touchPlan: false（$m 处）"
else
    bad "setLidAwake 收尾" "只有 $m 处传了 touchPlan: false"
fi

# CLI 侧必须认这个参数，否则 App 传了也白传
grep -q 'clearLidAwake(touchPlan: Bool = true)' Sources/CLI/main.swift \
    && ok "CLI clearLidAwake 支持 touchPlan 参数" \
    || bad "clearLidAwake" "未支持 touchPlan"

grep -q 'args.contains("--no-touch-plan")' Sources/CLI/main.swift \
    && ok "CLI off 分支识别 --no-touch-plan" \
    || bad "CLI off 分支" "未识别 --no-touch-plan"

# 用户亲手敲的 nosleep off 必须仍然归位方案：这是 clearLidAwake 的原意，不能被修掉
grep -q 'clearLidAwake(touchPlan: !noTouchPlan)' Sources/CLI/main.swift \
    && ok "用户主动 nosleep off 仍会归位方案（原意保留）" \
    || bad "clearLidAwake 默认行为" "用户主动关闭不再归位方案"

# ---------------------------------------------------------------
sec "P2-2 / P2-7  不许报成功、不许静默失败"

# P2-7：三处关屏入口都不得再用 `try?` 写状态文件。状态文件是「黑屏中 + 该恢复到
# 多少亮度」的唯一记录；写失败还继续关屏，磁盘上就什么都不剩，下一次启动的自愈
# 路径读不到该恢复到哪。改成写失败即拒绝关屏。
#
# ⚠️ grep 给**多个**文件时输出 `文件:计数`，给单个文件时只有计数。必须一次传两个
# 文件，否则下面的 `awk -F:` 取不到字段，会静默算成 0 —— 一条永远失败的断言比没有
# 断言更坏（看着在跑，实际什么都不查）。这坑踩过一次。
n_try=$(grep -c 'try? String(.*)\.write(toFile: stateFile' \
        Sources/CLI/main.swift Sources/Bar/main.swift | awk -F: '{s+=$2} END{print s+0}')
[ "$n_try" -eq 0 ] \
    && ok "stateFile 已无 try? 写入（两处源码共 0 处）" \
    || bad "stateFile 仍有 try? 写入" "命中 $n_try 处"

n_guard=$(grep -c '无法写入状态文件' \
          Sources/CLI/main.swift Sources/Bar/main.swift | awk -F: '{s+=$2} END{print s+0}')
[ "$n_guard" -eq 3 ] \
    && ok "三处关屏入口都有写失败守卫（一次性 daemon / CLI 服务 / App）" \
    || bad "写失败守卫数量" "期望 3 处，实际 $n_guard 处"

# shutdown() 的自愈记录也不能静默失败：写不进去却照样通知「下次启动会自动恢复」，
# 那句话就成了假的 —— 而这正是本项目唯一一条确定会永久黑屏的路径。
grep -q '退出前亮度恢复失败，记录也没写进去' Sources/Bar/main.swift \
    && ok "自愈记录写失败有独立文案（不谎称下次会自动恢复）" \
    || bad "自愈记录写失败" "未找到对应失败分支文案"

# P2-2：复位 disablesleep 后必须回读校验，不能无条件报「已复位」。
n_verify=$(grep -c 'systemSleepDisabled()' \
           Sources/CLI/main.swift Sources/Bar/main.swift | awk -F: '{s+=$2} END{print s+0}')
[ "$n_verify" -ge 4 ] \
    && ok "disablesleep 复位后有回读校验（$n_verify 处调用 systemSleepDisabled）" \
    || bad "缺回读校验" "systemSleepDisabled 仅 $n_verify 处"

grep -q 'nosleep: disablesleep 复位失败' Sources/CLI/main.swift \
    && ok "复位失败有独立文案（不与成功共用一句）" \
    || bad "复位失败文案" "未找到失败分支文案"

# P2-4：参数校验必须排在动作之前。把校验放在「守护已在运行就短路退出」的分支之后，
# `lidkeep nosleep on --syste` 会在守护已经在跑时被静默接受并 exit 0 ——
# 同一句命令两种结果，取决于当时有没有守护在跑，用户敲之前无法预知。
# 这条断言是本轮实测逮到的：守护在跑时该用例失败，守护不在跑时通过。
#
# 两条行号都必须**限定在 `case "on":` 之后**取：全文 `if let pid = nosleepPid() {`
# 有三处，`doctor` 里那处（单行 if）行号更小，`head -1` 会取错那条而永远失败。
# 一条永远失败的断言比没有断言更坏 —— 看着在跑，实际什么都不查。这坑也踩了一次。
ln_parse=$(awk '/^    case "on":$/{f=1} f && /rejectMissingValue\(args, from: 3/{print NR; exit}' Sources/CLI/main.swift)
ln_short=$(awk '/^    case "on":$/{f=1} f && /if let pid = nosleepPid\(\) \{/{print NR; exit}' Sources/CLI/main.swift)
if [ -n "$ln_parse" ] && [ -n "$ln_short" ] && [ "$ln_parse" -lt "$ln_short" ]; then
    ok "nosleep on 先校验参数再动作（第 $ln_parse 行 早于 第 $ln_short 行）"
else
    bad "nosleep on 的校验排在短路之后" "parse=$ln_parse short=$ln_short"
fi

# 取值选项必须按子命令分开给，不能用一份全集：--battery 在 config 后面跟数字、
# 在 plan 后面什么都不跟。用全集判漏值会把 `plan --ac --battery` 判成「需要一个值」。
n_split=$(grep -c 'let valueOptions' Sources/CLI/main.swift)
[ "$n_split" -ge 4 ] \
    && ok "取值选项按子命令分表（$n_split 份）" \
    || bad "取值选项未分表" "只有 $n_split 份，全集会误判 plan --battery"

# 冒烟脚本自身的两条硬要求。都因为「跑起来才知道」而踩过：
#
# ① bash -n：macOS 自带 bash 3.2，脚本里若有一处没闭合的 if/fi，跑到一半才报
#    syntax error，前面的用例结果全部作废而且看不出来 —— 报告是绿的，账已经丢了。
bash -n dev-tools/smoke.sh 2>/dev/null \
    && ok "冒烟脚本语法正确（bash -n）" \
    || bad "冒烟脚本语法错误" "bash -n 未通过，后半段结果不可信"
bash -n dev-tools/regress.sh 2>/dev/null \
    && ok "本脚本语法正确（bash -n）" \
    || bad "回归脚本语法错误" "bash -n 未通过"

# ② 函数定义必须排在第一次调用之前。bash 在运行时才解析函数体，所以定义写在
#    调用下面一行不会报语法错，只在跑到那里时打一句 "command not found" ——
#    而脚本没有 set -e，那句错误混在输出里就被忽略了。后果是依赖它的断言
#    恒为假而被跳过，看着全绿。newlog() 曾经就是这样让「-is 断言是否一并放开」
#    那条断言从没过（它守的正是历史上真出过的 bug）。
ln_def=$(grep -n 'newlog() {' dev-tools/smoke.sh | head -1 | cut -d: -f1)
ln_use=$(grep -n 'newlog | grep' dev-tools/smoke.sh | head -1 | cut -d: -f1)
if [ -n "$ln_def" ] && [ -n "$ln_use" ] && [ "$ln_def" -lt "$ln_use" ]; then
    ok "newlog() 定义早于首次调用（第 ${ln_def} 行 早于 第 ${ln_use} 行）"
else
    bad "newlog() 定义排在调用之后" "def=${ln_def} use=${ln_use}，依赖它的断言会被静默跳过"
fi

# 反向断言：脚本里不得有「跳过被当成通过」的结构。同【17】那条纪律是同一件事 ——
# 一条永远不跑的断言比没有这条断言更坏，它让人以为该路径已经验过了。
n_orphan=$(grep -cE '^\s*had_[a-z_]+=0$' dev-tools/smoke.sh || true)
[ "$n_orphan" -le 1 ] \
    && ok "预置标记变量数量正常（$n_orphan 个）" \
    || bad "预置标记变量过多" "$n_orphan 个，可能存在定义了却永不赋值的断言开关"

# ---------------------------------------------------------------
sec "多语言表完整性"

for lg in EN JA KO DE FR ES; do
    n=$(grep -c '"' "Sources/Shared/L10n$lg.swift")
    if [ "$n" -gt 400 ]; then ok "L10n$lg 表条目 $n"; else bad "L10n$lg" "只有 $n 条"; fi
done

# ---------------------------------------------------------------
sec "通知闸门覆盖"

# 这组断言存在的原因：闸门（Notify.swift）最初只在 Bar 侧接上了，CLI 侧的 notify
# 压根没有 key 参数 —— 而 CLI 的守护与一次性命令同样会弹通知。缺陷能活下来，
# 是因为 regress.sh 当时没有任何一条断言提到闸门，「全绿」并不代表它被覆盖过。

# 1) CLI 侧的 notify 必须支持闸门：没有 key 参数就等于永远放行
if grep -qE 'func notify\(_ msg: String, key: String\?' Sources/CLI/main.swift; then
    ok "CLI 的 notify 支持闸门（key 参数存在）"
else
    bad "CLI 的 notify 没有 key 参数" "CLI 侧的通知将完全不受闸门约束"
fi

# 2) 两处持续状态必须走闸门。这两条是持续问题而非瞬时事件，不去重就会被反复提醒：
#    ① 缺提权助手导致防睡眠降级；② 亮度恢复失败转入持续重试。
n_hm=$(grep -c 'key: "helper-missing"' Sources/CLI/main.swift || true)
n_rf=$(grep -c 'key: "restore-failed"' Sources/CLI/main.swift || true)
[ "$n_hm" -ge 1 ] \
    && ok "缺助手的降级提示已走闸门（$n_hm 处）" \
    || bad "缺助手的降级提示未走闸门" "用户反复手动 nosleep on 时会每敲一次弹一条"

[ "$n_rf" -ge 2 ] \
    && ok "亮度恢复失败已走闸门（$n_rf 处：daemon 与 service 两条路径）" \
    || bad "亮度恢复失败的闸门覆盖不全" "只有 $n_rf 处，另一条路径仍会反复弹"

# 3) 反向断言：闸门必须真的被调用过，而不是只有定义。
#    「定义了闸门但一处没接」与「没有闸门」在用户侧是同一种故障。
n_open=$(grep -rc 'notifyGateOpen' Sources/CLI/main.swift Sources/Bar/main.swift | awk -F: '{s+=$2} END {print s+0}')
[ "$n_open" -ge 2 ] \
    && ok "闸门在运行时路径上被调用（$n_open 处）" \
    || bad "闸门几乎没被调用" "$n_open 处，可能只定义了没用上"

# ---------------------------------------------------------------
printf '\n================================\n'
printf '通过 %d / 失败 %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1