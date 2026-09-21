#!/usr/bin/env bash
# 公证脚手架（Notarization scaffold）
#
# ⚠️ 本脚本需要你自己的付费 Apple Developer 账号与 Developer ID 证书。
#    项目当前是 ad-hoc 签名（无证书），本脚本不会被 CI 自动调用，也不会改动
#    现有发布流程——它只是把「拿到证书后如何一键公证」的步骤固化下来。
#
# 前置条件：
#   1. 加入 Apple Developer Program（$99/年）。
#   2. 在 Xcode → Settings → Accounts 或 developer.apple.com 创建：
#        - "Developer ID Application" 证书（用于签名 .app）
#        - "Developer ID Installer" 证书（用于签名 .pkg，若走 pkg 分发）
#   3. 申请一个 App-Specific Password（appleid.apple.com → 安全 → App 专用密码），
#      用作 NOTARIZE_PASSWORD。
#   4. 记下你的 10 位 Team ID（developer.apple.com → Membership）。
#
# 用法：
#   APPLE_ID=you@example.com \
#   APPLE_ID_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#   TEAM_ID=ABCDE12345 \
#   ./packaging/notarize.sh 2.2.3
#
# 流程：重签（Developer ID + runtime）→ 生成 dmg/pkg → notarytool 提交 →
#       等待 → staple（把票据钉进制品，离线也能通过 Gatekeeper）。

set -euo pipefail

VER="${1:?用法: notarize.sh <版本号, 如 2.2.3>}"
APPLE_ID="${APPLE_ID:?请设置 APPLE_ID（你的 Apple 账号）}"
APPLE_ID_PASSWORD="${APPLE_ID_PASSWORD:?请设置 APPLE_ID_PASSWORD（App 专用密码）}"
TEAM_ID="${TEAM_ID:?请设置 TEAM_ID（10 位 Team ID）}"

APP_ID="com.lidkeep.bar"          # 与 Info.plist 的 CFBundleIdentifier 一致
INSTALLER_ID="com.lidkeep.bar.installer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/LidKeep.app"
DMG="build/dmgout/LidKeep-$VER.dmg"
PKG="build/pkgout/LidKeep-$VER.pkg"

echo "==> 1. 构建（make all 会注入版本号 $VER 并重签前的准备）"
make all

echo "==> 2. 用 Developer ID 重签 .app（含 --options runtime 才能过公证）"
# 先撤销 ad-hoc 残留，再正式签名
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep --options runtime \
  --sign "Developer ID Application: $TEAM_ID" "$APP"

echo "==> 3. 生成 dmg / pkg（用 Developer ID Installer 签 pkg）"
./packaging/make_dmg.sh "$VER"
./packaging/make_pkg.sh "$VER"
if [ -f "$PKG" ]; then
  productsign --sign "Developer ID Installer: $TEAM_ID" "$PKG" "${PKG}.signed" \
    && mv "${PKG}.signed" "$PKG"
fi

submit_and_staple() {
  local file="$1" label="$2"
  echo "==> 4. 公证 $label: $file"
  xcrun notarytool submit "$file" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
  echo "==> 5. 钉票据 (staple): $file"
  xcrun stapler staple "$file"
  xcrun stapler validate "$file"
}

submit_and_staple "$DMG" "DMG"
[ -f "$PKG" ] && submit_and_staple "$PKG" "PKG"

echo "✅ 公证完成。把钉过票据的 $DMG / $PKG 上传到 GitHub Release 即可，"
echo "   用户下载后双击即可安装，无需再手动 xattr -dr 清 quarantine。"
echo "   记得同时更新 README 的「Unsigned」小节，标注已公证。"
