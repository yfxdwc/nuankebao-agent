#!/usr/bin/env bash
# ============================================================
# 暖客宝 dev 状态总览 (systemd + docker + 端口 + 日志)
#
# 用法:
#   ./tools/dev-status.sh
#
# 显示:
#   - nuankebao-nextjs.service (systemd user) 状态
#   - nuankebao-postgres 容器状态
#   - 端口 3003 / 5432 / 5434 占用
#   - /tmp/nuankebao-*.log 日志大小
#   - Flutter / adb / docker 可用性
# ============================================================
set -uo pipefail

# 拿 flutter / adb / java 等 dev 工具 (PATH 补全, 见 ~/.nuankebao_env)
[ -f ~/.nuankebao_env ] && . ~/.nuankebao_env

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()    { printf "${GREEN}✅${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠️${NC}  %s\n" "$*"; }
err()   { printf "${RED}❌${NC} %s\n" "$*"; }
hdr()   { printf "\n${BLUE}━━━ %s ━━━${NC}\n" "$*"; }

# ---------- systemd ----------
hdr "systemd user service"
if systemctl --user is-active nuankebao-nextjs >/dev/null 2>&1; then
  ok "nuankebao-nextjs.service active"
  systemctl --user status nuankebao-nextjs --no-pager 2>&1 | grep -E "Main PID|Memory|CPU|active since" | head -4 | sed 's/^/    /'
else
  warn "nuankebao-nextjs.service NOT active"
  echo "    启: ./tools/dev-stack.sh"
fi

# ---------- docker ----------
hdr "docker containers"
if command -v docker >/dev/null 2>&1; then
  docker ps --filter "name=nuankebao" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
    | awk -F'\t' '{
        status = $2
        if (status ~ /Up/) { printf "    " "\033[0;32m✅\033[0m %-22s %s\n", $1, status }
        else               { printf "    " "\033[1;33m⚠️\033[0m  %-22s %s\n", $1, status }
      }'
else
  err "docker 未装"
fi

# ---------- ports ----------
hdr "端口占用"
for port in 3003 5432 5434; do
  if ss -tln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
    proc=$(ss -tlnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | head -1 | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$proc" ]; then
      cmd=$(ps -p "$proc" -o comm= 2>/dev/null || echo "?")
      printf "    ${YELLOW}✗${NC}  %-6s 占用 (pid=%s, %s)\n" "$port" "$proc" "$cmd"
    else
      printf "    ${YELLOW}✗${NC}  %-6s 占用 (未知进程)\n" "$port"
    fi
  else
    printf "    ${GREEN}✓${NC}  %-6s 空闲\n" "$port"
  fi
done

# ---------- 日志 ----------
hdr "日志 (/tmp/nuankebao-*.log)"
ls -lh /tmp/nuankebao-*.log 2>/dev/null \
  | awk '{printf "    %-40s %5s\n", $9, $5}' \
  || warn "  无日志文件"

# ---------- 工具链 ----------
hdr "工具链 (PATH)"
for cmd in flutter adb java javac docker pnpm node; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ver=$(timeout 3 "$cmd" --version 2>&1 | head -1 | cut -c1-60 || echo "?")
    printf "    ${GREEN}✓${NC}  %-8s %s\n" "$cmd" "$ver"
  else
    printf "    ${RED}✗${NC}  %-8s NOT FOUND\n" "$cmd"
  fi
done

# ---------- adb 设备 ----------
hdr "adb 设备"
adb devices 2>&1 | sed 's/^/    /'

# ---------- health ----------
hdr "健康检查"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3003/ 2>/dev/null || echo "000")
if [ "$code" = "000" ]; then
  err "127.0.0.1:3003 unreachable"
else
  ok "127.0.0.1:3003 → HTTP $code (Next.js dev server)"
fi

pg=$(pg_isready -h localhost -p 5432 2>&1 | tail -1 || echo "FAIL")
if [[ "$pg" == *"accepting"* ]]; then
  ok "localhost:5432 → $pg"
else
  warn "localhost:5432 → $pg"
fi