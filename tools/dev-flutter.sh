#!/usr/bin/env bash
# ============================================================
# 暖客宝 Flutter dev 启动脚本 (Web + Phone 并行)
#
# 用法:
#   ./tools/dev-flutter.sh                        # 只起 web
#   ./tools/dev-flutter.sh 192.168.1.10           # web + phone 并行 (默认)
#   ./tools/dev-flutter.sh 192.168.1.10 web       # 只起 web (指定 IP 备用)
#   ./tools/dev-flutter.sh 192.168.1.10 phone     # 只起 phone
#   ./tools/dev-flutter.sh 192.168.1.10 both      # 两个都起
#   ./tools/dev-flutter.sh --help
#
# 环境变量:
#   PHONE_IP        手机 IP (覆盖命令行参数)
#   PHONE_PORT      ADB 端口 (默认 5555)
#   WEB_PORT        Web 端口 (默认 8080)
#   WEB_HOST        Web 主机 (默认 0.0.0.0)
#   ENV             dart-define ENV 值 (默认 dev)
#
# ADR: docs/adr/0003-flutter-dev-workflow.md
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="$ROOT/flutter_app"

# ---------- 参数解析 ----------
PHONE_IP="${PHONE_IP:-}"
TARGET="${1:-both}"

if [ "$TARGET" = "--help" ] || [ "$TARGET" = "-h" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \?//'
  exit 0
fi

# 如果第一个参数是 IP (数字开头), 它是 PHONE_IP, 第二个参数是 TARGET
if [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  PHONE_IP="$TARGET"
  TARGET="${2:-both}"
fi

# 读 .env.local 兜底 (如果有 PHONE_IP=...)
if [ -z "$PHONE_IP" ] && [ -f "$ROOT/.env.local" ]; then
  PHONE_IP="$(grep -E '^PHONE_IP=' "$ROOT/.env.local" | cut -d= -f2- | tr -d '"' || true)"
fi

# ---------- 默认配置 ----------
PHONE_PORT="${PHONE_PORT:-5555}"
WEB_PORT="${WEB_PORT:-8080}"
WEB_HOST="${WEB_HOST:-0.0.0.0}"
ENV_VAL="${ENV:-dev}"

PID_DIR="/tmp/nuankebao-flutter"
mkdir -p "$PID_DIR"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }

# ---------- 预检 ----------
preflight() {
  if ! command -v flutter >/dev/null 2>&1; then
    err "flutter 未安装, 请先跑 install-flutter-sdk.sh"
    err "或 export PATH=\$HOME/flutter/bin:\$HOME/android-platform-tools/platform-tools:\$PATH"
    exit 1
  fi

  if [ ! -d "$FLUTTER_DIR" ]; then
    err "找不到 $FLUTTER_DIR"
    exit 1
  fi

  if ! command -v adb >/dev/null 2>&1; then
    warn "adb 未安装 (Phone 模式跑不了), 但 Web 仍可起"
  fi
}

# ---------- 启动 Web ----------
start_web() {
  log "🌐 启动 Web → http://${WEB_HOST}:${WEB_PORT}"
  (cd "$FLUTTER_DIR" && \
    flutter run -d web-server \
                --web-port="$WEB_PORT" \
                --web-hostname="$WEB_HOST" \
                --dart-define=ENV="$ENV_VAL") \
    > "$PID_DIR/web.log" 2>&1 &
  echo $! > "$PID_DIR/web.pid"
  ok "web PID=$(cat "$PID_DIR/web.pid"), 日志=$PID_DIR/web.log"
}

# ---------- 启动 Phone ----------
start_phone() {
  local ip="$1"

  if ! command -v adb >/dev/null 2>&1; then
    err "adb 未安装, 跳 phone"
    return 1
  fi

  log "📱 连接 Phone → ${ip}:${PHONE_PORT}"
  adb disconnect "${ip}:${PHONE_PORT}" 2>/dev/null || true
  if ! adb connect "${ip}:${PHONE_PORT}" 2>&1 | tee -a "$PID_DIR/adb.log" | grep -q "connected"; then
    err "❌ ADB 连不上 ${ip}:${PHONE_PORT}"
    err "   检查: 1) 手机和服务器同 WiFi  2) 手机开发者选项开了无线调试"
    return 1
  fi

  # 验证设备在列表
  if ! adb devices | grep -q "${ip}:${PHONE_PORT}.*device$"; then
    err "❌ ADB 连了但设备未授权 (unauthorized)"
    err "   检查: 手机屏幕有没有弹 '允许 USB 调试' 框"
    return 1
  fi

  log "📱 启动 Phone → ${ip}:${PHONE_PORT}"
  (cd "$FLUTTER_DIR" && \
    flutter run -d "${ip}:${PHONE_PORT}" \
                --dart-define=ENV="$ENV_VAL") \
    > "$PID_DIR/phone.log" 2>&1 &
  echo $! > "$PID_DIR/phone.pid"
  ok "phone PID=$(cat "$PID_DIR/phone.pid"), 日志=$PID_DIR/phone.log"
}

# ---------- 收尾 ----------
cleanup() {
  echo ""
  warn "🛑 收到退出信号, 收尾..."
  for name in web phone; do
    pidfile="$PID_DIR/${name}.pid"
    if [ -f "$pidfile" ]; then
      pid="$(cat "$pidfile")"
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        ok "stopped $name (pid=$pid)"
      fi
      rm -f "$pidfile"
    fi
  done
  exit 0
}
trap cleanup EXIT INT TERM

# ---------- 主流程 ----------
preflight

case "$TARGET" in
  web)
    start_web
    ok "✅ 只跑 web, 浏览器打开 http://${WEB_HOST}:${WEB_PORT}"
    ;;
  phone)
    if [ -z "$PHONE_IP" ]; then
      err "phone 模式需要 PHONE_IP (命令行参数或 .env.local)"
      exit 1
    fi
    start_phone "$PHONE_IP"
    ok "✅ 只跑 phone, 看手机屏幕"
    ;;
  both)
    start_web
    if [ -n "$PHONE_IP" ]; then
      start_phone "$PHONE_IP" || warn "phone 起失败, 继续 web"
    else
      warn "⚠️  没给 PHONE_IP, 只起 web"
      warn "   用法: $0 192.168.1.10"
    fi
    ok "✅ 并行模式"
    ok "   🌐 web    → http://${WEB_HOST}:${WEB_PORT}  (日志: $PID_DIR/web.log)"
    ok "   📱 phone  → ${PHONE_IP:-N/A}:${PHONE_PORT} (日志: $PID_DIR/phone.log)"
    ;;
  *)
    err "未知 TARGET=$TARGET (应为 web|phone|both)"
    exit 1
    ;;
esac

ok ""
ok "💡 快捷键 (在 flutter run 终端): r = hot reload, R = hot restart, q = quit"
ok "💡 实时日志: tail -f $PID_DIR/web.log 或 $PID_DIR/phone.log"
ok "🛑 停服务: Ctrl+C"

# 等后台进程
wait
