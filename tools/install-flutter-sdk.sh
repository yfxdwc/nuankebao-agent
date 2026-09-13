#!/usr/bin/env bash
# ============================================================
# 暖客宝 Flutter SDK + ADB 安装脚本 (免 sudo)
#
# 安装位置:
#   ~/flutter                              (Flutter SDK)
#   ~/android-platform-tools/platform-tools (ADB)
#
# 配 PATH: 增量追加到 ~/.bashrc (不覆盖)
#
# 用法:
#   ./tools/install-flutter-sdk.sh           # 装 Flutter 3.24.5 + ADB
#   FLUTTER_VERSION=3.27.0 ./tools/install-flutter-sdk.sh
#
# ADR: docs/adr/0003-flutter-dev-workflow.md
# ============================================================
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
ADB_DIR="${ADB_DIR:-$HOME/android-platform-tools}"
BASHRC="${BASHRC:-$HOME/.bashrc}"

echo "==> 配置"
echo "    FLUTTER_VERSION: $FLUTTER_VERSION"
echo "    FLUTTER_CHANNEL: $FLUTTER_CHANNEL"
echo "    FLUTTER_DIR:     $FLUTTER_DIR"
echo "    ADB_DIR:         $ADB_DIR"
echo "    BASHRC:          $BASHRC"
echo ""

# ---------- 装 Flutter ----------
if [ -d "$FLUTTER_DIR" ] && [ -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "==> Flutter 已存在, 跳过下载"
else
  echo "==> 下载 Flutter ${FLUTTER_VERSION} (~700MB)..."
  TARBALL="/tmp/flutter-install.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"
  echo "    URL: $URL"
  curl -L --connect-timeout 30 --max-time 900 -o "$TARBALL" "$URL"
  echo "==> 解压到 $FLUTTER_DIR ..."
  cd ~
  tar -xf "$TARBALL"
  rm -f "$TARBALL"
  echo "    完成"
fi

# ---------- 装 ADB (platform-tools) ----------
if [ -x "$ADB_DIR/platform-tools/adb" ]; then
  echo "==> ADB 已存在, 跳过下载"
else
  echo "==> 下载 platform-tools (~50MB)..."
  ZIP="/tmp/platform-tools-install.zip"
  URL="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
  curl -L --connect-timeout 30 --max-time 300 -o "$ZIP" "$URL"
  echo "==> 解压到 $ADB_DIR ..."
  mkdir -p "$ADB_DIR"
  cd "$ADB_DIR"
  unzip -q -o "$ZIP"
  rm -f "$ZIP"
  echo "    完成"
fi

# ---------- 配 PATH ----------
echo ""
echo "==> 配 PATH (写入 $BASHRC)"
add_to_bashrc() {
  local marker="$1"
  local line="$2"
  if grep -qF "$marker" "$BASHRC" 2>/dev/null; then
    echo "    已存在: $marker"
  else
    echo "" >> "$BASHRC"
    echo "# $marker" >> "$BASHRC"
    echo "$line" >> "$BASHRC"
    echo "    已追加: $line"
  fi
}

add_to_bashrc "Flutter SDK (暖客宝)" "export PATH=\"\$HOME/flutter/bin:\$PATH\""
add_to_bashrc "Android platform-tools (暖客宝 ADB)" "export PATH=\"\$HOME/android-platform-tools/platform-tools:\$PATH\""

# ---------- 当前 shell 也生效 ----------
export PATH="$FLUTTER_DIR/bin:$ADB_DIR/platform-tools:$PATH"

# ---------- Flutter 首次配置 ----------
echo ""
echo "==> Flutter 首次配置"
git config --global --add safe.directory "$FLUTTER_DIR"
"$FLUTTER_DIR/bin/flutter" --disable-analytics 2>&1 | head -3 || true
"$FLUTTER_DIR/bin/flutter" config --no-analytics 2>&1 | head -3 || true

# ---------- 验证 ----------
echo ""
echo "==> 验证"
"$FLUTTER_DIR/bin/flutter" --version 2>&1 | head -5
"$ADB_DIR/platform-tools/adb" version 2>&1 | head -2

# ---------- 后续提示 ----------
echo ""
echo "==> ✅ 装完"
echo ""
echo "新开终端 (或 source ~/.bashrc) 后:"
echo "    flutter --version"
echo "    adb version"
echo ""
echo "下一步:"
echo "    1. cd ~/nuankebao-agent/flutter_app"
echo "    2. flutter pub get"
echo "    3. flutter doctor            # 看 Android toolchain 是否齐"
echo "    4. ./tools/dev-flutter.sh    # 一键起 web (或 phone + web 并行)"
echo ""
echo "💡 Android SDK / cmdline-tools 如果 flutter doctor 报缺, 见:"
echo "    https://docs.flutter.dev/get-started/install/linux/android"
