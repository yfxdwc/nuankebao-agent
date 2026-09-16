#!/usr/bin/env bash
# ============================================================
# 暖客宝 Flutter Web DEV SERVER 启动器 (秒级 hot reload)
#
# 用途: 让 /app-preview?dev=1 走 Flutter web dev server, 改代码秒级看到
#   - flutter run -d web-server → port 8080
#   - hot reload (保存 .dart 即自动 reload, 1-2s)
#   - 主人侧无操作: 同源 cookie 共享 + WebSocket 不被 CORS 拦
#
# 前置条件:
#   1. ./tools/install-flutter-dev-tunnel.sh 已跑一次 (cloudflared 加 path rule)
#   2. .env.local 有 APP_PORT (默认 3003) 跟 Next.js 一致
#
# 用法:
#   ./tools/start-flutter-dev.sh                    # 起 dev server, 后台跑
#   ./tools/start-flutter-dev.sh foreground         # 前台跑 (Ctrl+C 退出)
#   ./tools/start-flutter-dev.sh stop               # 停 dev server
#   ./tools/start-flutter-dev.sh status             # 看状态
#
# 配合 /app-preview?dev=1 路径:
#   - 主人浏览器: https://nuankebao.tooyang.top/app-preview?dev=1
#   - iframe src: /dev-app/ → cloudflared 反代 → 127.0.0.1:8080 (Flutter web dev)
#   - 改 flutter_app/lib/**/*.dart → 保存 → 1-2s 内 iframe 自动更新
#
# ADR: 主人 2026-09-16 拍, 配合 feature-customer-graph-uses-franchisee 任务
# 配套:
#   - tools/install-flutter-dev-tunnel.sh  (一次性 cloudflared patch)
#   - tools/stop-flutter-dev.sh             (本脚本 alias)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="$ROOT/flutter_app"

# ---------- 参数 ----------
TARGET="${1:-start}"

# ---------- 默认 ----------
WEB_PORT="${WEB_PORT:-8080}"
WEB_HOST="${WEB_HOST:-0.0.0.0}"
ENV_VAL="${ENV:-dev}"

PID_DIR="/tmp/nuankebao-flutter"
mkdir -p "$PID_DIR"
PID_FILE="$PID_DIR/dev.pid"
LOG_FILE="$PID_DIR/dev.log"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0:34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }

# ---------- 预检 ----------
preflight() {
  if ! command -v flutter >/dev/null 2>&1; then
    err "flutter 未安装 / 不在 PATH"
    err "  装 SDK: ./tools/install-flutter-sdk.sh  (~700MB)"
    err "  或手动: export PATH=\$HOME/flutter/bin:\$PATH"
    exit 1
  fi
  if [ ! -d "$FLUTTER_DIR" ]; then
    err "找不到 $FLUTTER_DIR"
    exit 1
  fi
  # 检测端口空闲
  if ss -ltn 2>/dev/null | grep -q ":$WEB_PORT "; then
    err "端口 $WEB_PORT 已占用, 改 WEB_PORT=8081 之类的"
    err "  或: lsof -i :$WEB_PORT 查谁在占"
    exit 1
  fi
}

# ---------- 子命令 ----------
cmd_start_bg() {
  preflight
  log "🚀 后台启动 Flutter web dev server → 127.0.0.1:$WEB_PORT"
  (cd "$FLUTTER_DIR" && \
    flutter run -d web-server \
                --web-port="$WEB_PORT" \
                --web-hostname="$WEB_HOST" \
                --dart-define=ENV="$ENV_VAL") \
    > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  ok "PID=$(cat "$PID_FILE"), 日志=$LOG_FILE"
  ok ""
  ok "用法:"
  ok "  主人浏览器:  https://nuankebao.tooyang.top/app-preview?dev=1"
  ok "  改代码:      编辑 flutter_app/lib/**/*.dart → 保存 → 1-2s iframe 自动更新"
  ok "  看实时日志:  tail -f $LOG_FILE"
  ok "  停服务:      $0 stop"
}

cmd_start_fg() {
  preflight
  log "🚀 前台启动 Flutter web dev server → 127.0.0.1:$WEB_PORT"
  log "💡 Ctrl+C 退出"
  exec flutter run -d web-server \
                   --web-port="$WEB_PORT" \
                   --web-hostname="$WEB_HOST" \
                   --dart-define=ENV="$ENV_VAL"
}

cmd_stop() {
  if [ ! -f "$PID_FILE" ]; then
    warn "PID file 不存在 ($PID_FILE), 没跑过"
    # 兜底: pkill
    pkill -f "flutter run -d web-server" 2>/dev/null && ok "pkill 兜底停掉" || warn "没找到 flutter run 进程"
    return
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    # 等最多 5s 让它退出
    for i in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      err "PID $pid 没退, kill -9"
      kill -9 "$pid" 2>/dev/null || true
    else
      ok "已停 dev server (PID=$pid)"
    fi
  else
    warn "PID $pid 不存在, 已退"
  fi
  rm -f "$PID_FILE"
  # 兜底再 pkill 一次 (防 wrapper 进程残留)
  pkill -f "frontend_server_aot" 2>/dev/null || true
}

cmd_status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    ok "Flutter web dev server 在跑 (PID=$(cat "$PID_FILE"))"
    log "  URL (LAN):  http://192.168.1.99:$WEB_PORT/"
    log "  URL (loopback): http://127.0.0.1:$WEB_PORT/"
    log "  日志:       tail -f $LOG_FILE"
  else
    warn "Flutter web dev server 没跑"
  fi
}

# ---------- 主流程 ----------
case "$TARGET" in
  start|background|bg)
    cmd_start_bg
    ;;
  foreground|fg)
    preflight
    cd "$FLUTTER_DIR"
    cmd_start_fg
    ;;
  stop|kill)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  restart)
    cmd_stop
    sleep 1
    cmd_start_bg
    ;;
  --help|-h)
    sed -n '2,30p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *)
    err "未知子命令: $TARGET"
    err "用法: $0 start|foreground|stop|status|restart"
    exit 1
    ;;
esac