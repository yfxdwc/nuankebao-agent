#!/usr/bin/env bash
# ============================================================
# 暖客宝 release APK 打包 (带签名校验) —— 主人 2026-09-21
#
# 为什么单独一个脚本:
#   主人问「升级 app 后能保持登录状态吗」→ 答案的关键是**签名密钥一致**。
#   Android 只允许"同签名的包"覆盖安装; 签名变了必须先卸载 → app 数据(含登录凭证)全丢。
#   本脚本在打包前检查签名材料、打包后打印签名指纹, 让这件事**可核对**。
#
# 用法:
#   bash tools/build-apk.sh                       # 默认生产域名 (nuankebao.tooyang.top)
#   bash tools/build-apk.sh http://192.168.1.200:3004   # 指定 API base (局域网内测)
#   bash tools/build-apk.sh --no-build            # 只检查签名材料 + 打印现有 APK 指纹
#
# 输出: flutter_app/build/app/outputs/flutter-apk/app-release.apk
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/flutter_app"
KEY_PROPS="$APP_DIR/android/key.properties"
export JAVA_HOME="${JAVA_HOME:-/home/tooyan/jdk}"
export PATH="$JAVA_HOME/bin:$PATH:/home/tooyan/flutter/bin"

API_BASE="${1:-https://nuankebao.tooyang.top}"
BUILD=1
[ "${1:-}" = "--no-build" ] && { BUILD=0; API_BASE="https://nuankebao.tooyang.top"; }

echo "=============================================="
echo " 暖客宝 release APK"
echo "=============================================="

# ---------- 1. 签名材料检查 (缺了就别打, 否则会打出 debug 签名的包) ----------
if [ ! -f "$KEY_PROPS" ]; then
  echo "✗ 缺少 $KEY_PROPS"
  echo "  → release 构建必须用正式签名, 否则用户装不上 (要先卸载 = 丢登录态和数据)"
  exit 1
fi
STORE_FILE="$(grep -oP '(?<=storeFile=).*' "$KEY_PROPS")"
if [ ! -f "$STORE_FILE" ]; then
  echo "✗ key.properties 指向的 keystore 不存在: $STORE_FILE"
  exit 1
fi
echo "✓ 签名材料: $STORE_FILE"

# ---------- 2. 打包 ----------
if [ "$BUILD" = "1" ]; then
  echo "→ flutter build apk --release --dart-define=NUANKEBAO_API_BASE=$API_BASE"
  ( cd "$APP_DIR" && flutter build apk --release \
      --dart-define="NUANKEBAO_API_BASE=$API_BASE" )
fi

APK="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "✗ 没找到产物: $APK"
  exit 1
fi

# ---------- 3. 打印指纹 (发版前拿它跟旧版 App 里「网络自检 → 安装包」对一眼) ----------
echo
echo "=============================================="
echo " 产物"
echo "=============================================="
ls -la "$APK" | awk '{printf "  文件: %s\n  大小: %.1f MB\n", $NF, $5/1024/1024}'
echo "  API : $API_BASE"
echo
echo "  签名指纹 (必须与线上版本一致, 否则用户要先卸载):"
keytool -printcert -jarfile "$APK" 2>/dev/null \
  | grep -E "SHA256:|SHA1:|所有者|Owner" | sed 's/^/    /' \
  || echo "    (keytool 读不出 — 检查 JAVA_HOME)"
echo
echo "  对照办法: 旧版 App → 我的 → 网络自检 → 「安装包」那行, 签名前 16 位应完全一致"
