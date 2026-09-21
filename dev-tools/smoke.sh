#!/bin/bash
# lidkeep 端到端冒烟测试
#
# 目的：把「改了代码还能不能用」从人工验证变成一条命令。
# 覆盖：版本/诊断输出、参数校验、配置往返、电量保护、关屏与恢复、孤儿进程、
#       防睡眠启停、合盖熄屏与恢复（模拟）、提权助手资产一致性、守护掉电自停、
#       守护唯一性、「息屏后保持唤醒」是否真的持有断言、它的电量下限释放、
#       进程归属判定（不得被命令行里的路径字样骗到）。
#
# 慢用例的门控（两者需要相反的运行条件，各跑一次才全覆盖）：
#   SMOKE_FULL=1 + App 未常驻  → 跑【11】合盖守护掉电自停
#   SMOKE_FULL=1 + App 常驻    → 跑【13】常亮的电量下限释放、【14】息屏保持唤醒的电量下限释放
# 无论哪次运行，脚本都会在结尾把 config.json 还原成跑之前那份。
#
# 用法:
#   ./dev-tools/smoke.sh [CLI 路径]        # 默认 build/lidkeep
#   SMOKE_FULL=1 ./dev-tools/smoke.sh      # 强制跑真实关屏测试
#
# 设计取舍：
#   * 检测到菜单栏 App 正在常驻时，跳过真实关屏测试——那会打断用户当前会话，
#     而且测的是已安装的旧二进制，不是刚构建出来的这份。
#   * 检测不到可用亮度接口（如 CI 的虚拟显示）时同样跳过，而不是记失败。

set -uo pipefail

# 断言基于中文案文，而 CLI 会跟随系统语言（CI 是英文系统）→ 这里锁定为中文。
# 需要测英文时: SMOKE_LANG=en ./dev-tools/smoke.sh
export LIDKEEP_LANG="${SMOKE_LANG:-zh}"

B="${1:-build/lidkeep}"
CFG="$HOME/Library/Application Support/LidKeep/config.json"
SUP_DIR="$(dirname "$CFG")"      # 配置与状态文件同目录（_sim-battery / nosleep.pid 等）
pass=0; fail=0; skip=0
# 【15】用的诱饵进程（命令行里带路径字样、可执行文件却不是本程序）。声明在 cleanup 之前，
# 半途中断时也能被收走，不会留一个 60 秒的 sleep 挂在系统里。
DECOY_PIDS=""

# 这份 config.json 是用户真实在用的。测试会改方案、改电量下限（`nosleep off` 还会
# 清掉当前电源那套的合盖项），跑完必须原样放回去 —— 否则「跑一次 make test，
# 自己的设置就没了」，真实踩过，用户只会觉得莫名其妙。
cp "$CFG" /tmp/bs_cfg_user_backup.json 2>/dev/null || true

# 清场 + 兜底还原。
# 电量模拟钩子是**上一轮被中断的测试**最可能的残留：留着它，常驻 App 会以为电量只剩
# 10%，电量触底动作立刻触发并把用户的方案改掉。实测踩过：一次冒烟莫名报「方案被回写
# 覆盖」，根因就是外部对抗脚本留下的 _sim-battery，与本次改动毫无关系。
# 用 trap 而不是只写在末尾：半途 Ctrl-C / 断言 exit 时也必须还原用户配置。
cleanup() {
    if [ -n "${DECOY_PIDS:-}" ]; then
        for p in $DECOY_PIDS; do kill "$p" 2>/dev/null; done
    fi
    rm -f "$(dirname "$CFG")/_sim-battery"
    if [ -f /tmp/bs_cfg_user_backup.json ]; then
        cp /tmp/bs_cfg_user_backup.json "$CFG" 2>/dev/null
    fi
}
trap cleanup EXIT
rm -f "$(dirname "$CFG")/_sim-battery"

ok()   { echo "  ✅ $1"; pass=$((pass + 1)); }
bad()  { echo "  ❌ $1"; fail=$((fail + 1)); }
skip_() { echo "  ⏭  $1（$2）"; skip=$((skip + 1)); }

# ps 在某些托管环境里连 exec 都被拒（实测：`/bin/ps: Operation not permitted`，而 pgrep 正常）。
# 依赖它的断言若照跑，只会得到「进程数为 0」的假失败 —— 天天报红的守卫等于没有守卫。
# 因此先探测，探不到就如实跳过；CI 上 ps 可用，断言照常生效。
if ps -o pid= -p $$ >/dev/null 2>&1; then HAVE_PS=1; else HAVE_PS=0; fi

if [ ! -x "$B" ]; then
    echo "找不到可执行文件或不可执行: $B（先执行 make）" >&2
    exit 2
fi

echo "lidkeep 冒烟测试 —— $($B version 2>/dev/null | head -1)"
echo

# ---------- 1. 版本与诊断 ----------
echo "【1】版本与诊断"
[ -n "$($B version 2>/dev/null)" ] && ok "version 有输出" || bad "version 无输出"
$B doctor >/tmp/bs_doctor.out 2>&1
grep -q "关屏能力" /tmp/bs_doctor.out && ok "doctor 输出完整报告" || bad "doctor 输出异常"

# 依据 doctor 判断环境能力，后面的用例据此决定跑还是跳
no_display=0
grep -q "亮度接口不可用" /tmp/bs_doctor.out && no_display=1
has_service=0
grep -q "常驻服务运行中" /tmp/bs_doctor.out && has_service=1

# ---------- 2. 参数校验 ----------
echo
echo "【2】参数校验（非法输入必须被拒绝，而不是被静默接受）"
reject() {   # $1=描述  $2..=命令
    local d="$1"; shift
    "$@" >/dev/null 2>&1
    [ $? -ne 0 ] && ok "拒绝 $d" || bad "接受了非法输入：$d"
}
reject "越界亮度 5"            "$B" bright 5
reject "非数值亮度 abc"         "$B" bright abc
reject "越界电量 200"          "$B" config --battery 200
reject "越界键码 999"          "$B" config --key 999
reject "负数超时 -1"           "$B" config --timeout -1
reject "非法恢复策略 abc"       "$B" config --restore abc
reject "无修饰键热键"          "$B" config --mods "" --key 0

# ---------- 3. 配置往返 ----------
echo
echo "【3】配置读写往返"
$B config >/dev/null 2>&1
# 压缩掉空白再取字段：App 保存的是 pretty-printed JSON（"batteryFloor" : 20），
# CLI 保存的是紧凑格式，两种都要能解析
json_batt() { [ -f "$CFG" ] || return 0; tr -d ' \n\t' < "$CFG" 2>/dev/null | grep -o '"batteryFloor":[0-9]*' | grep -o '[0-9]*$'; }
orig=$(json_batt); orig=${orig:-20}
$B config --battery 35 >/dev/null 2>&1
now=$(json_batt)
[ "${now:-}" = "35" ] && ok "写入配置已落盘（电量下限 35）" || bad "配置未生效（读到 ${now:-空}）"
$B config --battery "$orig" >/dev/null 2>&1
back=$(json_batt)
[ "${back:-}" = "$orig" ] && ok "配置已复原（${orig}）" || bad "配置未能复原（读到 ${back:-空}）"

# 菜单栏 App 与 CLI 共写同一个 config.json：任一端漏了某个字段的 CodingKeys，
# 另一端写盘时就会把它静默抹掉。这个坑踩过两回（lidBlackout、自动更新字段），
# 所以每次新增配置字段都必须在这里加一条往返断言。
json_raw() { [ -f "$CFG" ] || return 0; tr -d ' \n\t' < "$CFG" 2>/dev/null | grep -o "\"$1\":[^,}]*" | head -1 | sed "s/\"$1\"://"; }
orig_act=$(json_raw batteryAction); orig_act=${orig_act:-0}
orig_hk=$(json_raw hotkeyEnabled);  orig_hk=${orig_hk:-true}
$B config --battery-action 1 --hotkey off >/dev/null 2>&1
[ "$(json_raw batteryAction)" = "1" ] && ok "电量触底动作已写入" || bad "电量触底动作未写入（读到 $(json_raw batteryAction)）"
[ "$(json_raw hotkeyEnabled)" = "false" ] && ok "全局热键开关已写入" || bad "全局热键开关未写入（读到 $(json_raw hotkeyEnabled)）"
# 换个字段再写一次盘：上面两个值必须还在
$B config --battery 45 >/dev/null 2>&1
[ "$(json_raw batteryAction)" = "1" ] && ok "CLI 再次写盘后 batteryAction 仍在" || bad "CLI 写盘抹掉了 batteryAction"
[ "$(json_raw hotkeyEnabled)" = "false" ] && ok "CLI 再次写盘后 hotkeyEnabled 仍在" || bad "CLI 写盘抹掉了 hotkeyEnabled"
$B config --battery "$orig" --battery-action "$orig_act" --hotkey "$orig_hk" >/dev/null 2>&1

# 电源方案是嵌套对象（planAC / planBattery），必须整体往返：
# 两套方案被抹掉任意一个，就等于退回单一的全局设置。
plan_field() { [ -f "$CFG" ] || return 0; tr -d ' \n\t' < "$CFG" 2>/dev/null | grep -o "\"$1\":{[^}]*}" | head -1 | sed "s/\"$1\"://"; }
lid_of()  { plan_field "$1" | grep -o '"lid":"[a-z]*"'        | sed 's/.*://;s/"//g'; }
# 注意用 grep -E：BSD grep 的 BRE 不支持 \| 交替（实测取到空值，会把 keepAwake 误判为 false）
ka_of()   { plan_field "$1" | grep -oE '"keepAwake":(true|false)' | sed 's/.*://'; }
ac_lid=$(lid_of planAC)
ac_ka=$(ka_of planAC)
bat_lid=$(lid_of planBattery)
bat_ka=$(ka_of planBattery)
if [ -z "$ac_lid" ];  then ac_lid=sleep; fi
if [ -z "$ac_ka" ];   then ac_ka=false; fi
if [ -z "$bat_lid" ]; then bat_lid=sleep; fi
if [ -z "$bat_ka" ];  then bat_ka=false; fi
[ -n "$(plan_field planAC)" ] && ok "接通电源方案已落盘（$(plan_field planAC)）" || bad "planAC 缺失（CLI 或 App 未镜像该字段）"
[ -n "$(plan_field planBattery)" ] && ok "使用电池方案已落盘（$(plan_field planBattery)）" || bad "planBattery 缺失（CLI 或 App 未镜像该字段）"
$B plan --ac --lid nothing >/dev/null 2>&1
case "$(plan_field planAC)" in *'"lid":"nothing"'*) ok "接通电源方案可写入" ;; *) bad "接通电源方案未写入（读到 $(plan_field planAC)）" ;; esac
[ "$(lid_of planBattery)" = "$bat_lid" ] && ok "改接通电源方案不影响使用电池方案" || bad "使用电池方案被覆盖（读到 $(plan_field planBattery)）"
$B plan --battery --keep-awake off >/dev/null 2>&1
case "$(plan_field planBattery)" in *'"keepAwake":false'*) ok "使用电池方案可写入" ;; *) bad "使用电池方案未写入（读到 $(plan_field planBattery)）" ;; esac
# 换个字段再写一次盘：两套方案都必须还在
$B config --battery 45 >/dev/null 2>&1
case "$(plan_field planAC)" in *'"lid":"nothing"'*) ok "CLI 再次写盘后 planAC 仍在" ;; *) bad "CLI 写盘抹掉了 planAC" ;; esac
case "$(plan_field planBattery)" in *'"keepAwake":false'*) ok "CLI 再次写盘后 planBattery 仍在" ;; *) bad "CLI 写盘抹掉了 planBattery" ;; esac
# 配置自愈：盘上出现非法取值 / 类型错误时，读取一次就该把修好的值**落盘**。
# 只靠解码层兜底的话，内存里是好的、盘上一直是脏的：每次启动都重新兜一次，
# 用户从外部看到的是一个永远修不好的配置文件。
if command -v python3 >/dev/null 2>&1; then
    python3 - "$CFG" <<'PYEOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c.setdefault("planAC", {})["lid"] = "bogus"      # 非法枚举值
json.dump(c, open(p, "w"), indent=2)
PYEOF
    $B plan >/dev/null 2>&1
    [ "$(lid_of planAC)" = "sleep" ] && ok "非法 lid 取值已被落盘修复" || bad "非法 lid 取值未被修复（读到 $(lid_of planAC)）"

    # 单个方案字段类型错误不能带崩整份配置：早期实现里 decodeIfPresent 会直接抛出，
    # 整个 decode 失败 → loadConfig 退回全新 Config → 热键、语言、电量下限全部被重置
    python3 - "$CFG" <<'PYEOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["planAC"] = "oops"
json.dump(c, open(p, "w"), indent=2)
PYEOF
    $B config --battery 46 >/dev/null 2>&1        # 写一次盘，触发 loadConfig + saveConfig
    [ "$(json_raw batteryAction)" = "$orig_act" ] \
      && ok "方案字段类型错误后其它设置仍在（未被重置）" || bad "方案字段类型错误抹掉了其它设置"
    $B config --battery "$orig" >/dev/null 2>&1
else
    skip_ "配置自愈" "未找到 python3"
fi

$B config --battery "$orig" >/dev/null 2>&1
$B plan --ac --lid "$ac_lid" --keep-awake "$ac_ka" >/dev/null 2>&1
$B plan --battery --lid "$bat_lid" --keep-awake "$bat_ka" >/dev/null 2>&1
# 写完要盯 4 秒再判：常驻 App 的「读-改-写」窗口约 1 秒（中途要 spawn 守护进程），
# 若它拿旧快照整份回写，刚写进去的方案会在 1 秒后被翻回去——只查一次的断言会漏掉它
# （实测就是这样漏掉过一次，用户看到的是「改完自己变回去」）。
stuck=1
for _ in 1 2 3 4 5 6 7 8; do
    sleep 0.5
    if [ "$(lid_of planAC)" != "$ac_lid" ] || [ "$(lid_of planBattery)" != "$bat_lid" ]; then
        stuck=0; break
    fi
done
[ "$stuck" = "1" ] && ok "电源方案已复原且 4 秒内未被回写覆盖（AC=${ac_lid} / 电池=${bat_lid}）" \
                   || bad "电源方案被回写覆盖（AC=$(lid_of planAC) 电池=$(lid_of planBattery)，期望 AC=${ac_lid} 电池=${bat_lid}）"

# ---------- 4. 电量保护 ----------
echo
echo "【4】电量保护（模拟电池 10% 放电中）"
if [ "$has_service" -eq 1 ]; then
    skip_ "低电量拒绝关屏" "常驻服务由另一进程持有，环境变量无法注入"
elif [ "$no_display" -eq 1 ]; then
    skip_ "低电量拒绝关屏" "无可用亮度接口"
else
    LK_SIMULATE_BATTERY="10,batt,discharging" "$B" off >/dev/null 2>&1
    [ $? -ne 0 ] && ok "低电量时拒绝关屏并报错" || bad "低电量未拒绝关屏"
fi
# 防睡眠同样要拦：低于下限还去开防睡眠，就是把「包里放电到关机」这条路铺平。
# 必须先清掉已有守护——`nosleep on` 见守护在跑会直接 exit 0，那样测到的是「已在运行」
# 而不是「被下限拦住」，断言会随上一个用例的残留状态飘（实测飘过一次）。
"$B" nosleep off >/dev/null 2>&1
sleep 1
LK_SIMULATE_BATTERY="10,batt,discharging" "$B" nosleep on >/dev/null 2>&1
[ $? -ne 0 ] && ok "低电量时拒绝开启防睡眠" || bad "低电量未拒绝防睡眠"

# ---------- 5. 关屏与恢复 ----------
echo
echo "【5】关屏与恢复（会短暂黑屏）"
if [ "$no_display" -eq 1 ]; then
    skip_ "关屏 / 恢复" "无可用亮度接口"
elif [ "$has_service" -eq 1 ]; then
    skip_ "关屏 / 恢复" "菜单栏 App 常驻中，避免打断当前会话"
elif [ "${SMOKE_FULL:-0}" != "1" ]; then
    skip_ "关屏 / 恢复" "默认跳过，设 SMOKE_FULL=1 启用"
else
    before=$("$B" bright 2>/dev/null | awk '{print $NF}')
    "$B" off >/dev/null 2>&1
    sleep 1.2
    mid=$("$B" bright 2>/dev/null | awk '{print $NF}')
    [ "$mid" = "0.0" ] && ok "关屏后亮度为 0" || bad "关屏后亮度=$mid"
    "$B" on >/dev/null 2>&1
    sleep 1.2
    after=$("$B" bright 2>/dev/null | awk '{print $NF}')
    same=$(awk -v a="$before" -v b="$after" 'BEGIN{d=a-b; if(d<0)d=-d; print (d<0.02)?"1":"0"}')
    [ "$same" = "1" ] && ok "恢复后亮度回到原值（${before} → ${after}）" \
                       || bad "恢复后亮度偏差过大（${before} → ${after}）"
fi

# ---------- 6. 断言归属：本程序自己的断言必须被认成自己的 ----------
echo
echo "【6】断言归属（受限环境也不许依赖 ps）"
# 这里原本是「✅ 无孤儿 caffeinate」，一条**永远不可能命中**的假绿灯：判据是
# 「caffeinate 的父进程还在不在」，而父进程一消失它立刻被 launchd 收养，ppid 恒指向
# 存活的 1；叠加 ps 被策略拒绝（读不到就静默当成「没有孤儿」），这条检查从来没查过东西。
# 换成一条真正会失败的判据：**「息屏后保持唤醒」打开后，doctor 必须能认出断言是本程序的**。
# 它同时守住两件事：开关不是空转（真的持有断言）、归属判定不能依赖外部命令
# （曾经走 `ps -o ppid=`，被拒后把自家断言全报成「其他持有者」，还会附一句
# 「配置要求防睡眠，但当前没有任何断言在生效中」的自相矛盾提示）。
# 判据来自 `lidkeep doctor`（进程内 sysctl/proc 实现），因此在本机也一样有效。
if [ "$has_service" -eq 0 ]; then
    skip_ "断言归属" "该断言由菜单栏 App 持有，需 App 常驻"
else
    # 文件钩子固定「接电源且健康」，否则电量低于下限时断言会被正确地拒绝
    printf '80,ac,charging' > "$SUP_DIR/_sim-battery"
    "$B" plan --ac --keep-awake on >/dev/null 2>&1
    sleep 4
    got=""
    for _ in $(seq 1 6); do
        got=$("$B" doctor 2>/dev/null | grep "本程序持有" || true)
        [ -n "$got" ] && break
        sleep 2
    done
    if [ -z "$got" ]; then
        bad "开启后 doctor 认不出任何自有断言（开关空转，或归属判定依赖了被拒的外部命令）"
    elif echo "$got" | grep -q "DisplaySleep"; then
        bad "自有断言里出现了 Display 类型：屏幕永远不会自动熄灭，与「息屏后保持唤醒」自相矛盾"
    else
        ok "开启后能认出持有的断言，且不含 Display 类型（系统不睡、屏幕仍可自动熄灭）"
    fi
    "$B" plan --ac --keep-awake off >/dev/null 2>&1
    sleep 4
    "$B" doctor 2>/dev/null | grep -q "本程序持有" \
        && bad "关闭后 doctor 仍认为本程序持有断言" || ok "关闭后断言随之解除"
    rm -f "$SUP_DIR/_sim-battery"
fi

# ---------- 7. 防睡眠启停 ----------
echo
echo "【7】防睡眠启停与超时自停"
"$B" nosleep off >/dev/null 2>&1
"$B" nosleep on --timeout 2 >/dev/null 2>&1
sleep 0.6
if "$B" nosleep status 2>/dev/null | grep -q "已开启"; then
    ok "防睡眠已开启"
else
    bad "防睡眠未能开启"
fi
sleep 2.6
if "$B" nosleep status 2>/dev/null | grep -q "未开启"; then
    ok "超时后自动停止"
else
    bad "超时后未自动停止"
fi

# ---------- 8. 合盖熄屏与恢复（模拟合盖，不依赖物理开合盖子） ----------
echo
echo "【8】合盖熄屏与恢复（LK_SIMULATE_LID_CLOSED 模拟）"
log_file="$HOME/Library/Application Support/LidKeep/LidKeep.log"
log_tail() {  # 打印自调用前累积行数之后的新日志
    local n0="$1"
    tail -n "+$((n0 + 1))" "$log_file" 2>/dev/null
}
# doctor 只能判断 DisplayServices 是否加载；CI 虚拟机加载了却读不到真实亮度。
# 这里直接探测：`bright` 必须返回可解析的数值才认为亮度接口真正可用。
bright_ok=0
probe=$("$B" bright 2>/dev/null | awk '{print $NF}')
case "$probe" in ''|*[!0-9.]*) bright_ok=0 ;; *) bright_ok=1 ;; esac
if [ "$bright_ok" -eq 0 ]; then
    skip_ "合盖熄屏" "无可用亮度接口（CI 虚拟显示）"
elif [ "$has_service" -eq 1 ]; then
    skip_ "合盖熄屏" "菜单栏 App 常驻中，避免熄灭用户屏幕"
else
    "$B" nosleep off >/dev/null 2>&1
    n0=$(wc -l < "$log_file" 2>/dev/null || echo 0)
    # --timeout 8 兜底：即使断言失败守护也会自停，不留黑屏
    LK_SIMULATE_LID_CLOSED=1 "$B" nosleep on --timeout 8 >/dev/null 2>&1
    sleep 3
    if log_tail "$n0" | grep -q "内屏已熄灭"; then
        ok "合盖后内屏自动熄灭"
    else
        bad "合盖后未见熄屏记录（日志: $(log_tail "$n0" | grep '^lid' | tail -1)）"
    fi
    mid=$("$B" bright 2>/dev/null | awk '{print $NF}')
    [ "$mid" = "0.0" ] && ok "合盖期间内屏亮度为 0" || bad "合盖期间亮度=${mid}"
    # 守护退出（此处为超时自停）必须恢复亮度——不留黑屏残局
    sleep 7
    if log_tail "$n0" | grep -q "恢复内屏亮度"; then
        ok "守护停止时恢复内屏亮度"
    else
        bad "守护停止时未见恢复记录"
    fi
    after=$("$B" bright 2>/dev/null | awk '{print $NF}')
    # 注意：$after 后必须用 ${after} 界定——后跟全角括号会被 bash 3.2 当成变量名的一部分
    [ "$(awk -v a="$after" 'BEGIN{print (a>0.05)?"1":"0"}')" = "1" ] \
        && ok "停止后内屏亮度已恢复（${after}）" || bad "停止后内屏仍黑着（${after}）"
fi

# ---------- 9. 提权助手资产一致性 ----------
echo
echo "【9】提权助手资产一致性（内嵌资产必须与仓库副本逐字相同）"
tmp_assets=$(mktemp -d)
"$B" nosleep write-assets "$tmp_assets" >/dev/null 2>&1
if diff -q "$tmp_assets/com.lidkeep.pmset" packaging/helper/com.lidkeep.pmset >/dev/null 2>&1; then
    ok "helper 脚本与仓库副本一致"
else
    bad "helper 脚本与仓库副本不一致（执行 make 后重新 write-assets 同步）"
fi
if diff -q "$tmp_assets/com.lidkeep.nosleep.reset.plist" \
            packaging/helper/com.lidkeep.nosleep.reset.plist >/dev/null 2>&1; then
    ok "开机复位 LaunchDaemon 与仓库副本一致"
else
    bad "LaunchDaemon 与仓库副本不一致"
fi
# 提权脚本必须能被 shell 解析：它会被 root 执行，语法错误意味着安装即损坏
if sh -n packaging/helper/com.lidkeep.pmset 2>/dev/null; then
    ok "helper 脚本语法正确"
else
    bad "helper 脚本存在语法错误"
fi
rm -rf "$tmp_assets"

# ---------- 10. 本地化 ----------
echo
echo "【10】本地化（界面语言跟随系统，可用 LIDKEEP_LANG 覆盖）"
# 汉字检测必须用 Perl 的 \p{Han}：grep 的字符区间 [一-鿿] 在 CI 的 C locale 下
# 会把 emoji 和 ⌃⌥⌘ 之类的符号也算成中文（实测误判 ✅ / ⚠️ / —）。
has_han() { perl -CSD -ne 'BEGIN { $f = 0 } $f++ if /\p{Han}/; END { exit($f ? 0 : 1) }'; }
lines_han() { perl -CSD -ne 'print "$.: $_" if /\p{Han}/'; }

en_out=$(LIDKEEP_LANG=en "$B" doctor 2>/dev/null)
if printf '%s\n' "$en_out" | has_han; then
    bad "英文模式下仍有中文残留"
    printf '%s\n' "$en_out" | lines_han | head -5 | sed 's/^/      残留: /'
else
    ok "英文模式输出无中文残留"
fi
zh_out=$(LIDKEEP_LANG=zh "$B" doctor 2>/dev/null)
if printf '%s\n' "$zh_out" | has_han; then
    ok "中文模式输出为中文"
else
    bad "中文模式未输出中文"
fi
if LIDKEEP_LANG=en "$B" --help 2>/dev/null | grep -q 'CLI usage'; then
    ok "帮助文本已本地化"
else
    bad "帮助文本未本地化"
fi
# 跟随系统语言：用 -AppleLanguages 参数域模拟系统语言。必须清掉 LIDKEEP_LANG
# 才会走到系统判定这一步（smoke.sh 顶部把它锁成了中文）。
# 回归点：系统语言既非中文也非英文（如日语）时应回落英文界面——曾经因为退回
# Locale.current（本机区域 zh）而误判成中文。
sys_ja=$(env -u LIDKEEP_LANG "$B" -AppleLanguages '(ja)' 2>/dev/null)
if printf '%s\n' "$sys_ja" | has_han; then
    bad "非中英系统语言未回落英文界面（误判为中文）"
    printf '%s\n' "$sys_ja" | lines_han | head -3 | sed 's/^/      残留: /'
else
    ok "非中英系统语言（ja）回落英文界面"
fi
sys_en=$(env -u LIDKEEP_LANG "$B" -AppleLanguages '(en)' 2>/dev/null)
if printf '%s\n' "$sys_en" | has_han; then
    bad "模拟英文系统时仍有中文"
else
    ok "跟随系统语言（en）生效"
fi
sys_zh=$(env -u LIDKEEP_LANG "$B" -AppleLanguages '(zh-Hans)' 2>/dev/null)
if printf '%s\n' "$sys_zh" | has_han; then
    ok "跟随系统语言（zh-Hans）生效"
else
    bad "模拟中文系统时未输出中文"
fi

# ---------- 11. 合盖守护的电量下限自停（端到端，较慢） ----------
echo
echo "【11】合盖守护电量下限自停（需 SMOKE_FULL=1，约 50 秒）"
# 合盖守护是独立进程，App 重启带不走它，它的电量下限只有它自己盯着（见 CLI nosleep 主循环）。
# 这条路径一旦失守，用户把合盖运行的机器塞进包里就会一路放电到关机——最贵的那种故障。
# 用**文件**钩子而非环境变量：守护由 App 拉起，拿不到 App 的环境变量。
daemon_alive() { [ -f "$SUP_DIR/nosleep.pid" ] && kill -0 "$(cat "$SUP_DIR/nosleep.pid" 2>/dev/null)" 2>/dev/null; }
if [ "${SMOKE_FULL:-0}" != "1" ]; then
    skip_ "守护掉电自停" "默认跳过，设 SMOKE_FULL=1 启用"
elif [ "$has_service" -eq 1 ]; then
    skip_ "守护掉电自停" "菜单栏 App 常驻中，巡检会和测试抢同一个守护"
else
    cp "$CFG" /tmp/bs_cfg_backup.json 2>/dev/null || true
    printf '80,batt,discharging' > "$SUP_DIR/_sim-battery"
    "$B" config --battery 20 >/dev/null 2>&1
    "$B" nosleep on --system >/dev/null 2>&1
    sleep 2
    if daemon_alive; then
        ok "模拟 80% 时守护正常启动"
        printf '10,batt,discharging' > "$SUP_DIR/_sim-battery"
        stopped=0
        for _ in $(seq 1 25); do
            sleep 2
            if ! daemon_alive; then stopped=1; break; fi
        done
        [ "$stopped" = "1" ] && ok "电量掉到下限后守护自行停止" \
                             || bad "电量低于下限已 50 秒，守护仍在运行（包内放电风险）"
    else
        skip_ "守护掉电自停" "守护未能启动（本机可能未安装提权助手）"
    fi
    rm -f "$SUP_DIR/_sim-battery"
    # 配置必须还原：这份 config.json 是用户真实在用的
    [ -f /tmp/bs_cfg_backup.json ] && cp /tmp/bs_cfg_backup.json "$CFG" 2>/dev/null || true
fi

# ---------- 12. 守护唯一性（pid 文件只有一个，进程却可以有很多） ----------
echo
echo "【12】防睡眠守护唯一性"
# 曾经的实现允许并存：后启动的守护覆盖 nosleep.pid，先启动的从此无人认领，
# `nosleep off` 再也找不到它 —— 它一直持有 caffeinate，机器再也睡不着，
# 而界面上显示的是「防睡眠已关闭」。本机实测残留过 5 个，必须由机器守住。
daemon_pids() {
    pgrep -f "nosleep-daemon" 2>/dev/null | while read -r p; do
        # 有 ps 就再核一次可执行文件归属；没有就只能靠 pgrep 的角色匹配（CI 上走前者）
        [ "$HAVE_PS" = "1" ] || { echo "$p"; continue; }
        ps -o command= -p "$p" 2>/dev/null | grep -q "lidkeep" && echo "$p"
    done
}
"$B" nosleep off >/dev/null 2>&1
"$B" nosleep on --system >/dev/null 2>&1; sleep 2
# 精确复现历史故障的前置条件：守护活着，但 pid 文件丢了
# （后启动的守护覆盖它、或手滑删掉，都会造成这个状态）
rm -f "$SUP_DIR/nosleep.pid"
"$B" nosleep on --system >/dev/null 2>&1; sleep 3
n=$(daemon_pids | wc -l | tr -d ' ')
[ "$n" = "1" ] && ok "pid 文件丢失后再启动，仍只保留 1 个守护" \
               || bad "pid 文件丢失后出现了 $n 个守护（pid 文件之外的会永久泄漏防睡眠）"
# 再做一个孤儿（pid 文件又删掉），验证 off 能把它一起收走
rm -f "$SUP_DIR/nosleep.pid"
"$B" nosleep on --system >/dev/null 2>&1; sleep 3
"$B" nosleep off >/dev/null 2>&1; sleep 1
n=$(daemon_pids | wc -l | tr -d ' ')
[ "$n" = "0" ] && ok "nosleep off 把 pid 文件之外的守护也收干净" \
               || bad "off 之后仍残留 $n 个守护（系统会一直不睡）"

# ---------- 13. 电量守卫必须认得「保持屏幕常亮」的断言（端到端，较慢） ----------
echo
echo "【13】保持屏幕常亮的电量下限释放（需 SMOKE_FULL=1 且 App 常驻，约 60 秒）"
# 与【14】互补：【14】测「息屏后保持唤醒」（caffeinate -is），这条测「保持屏幕常亮」（caffeinate -d）。
# displayCaff 曾是守卫准入条件里唯一漏掉的一条 —— 它独立于黑屏长期持有，且是唯一
# 「屏幕整夜亮着」的形态；漏掉的后果是插着电池一路放电到自动关机，而保护全程不介入。
# 本程序同时可能持有三条参数各异的 caffeinate 断言（-d / -is / -dis），
# 据此把它们区分开，不靠猜测。
#
# ⚠️ 前提：常驻的 App 必须是**本次构建装上去的那份**。本用例验证的是新加的电量拦截，
# 若 /Applications 里仍是旧版，App 根本不会释放 displayCaff，这里会报失败 ——
# 那是**假失败**，不是代码回归。跑前先 `make install`，再让 App 重启（launchd 会自动拉起）。
# 【14】没有这个前提：它测的 keepCaff 拦截在更早的版本里就已存在。
display_caff_cmd() {
    for p in $(pgrep -x caffeinate 2>/dev/null); do
        pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        case "$(ps -o command= -p "$pp" 2>/dev/null)" in
            *LidKeep*) ps -o command= -p "$p" 2>/dev/null | grep 'caffeinate -d -w' ;;
        esac
    done
}
if [ "${SMOKE_FULL:-0}" != "1" ]; then
    skip_ "常亮的电量释放" "默认跳过，设 SMOKE_FULL=1 启用"
elif [ "$has_service" -eq 0 ]; then
    skip_ "常亮的电量释放" "该断言由菜单栏 App 持有，需 App 常驻"
elif [ "$HAVE_PS" = "0" ]; then
    skip_ "常亮的电量释放" "本环境 ps 不可用，分不开 -d / -is / -dis 三条断言"
else
    printf '80,ac,charging' > "$SUP_DIR/_sim-battery"
    "$B" config --battery 20 >/dev/null 2>&1
    "$B" config --battery-action 0 >/dev/null 2>&1      # 触底：只恢复屏幕（也必须放开常亮）
    # 两套方案都开：切到电池方案后断言仍该在，于是「断言消失」只可能来自电量守卫，
    # 不会与电源方案切换混为一谈（那是另一条路径，【14】已覆盖）。
    "$B" plan --display-on on >/dev/null 2>&1
    sleep 5
    if [ -z "$(display_caff_cmd)" ]; then
        skip_ "常亮的电量释放" "断言未装上（无可用亮度接口，或已被电量下限拦下）"
    else
        printf '10,batt,discharging' > "$SUP_DIR/_sim-battery"
        released=0
        for _ in $(seq 1 30); do
            sleep 2
            if [ -z "$(display_caff_cmd)" ]; then released=1; break; fi
        done
        if [ "$released" = "1" ]; then
            ok "电量触底后常亮断言被撤销（不会亮着屏幕放电到关机）"
        else
            bad "电量低于下限已 60 秒，常亮断言仍在持有（若常驻的是旧版 App，请先 make install 再跑）"
        fi
    fi
    rm -f "$SUP_DIR/_sim-battery"
    "$B" plan --display-on off >/dev/null 2>&1
fi

# ---------- 14. 电量守卫必须认得「息屏后保持唤醒」的断言（端到端，较慢） ----------
echo
echo "【14】息屏保持唤醒的电量下限释放（需 SMOKE_FULL=1 且 App 常驻，约 40 秒）"
# 与【11】互补：【11】测的是「守护自己盯着」，这条测的是「App 的守卫记得还有它」。
# keepCaff 是**长期**持有的断言（不像黑屏那条只活几秒），守卫若漏掉它，
# 掀盖息屏后机器会一路放电到关机，而菜单栏上看起来一切正常。
#
# 这里为什么仍要 ps：doctor 只报断言持有者（caffeinate）的 pid，不报它是谁拉起来的，
# 而合盖守护**也**持有 caffeinate —— 不区分就会在 App 已经释放之后仍看到守护那条，
# 把正常状态判成失败。假警报比没有警报更糟，所以无 ps 时如实跳过，不猜。
# （【6】已经在无需 ps 的前提下守住了「开关不是空转 + 归属判定不许依赖被拒的命令」。）
keep_caff_pids() {
    for p in $(pgrep -x caffeinate 2>/dev/null); do
        pp=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        case "$(ps -o command= -p "$pp" 2>/dev/null)" in
            *LidKeep*) ps -o command= -p "$p" 2>/dev/null;;
        esac
    done
}
if [ "${SMOKE_FULL:-0}" != "1" ]; then
    skip_ "息屏保持唤醒的电量释放" "默认跳过，设 SMOKE_FULL=1 启用"
elif [ "$has_service" -eq 0 ]; then
    skip_ "息屏保持唤醒的电量释放" "该断言由菜单栏 App 持有，需 App 常驻"
elif [ "$HAVE_PS" = "0" ]; then
    skip_ "息屏保持唤醒的电量释放" "本环境 ps 不可用，分不开 App 的断言与合盖守护的"
else
    printf '80,ac,charging' > "$SUP_DIR/_sim-battery"
    "$B" config --battery 20 >/dev/null 2>&1
    "$B" config --battery-action 1 >/dev/null 2>&1      # 触底：恢复并撤销防睡眠
    "$B" plan --ac --keep-awake on >/dev/null 2>&1
    sleep 5
    if [ -z "$(keep_caff_pids)" ]; then
        skip_ "息屏保持唤醒的电量释放" "断言未装上（无可用亮度接口或助手缺失）"
    else
        printf '10,batt,discharging' > "$SUP_DIR/_sim-battery"
        released=0
        for _ in $(seq 1 22); do
            sleep 2
            if [ -z "$(keep_caff_pids)" ]; then released=1; break; fi
        done
        [ "$released" = "1" ] && ok "电量触底后断言被撤销（不会在包里放电到关机）" \
                              || bad "电量低于下限已 44 秒，断言仍在持有"
    fi
    rm -f "$SUP_DIR/_sim-battery"
    "$B" plan --ac --keep-awake off >/dev/null 2>&1
fi

# ---------- 15. 进程归属判定：只认可执行文件，不认命令行 ----------
echo
echo "【15】进程归属判定（不得被命令行里的路径字样骗到）"
# 归属判定曾经写成「ps -o command= 里有没有 lidkeep 子串」。命令行是调用方随便写的，
# 于是「正在跑 LidKeep 相关脚本的 shell」「在终端里 grep 这个路径的动作」「把路径当
# 参数传给别的命令的构建脚本」全都命中 —— 而这些恰好是用户操作 LidKeep 时最常存在的
# 进程。实测后果：App 启动接管 service.pid 时把自己的调试 shell SIGTERM 掉，表现为
# 「命令莫名其妙被掐断、没有任何输出」，几乎不可能联想到原因。
# 下面造一个「命令行里同时带着 lidkeep 与 nosleep-daemon 字样、可执行文件却是 bash」
# 的诱饵，验证它既不被告警、也不被清理。
bash -c 'sleep 60; true' /opt/homebrew/bin/lidkeep nosleep-daemon &
decoy=$!
DECOY_PIDS="$decoy"
sleep 0.6
if ! kill -0 "$decoy" 2>/dev/null; then
    skip_ "归属判定" "诱饵进程未成功启动"
elif ! pgrep -f "nosleep-daemon" 2>/dev/null | grep -qx "$decoy"; then
    # 陷阱必须真的上了膛：诱饵的命令行要确实带着 nosleep-daemon 字样，否则它诱不到
    # 任何按命令行判归属的写法，这条断言会空过。用 pgrep 核验（非 setuid，不受执行策略
    # 影响）；旧写法用 ps，于是本机能跑的时候它反而被跳过。
    skip_ "归属判定" "读不到诱饵的命令行（本环境限制了 argv 读取），诱饵无效"
else
    # ① 它不能被算进「我们的守护进程」——否则 doctor 会误报多守护、nosleep off 会去杀它
    hit=$("$B" doctor 2>/dev/null | grep -c "多个防睡眠守护并存" || true)
    [ "$hit" = "0" ] && ok "命令行带路径字样的无关进程不被认作自家守护" \
                     || bad "诱饵被认作自家守护：doctor 误报「多个防睡眠守护并存」"
    # ② nosleep off 的清理动作必须放过它（这条是真正的误杀回归位）
    "$B" nosleep off >/dev/null 2>&1
    sleep 0.5
    kill -0 "$decoy" 2>/dev/null && ok "nosleep off 的清理不误杀无关进程" \
                                || bad "无关进程被 nosleep off 误杀了（归属判定退回了按命令行子串）"
    # ③ 静态兜底：这类判据不允许再出现。Bar 与 CLI 共用 Ownership.swift 那一份实现，
    #    只要没有第二个判据冒出来，两边就不会再走样。
    if grep -qE 'contains\("lidkeep"\)|contains\("LidKeep"\)' Sources/Bar/main.swift Sources/CLI/main.swift 2>/dev/null; then
        bad "源码里又出现了按命令行子串判归属的写法（应改用 Sources/Shared/Ownership.swift）"
    else
        ok "归属判定统一走 Ownership.swift，源码中已无命令行子串判据"
    fi
fi
kill "$decoy" 2>/dev/null
wait "$decoy" 2>/dev/null      # 不加 wait 的话 bash 会在下次提示符时打一行 "Terminated: 15"
DECOY_PIDS=""

# ---------- 汇总 ----------
echo
echo "———— 结果：通过 ${pass}，失败 ${fail}，跳过 ${skip} ————"
# 还原动作已挂在 cleanup（EXIT trap）上，退出时自动执行
[ -f /tmp/bs_cfg_user_backup.json ] && echo "（config.json 将还原为测试前那份）"
[ "$fail" -eq 0 ] || exit 1
exit 0
