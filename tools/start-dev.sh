#!/usr/bin/env bash
# ============================================================
# 暖客宝 dev server 启动脚本 (v2 - 带真机预览 QR)
#
# W12 修: sandbox 把进程 cwd 重置成 sales-ai 目录,导致 next dev
# 跑在 sales-ai 用默认 3000 端口. 必须显式 cd 到 nuankebao-agent.
#
# W14 新增: 启动成功后自动打印手机扫码 QR (走 tools/dev-qr.sh).
#
# 用法:
#   ./tools/start-dev.sh                        # 默认 APP_PORT (从 .env.local 读, 兜底 3010)
#   ./tools/start-dev.sh 3010                   # 指定端口
#   APP_PORT=3030 ./tools/start-dev.sh          # env 覆盖
#   NO_QR=1 ./tools/start-dev.sh                # 关掉 QR 打印
#   NO_CHECK_PORT=1 ./tools/start-dev.sh        # 跳过端口预检
# ============================================================
set -e

# 自动推导项目根 (AGENTS §6.3)
BBT_DIR="${BBT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="/tmp/nuankebao-dev.log"
PID_FILE="/tmp/nuankebao-dev.pid"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ---------- 参数: 端口 ----------
PORT="${1:-${APP_PORT:-${PORT:-3010}}}"

# 兜底: 从 .env.local 读 APP_PORT
if [ "$PORT" = "3010" ] && [ -z "${1:-}" ] && [ -z "${APP_PORT:-}" ] && [ -z "${PORT:-}" ]; then
  if [ -f "$BBT_DIR/.env.local" ]; then
    FROM_ENV=$(grep -E '^APP_PORT=' "$BBT_DIR/.env.local" | cut -d= -f2- | tr -d '"' || true)
    if [ -n "$FROM_ENV" ] && [[ "$FROM_ENV" =~ ^[0-9]+$ ]]; then
      PORT="$FROM_ENV"
    fi
  fi
fi

# ---------- 端口预检 (AGENTS.md §3 红线: 必须先 check) ----------
if [ "${NO_CHECK_PORT:-0}" != "1" ] && [ -x "$BBT_DIR/tools/check-port.sh" ]; then
  if ! "$BBT_DIR/tools/check-port.sh" "$PORT" >/dev/null 2>&1; then
    echo -e "${RED}✗ 端口 $PORT 被占用, 启动会失败${NC}"
    echo -e "${DIM}  跑 ./tools/check-port.sh --find 3000 9000 找空闲端口${NC}"
    echo -e "${DIM}  或: APP_PORT=新端口 ./tools/start-dev.sh${NC}"
    echo -e "${DIM}  强制跳过: NO_CHECK_PORT=1 ./tools/start-dev.sh${NC}"
    "$BBT_DIR/tools/check-port.sh" "$PORT" || true
    exit 1
  fi
  echo -e "${GREEN}✓${NC} 端口 ${CYAN}$PORT${NC} 空闲"
fi

# ---------- 杀旧进程 ----------
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" || true
    sleep 2
  fi
  rm -f "$PID_FILE"
fi

# ---------- 启动 (后台) ----------
cd "$BBT_DIR"  # 必须显式 cd,sandbox 会重置

# 用绝对路径调 next (next 是 shell script, 必须用 sh 跑)
nohup /bin/sh "$BBT_DIR/node_modules/.bin/next" dev -p "$PORT" -H 0.0.0.0 > "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

echo -e "${GREEN}✓${NC} 暖客宝 dev started (pid=$NEW_PID, port=$PORT, log=$LOG)"

# ---------- 等启动 ----------
READY=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/api/health" 2>/dev/null | grep -q 200; then
    READY=1
    break
  fi
done

if [ "$READY" = "1" ]; then
  echo -e "${GREEN}✓${NC} $PORT OK: $(curl -s "http://localhost:$PORT/api/health" | head -c 100)"
  echo

  # ---------- 打印 QR 码 (W14) ----------
  if [ "${NO_QR:-0}" != "1" ] && [ -x "$BBT_DIR/tools/dev-qr.sh" ]; then
    "$BBT_DIR/tools/dev-qr.sh" "$PORT" || {
      echo -e "${YELLOW}⚠ QR 打印失败, 不影响 dev server${NC}"
    }
  fi
else
  echo -e "${RED}✗ $PORT 没起来, 看 log: $LOG${NC}"
  tail -20 "$LOG"
  exit 1
fi
