#!/usr/bin/env bash
# ============================================================
# 暖客宝 dev 模式一键启停 (postgres 容器 + systemd nuankebao-nextjs)
#
# 用法:
#   ./tools/dev-stack.sh              # 启 dev 全套
#   ./tools/dev-stack.sh stop         # 停 dev 全套 (保留 docker volume)
#   ./tools/dev-stack.sh restart      # 重启 systemd next dev (HMR 不掉线 5 秒)
#   ./tools/dev-stack.sh status       # 看状态 (等同 dev-status.sh)
#
# 设计:
#   dev 模式 = postgres (docker compose) + next dev (systemd, 端口 3003, HMR)
#   prod 模式 = postgres + web 容器 (走 nuankebao-stack.service, 后续 deploy 阶段)
#   两个模式互斥, 同一端口 3003 不能同时跑
#
# tc-full-deploy-2026-09-13 写入
# ============================================================
set -euo pipefail

# 拿 flutter / adb / java 等 dev 工具 (PATH 补全, 见 ~/.nuankebao_env)
[ -f ~/.nuankebao_env ] && . ~/.nuankebao_env

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }

CMD="${1:-up}"

# ---------- preflight ----------
preflight() {
  if ! command -v docker >/dev/null 2>&1; then
    err "docker 未装, 跑 install-docker.sh 或 sudo apt install docker.io"
    exit 1
  fi
  if ! systemctl --user --version >/dev/null 2>&1; then
    err "systemd --user 不可用, 检查 loginctl"
    exit 1
  fi
}

# ---------- 启 ----------
do_up() {
  preflight

  # 1. postgres 容器
  if docker ps --filter "name=nuankebao-postgres" --format "{{.Names}}" 2>/dev/null | grep -q nuankebao-postgres; then
    ok "✅ postgres 容器已在跑"
  else
    log "🐘 启 postgres 容器..."
    if ! docker compose up -d postgres 2>&1 | tail -5; then
      err "❌ postgres 启失败, 看 docker compose logs nuankebao-postgres"
      exit 1
    fi
  fi

  # 2. systemd nuankebao-nextjs
  if systemctl --user is-active nuankebao-nextjs >/dev/null 2>&1; then
    ok "✅ nuankebao-nextjs.service 已在跑"
  else
    log "🚀 启 nuankebao-nextjs.service..."
    systemctl --user start nuankebao-nextjs
  fi

  # 3. 等 Next.js ready
  log "⏳ 等 Next.js ready (最多 30s)..."
  for i in $(seq 1 6); do
    sleep 5
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3003/api/health 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "307" ] || [ "$code" = "404" ]; then
      ok "✅ Next.js ready (HTTP $code @ ${i}*5s)"
      break
    fi
    warn "   ${i}*5s ... HTTP $code"
  done

  ok ""
  ok "🎉 dev 就绪:"
  ok "   🌐 web    → http://0.0.0.0:3003"
  ok "   🐘 pg     → localhost:5432  (user: nuankebao, db: nuankebao)"
  ok ""
  ok "💡 状态:  ./tools/dev-status.sh"
  ok "💡 日志:  ./tools/dev-logs.sh -f"
  ok "💡 停服:  ./tools/dev-stack.sh stop"
  ok "💡 Flutter: ./tools/dev-flutter.sh <phone_ip>  (另开终端)"
}

# ---------- 停 ----------
do_stop() {
  log "🛑 停 dev 全套"
  if systemctl --user is-active nuankebao-nextjs >/dev/null 2>&1; then
    systemctl --user stop nuankebao-nextjs
    ok "✅ systemd nuankebao-nextjs 停了"
  else
    warn "systemd nuankebao-nextjs 本来就没跑"
  fi
  if docker ps --filter "name=nuankebao-postgres" --format "{{.Names}}" 2>/dev/null | grep -q nuankebao-postgres; then
    docker compose stop postgres
    ok "✅ postgres 容器停了 (volume 保留, 数据不丢)"
  else
    warn "postgres 容器本来就没跑"
  fi
}

# ---------- 重启 next dev ----------
do_restart() {
  log "🔄 重启 nuankebao-nextjs (postgres 不动)"
  systemctl --user restart nuankebao-nextjs
  sleep 3
  for i in $(seq 1 6); do
    sleep 5
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3003/api/health 2>/dev/null || echo "000")
    if [ "$code" != "000" ]; then
      ok "✅ Next.js ready (HTTP $code)"
      break
    fi
  done
}

# ---------- status ----------
do_status() {
  bash "$ROOT/tools/dev-status.sh"
}

case "$CMD" in
  up|start|"")  do_up ;;
  stop|down)    do_stop ;;
  restart)      do_restart ;;
  status|st)    do_status ;;
  -h|--help)
    sed -n '2,18p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *)
    err "未知命令: $CMD (用法: up|stop|restart|status)"
    exit 1
    ;;
esac