#!/usr/bin/env bash
# ============================================================
# 暖客宝 真机预览二维码生成器 (Bash wrapper)
#
# 用法:
#   ./tools/dev-qr.sh [port] [path]      # 默认端口 3010
#   ./tools/dev-qr.sh 3010 /admin
#   ./tools/dev-qr.sh --help
#
# 环境变量:
#   DEV_HOST         强制指定 LAN IP (默认自动选)
#   NO_FRAME=1       不要彩框 (只要裸 QR)
#   JSON=1           输出 JSON (管道/脚本友好)
#   PORT             端口兜底 (无参数时用)
#
# 典型用法:
#   ./tools/start-dev.sh 2>&1 | tee /tmp/dev.log    # start-dev 会自己调
#   ./tools/dev-qr.sh                                # 独立跑, 默认 3010
#   ./tools/dev-qr.sh 8080 /customers                # Flutter web
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/tools/dev-qr.cjs"

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  exit 0
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
fi

# ---------- 参数解析 ----------
PORT="${1:-${PORT:-3010}}"
URL_PATH="${2:-}"

# 校验端口
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  printf "${RED}✗ 端口必须是 1-65535 的数字, 收到: %s${NC}\n" "$PORT" >&2
  exit 2
fi

# ---------- 检查 node + qrcode ----------
if ! command -v node >/dev/null 2>&1; then
  printf "${RED}✗ node 未安装${NC}\n" >&2
  exit 1
fi

if [ ! -f "$SCRIPT" ]; then
  printf "${RED}✗ 找不到 %s${NC}\n" "$SCRIPT" >&2
  exit 1
fi

# ---------- 转发到 node ----------
# (不在这里 check 端口 — QR 只负责生成, 端口可用性由调用方负责.
#  start-dev.sh 会在前面预检, 独立调用 dev-qr.sh 时一般是 dev 已经在跑.)
NODE_ARGS=(--port "$PORT")

if [ -n "$URL_PATH" ]; then
  NODE_ARGS+=(--url "$URL_PATH")
fi

if [ -n "${DEV_HOST:-}" ]; then
  NODE_ARGS+=(--host "$DEV_HOST")
fi

if [ "${NO_FRAME:-0}" = "1" ]; then
  NODE_ARGS+=(--no-frame)
fi

if [ "${JSON:-0}" = "1" ]; then
  NODE_ARGS+=(--json)
fi

exec node "$SCRIPT" "${NODE_ARGS[@]}"
