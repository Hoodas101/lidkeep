#!/usr/bin/env bash
# 公证（Notarization）—— 一次跑完「重签 → 公证 → 钉票据 → 自检」。
#
# 为什么必须做：ad-hoc 签名的产物会被 Gatekeeper 判为不可信，用户双击打不开，
# 甚至可能被直接丢进废纸篓；pkg / dmg / brew 每条路径都得手工执行一次
#   xattr -dr com.apple.quarantine /Applications/LidKeep.app
# 走完公证后，上面这些步骤全部消失，变成普通双击。
#
# 用法：
#   ./packaging/notarize.sh 2.2.6              # 正式公证（需证书 + 凭据）
#   ./packaging/notarize.sh 2.2.6 --dry-run    # 只验链路：ad-hoc + hardened runtime，不提交
#
# --dry-run 不是玩具：它用和正式模式**完全相同**的签名参数（ad-hoc 无时间戳服务器，
# 故 --timestamp 除外）走完整条打包链路，把「重签 → 打包 dmg/pkg/zip → 产物自检」
# 全部真跑一遍，用来提前暴露那些只有真跑才会现形的问题 —— 比如本脚本自己踩过的
# 那个：macOS 自带的 bash 3.2 会把紧贴变量的全角字符吃进变量名。
#
# 边界要说清楚：--dry-run **不覆盖运行时**。App 在 hardened runtime 下能否正常
# dlopen 私有框架、spawn 子进程，签名合法并不保证 —— 只有把签好名的 App 真正
# 启动一次才知道。这一步请在真机上手工确认（启动后看菜单栏图标是否出现）。
#
# 前置条件（正式模式）：
#   1. 加入 Apple Developer Program（$99/年）。
#   2. 在 Xcode → Settings → Accounts 或 developer.apple.com 创建并下载：
#        "Developer ID Application" 证书（签 .app 与 CLI）
#        "Developer ID Installer"   证书（签 .pkg）
#   3. App 专用密码：appleid.apple.com → 登录与安全 → App 专用密码。
#   4. 10 位 Team ID：developer.apple.com → Membership。
#
# 环境变量：
#   APPLE_ID / APPLE_ID_PASSWORD / TEAM_ID    正式模式必需
#   SIGN_ID / INSTALLER_SIGN_ID               证书全名，缺省时自动从钥匙串里挑
#
# 正式模式示例：
#   APPLE_ID=you@example.com \
#   APPLE_ID_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#   TEAM_ID=ABCDE12345 \
#   ./packaging/notarize.sh 2.2.6
#
# ⚠️ 步骤顺序不是随意的，每一步的注释都写明了为什么必须是这个顺序。
#
# ⚠️ 变量引用一律写成 ${VAR} 形式，不要写成 $VAR 形式：macOS 自带的 /bin/bash 是 3.2，
#    它会把紧跟变量名之后的多字节字符（如全角「）」）的字节吃进变量名，
#    于是在 `set -u` 下直接报 "VER）: unbound variable"。bash 4+ 已修复该问题，
#    但 Apple 因 GPLv3 不会更新 /bin/bash，只能靠这条写法约定自己守住。

set -euo pipefail

VER=""
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -*) echo "未知参数: $arg" >&2; exit 2 ;;
        *)  VER="$arg" ;;
    esac
done
[ -n "$VER" ] || { echo "用法: notarize.sh <版本号, 如 2.2.6> [--dry-run]" >&2; exit 2; }
VER="${VER#v}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/LidKeep.app"
CLI_BIN="build/lidkeep"
DMG="build/dmgout/LidKeep-$VER.dmg"
PKG="build/pkgout/LidKeep-$VER.pkg"
ZIP="build/zipout/lidkeep-macos.zip"

# ---------------------------------------------------------------- 1. 预检
#
# 必须在动任何文件**之前**把凭据查清楚：否则会在 make all / 重签之后才失败，
# 留下一个「已撤销 ad-hoc 签名、又没签上 Developer ID」的半成品，
# 后面每一次构建都得先手工清理才能恢复。
if [ "$DRY_RUN" = "1" ]; then
    SIGN_ID="-"
    INSTALLER_SIGN_ID=""
    echo "==> DRY-RUN：用 ad-hoc + hardened runtime 验证链路（不提交公证）"
else
    : "${APPLE_ID:?请设置 APPLE_ID（你的 Apple 账号）}"
    : "${APPLE_ID_PASSWORD:?请设置 APPLE_ID_PASSWORD（App 专用密码）}"
    : "${TEAM_ID:?请设置 TEAM_ID（10 位 Team ID）}"

    # 自动挑证书：用户不必记住 "Developer ID Application: 张三 (ABCDE12345)" 这一长串。
    # 旧版脚本把 Team ID 当证书名传给 --sign，那是错的 —— codesign 按证书的 CN 匹配，
    # 只给 Team ID 会直接报 "no identity found"，而且是在重签那一步才报，太晚。
    pick_identity() {
        local kind="$1"
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n "s/.*\"\\(${kind}: [^\"]*\\)\".*/\\1/p" | head -1
    }
    [ -n "${SIGN_ID:-}" ] || SIGN_ID="$(pick_identity "Developer ID Application")"
    if [ -z "${SIGN_ID:-}" ]; then
        echo "❌ 钥匙串里找不到 \"Developer ID Application\" 证书。" >&2
        echo "   security find-identity -v -p codesigning   # 看看现在有什么" >&2
        echo "   没有的话需要先加入 Apple Developer Program 并创建该证书。" >&2
        echo "   想先验证链路（不提交公证）：./packaging/notarize.sh $VER --dry-run" >&2
        exit 1
    fi
    [ -n "${INSTALLER_SIGN_ID:-}" ] || INSTALLER_SIGN_ID="$(pick_identity "Developer ID Installer")"
    echo "==> 签名身份: $SIGN_ID"
    [ -n "$INSTALLER_SIGN_ID" ] && echo "==> 安装包身份: $INSTALLER_SIGN_ID"
fi

SIGN_ARGS=(--force --options runtime --sign "$SIGN_ID")
[ "$DRY_RUN" = "0" ] && SIGN_ARGS+=(--timestamp)

# ---------------------------------------------------------------- 2. 构建并重签
echo "==> 1/6 构建（make all 会注入版本号 ${VER}）"
make all

echo "==> 2/6 用 Developer ID 重签 CLI 与 .app"
# 先撤销 ad-hoc 残留再正式签名，避免 --force 之下新旧签名混在一起。
# 顺序：先内层可执行文件、再外层 bundle —— 反过来会让 bundle 的封印
# 记录下内层**旧**的哈希，verify 时报 "resource envelope is obsolete"。
codesign --remove-signature "$CLI_BIN" 2>/dev/null || true
codesign --remove-signature "$APP"     2>/dev/null || true

codesign "${SIGN_ARGS[@]}" "$CLI_BIN"
# 刻意**不用** --deep：Apple 已明确不建议用它签名（它会把残留的 *.cstemp 之类中间产物
# 也当成待签子组件，从而反复失败且错误被吞掉 —— 本项目真踩过，App 静默停在
# linker-signed 状态）。本 bundle 里只有一个 Mach-O 和一个 icns，没有嵌套代码，
# 逐个签反而更准确。
codesign "${SIGN_ARGS[@]}" "$APP"

echo "==> 校验签名"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|flags" | sed 's/^/    /' || true

# ---------------------------------------------------------------- 3. 公证 .app
#
# 为什么先单独公证 .app：zip 分发（lidkeep-macos.zip）里装的是裸 .app，
# 而**票据只能钉在 .app 上，钉不进 zip**。所以必须先让 .app 自己带上票据，
# 再拿它去打包 —— 顺序反了，zip 用户解压出来的 App 就得联网才能过 Gatekeeper。
notarize_and_staple() {
    local target="$1" label="$2"
    echo "==> 公证 $label: $target"
    xcrun notarytool submit "$target" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    echo "==> 钉票据: $target"
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
}

if [ "$DRY_RUN" = "0" ]; then
    echo "==> 3/6 公证 .app（先压缩成临时 zip 再提交 —— notarytool 不收裸 bundle）"
    TMPZIP="build/notarize-app.zip"
    rm -f "$TMPZIP"
    ditto -c -k --keepParent "$APP" "$TMPZIP"
    notarize_and_staple "$TMPZIP" "app 载荷"
    rm -f "$TMPZIP"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
else
    echo "==> 3/6 跳过 .app 公证（dry-run）"
fi

# ---------------------------------------------------------------- 4. 打包并公证
echo "==> 4/6 生成 dmg / pkg / zip"
./packaging/make_dmg.sh "$VER"
./packaging/make_pkg.sh "$VER"

# zip 直接由**已钉票据的 .app** 组装，不再单独公证（zip 本身不可钉）。
# 用 ditto 而不是 zip：ditto 会保留扩展属性与资源分叉，zip 会破坏签名封印。
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# dmg 与 pkg 各自也需要票据（用户下载的是这两个文件本身）。
if [ "$DRY_RUN" = "0" ]; then
    echo "==> 5/6 公证 dmg 与 pkg"
    notarize_and_staple "$DMG" "DMG"
    if [ -n "$INSTALLER_SIGN_ID" ] && [ -f "$PKG" ]; then
        # 用 Installer 证书签 pkg，再公证。pkg 的签名与 .app 的签名是两套东西：
        # 前者保证安装器本身可信，后者保证装进去的 App 可信，缺一不可。
        productsign --sign "$INSTALLER_SIGN_ID" "$PKG" "$PKG.signed"
        mv "$PKG.signed" "$PKG"
        notarize_and_staple "$PKG" "PKG"
    elif [ -f "$PKG" ]; then
        echo "⚠️  没有 Developer ID Installer 证书，pkg 未签名也未公证（dmg 与 zip 不受影响）"
    fi
else
    echo "==> 5/6 跳过 dmg / pkg 公证（dry-run）"
fi

# ---------------------------------------------------------------- 5. 自检
echo "==> 6/6 自检"
# spctl 是 Gatekeeper 的判据本身 —— 只有它说 accepted，用户的机器才会放行。
if [ "$DRY_RUN" = "1" ]; then
    echo "    （dry-run 用 ad-hoc 签名，spctl 预期 rejected，这不是失败）"
    "$CLI_BIN" version 2>&1 | head -1 | sed 's/^/    CLI 可执行: /'
    echo "    hardened runtime 已开在 .app 上，确认："
    codesign -dv "$APP" 2>&1 | grep -E "flags" | sed 's/^/    /' || true
else
    for f in "$APP" "$DMG"; do
        [ -e "$f" ] || continue
        kind="open"; [ "${f##*.}" = "app" ] && kind="exec"
        if spctl -a -t "$kind" -vv "$f" 2>&1 | grep -q "accepted"; then
            echo "    ✅ Gatekeeper 放行: $f"
        else
            echo "    ❌ Gatekeeper 仍拒绝: ${f}（公证或钉票据没生效）"
            spctl -a -vv "$f" 2>&1 | sed 's/^/       /' || true
            exit 1
        fi
    done
fi

echo
echo "✅ 完成。产物："
for f in "$DMG" "$PKG" "$ZIP"; do [ -f "$f" ] && ls -lh "$f" | sed 's/^/    /'; done
echo
echo "上传到 GitHub Release 后，记得同步更新 README 的「未公证：装前清一次隔离标记」小节 ——"
echo "公证生效后那一整节应当删掉，而不是继续教用户执行 xattr。"
