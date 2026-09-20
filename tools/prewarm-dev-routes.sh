#!/usr/bin/env bash
# ============================================================
# 暖客宝 Next.js Dev Mode 路由预编译脚本
#
# 用途: 把 src/app/api/** 下所有 list 路由 (无动态参数) curl 一次,
#   强制 Next.js dev mode 提前编译, 避免主人打开预览时撞冷编译
#   (实测最坏 43s, dio 10s timeout 直接抛「网络不太好」).
#
# 为什么不全编译: 动态路由 (/api/customers/[id]) 需要真实 ID + auth,
#   冷编译本身还是会触发 (401 也算编译完), 但 list 路由已覆盖
#   主人打开 /app-preview 后会立即 hit 的核心 API.
#
# 用法:
#   ./tools/prewarm-dev-routes.sh                     # 预编译 (默认 localhost:3003)
#   ./tools/prewarm-dev-routes.sh 192.168.1.99:3003   # 指定 host
#   APP_URL=http://192.168.1.99:3003 ./tools/prewarm-dev-routes.sh
#   ./tools/prewarm-dev-routes.sh --quiet             # 只输出汇总
#
# 触发时机:
#   - 主人重启 nuankebao-nextjs.service 后手跑一次
#   - 改 / 加新 API 路由后跑一次 (新路由要触发首次编译)
#   - 可选: 加到 systemd ExecStartPost= (在 install-systemd.sh)
#
# 关联:
#   - flutter_app/lib/core/http/api_client.dart  dio connectTimeout
#     web 模式 60s (兜住冷编译最坏情况)
#   - src/app/api/**/route.ts                  路由源 (本脚本自动发现)
#
# ADR: docs/login-failure-triage.md (待补, 跟 R12 一类的「治本沉淀」)
# CHANGELOG [0.5.3] 引入: 2026-09-20, w21 预览频繁「网络不太好」治本
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$ROOT/src/app/api"
LOG_FILE="/tmp/nuankebao-prewarm-dev-routes.log"

# ---------- 参数 ----------
QUIET=false
APP_URL="${APP_URL:-http://127.0.0.1:3003}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q)
      QUIET=true
      shift
      ;;
    --help|-h)
      sed -n '3,30p' "$0"
      exit 0
      ;;
    *)
      # 兼容旧用法: ./tools/prewarm-dev-routes.sh <host:port>
      if [[ "$1" =~ ^[a-zA-Z0-9._-]+:[0-9]+$ ]]; then
        APP_URL="http://$1"
      else
        echo "未知参数: $1 (用 --help 看用法)" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { $QUIET || echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { $QUIET || echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { $QUIET || echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
title(){ $QUIET || echo -e "\n${CYAN}==>${NC} $*"; }

# ---------- 0. 前置检查 ----------
title "前置检查"
log "APP_URL: $APP_URL"
log "API_DIR: $API_DIR"

if [[ ! -d "$API_DIR" ]]; then
  err "API 目录不存在: $API_DIR"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  err "curl 不在 PATH"
  exit 1
fi

# 检查 dev server 是否活着 (避免冷启动预编译撞 wall)
if ! curl -sS -o /dev/null -m 5 "$APP_URL/api/health" 2>/dev/null; then
  err "dev server 不在 $APP_URL (5s 内连不上)"
  err "请先 ./tools/start-dev.sh 或 systemctl --user start nuankebao-nextjs.service"
  exit 1
fi
ok "dev server 活 ✓"

# ---------- 1. 自动发现 list 路由 ----------
title "1. 自动发现 list 路由 (无 [id] 动态参数)"

# 模式: src/app/api/<path>/route.ts, 排除含 [ 的 (动态路由)
mapfile -t ROUTES < <(
  # find 返回绝对路径 (因 $API_DIR 是绝对), sed 只 strip 路径中 src/app/api 之前部分,
  # 保留 /api/... 前缀 (URL 要带)
  find "$API_DIR" -name "route.ts" -type f \
    | grep -v '/\[' \
    | sed -e "s|^.*/src/app/api|/api|" \
          -e 's|/route\.ts$||' \
    | sort
)

ROUTE_COUNT=${#ROUTES[@]}
log "发现 $ROUTE_COUNT 个 list 路由"

if [[ $ROUTE_COUNT -eq 0 ]]; then
  err "没找到任何 list 路由 (route.ts), 检查 $API_DIR"
  exit 1
fi

# 打印路由列表 (quiet 模式不打印)
if ! $QUIET; then
  printf '   %s\n' "${ROUTES[@]}" | sed 's|^/api/|     /api/|'
fi

# ---------- 2. 逐个 curl 预编译 ----------
title "2. 逐个 curl 预编译 (触发 Next.js dev lazy compile)"

START_TS=$(date +%s)
SUCCESS=0
FAIL=0
TOTAL_MS=0

for route in "${ROUTES[@]}"; do
  # 把 filesystem 路径转成 URL path
  url_path=$(echo "$route" | tr -d ' ')
  url="$APP_URL$url_path"

  # curl: -s 静默, -o /dev/null 丢 body, -w 写时, --max-time 60 (兜住最坏冷编译)
  t0=$(date +%s%3N)
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 60 "$url" 2>/dev/null || echo "000")
  t1=$(date +%s%3N)
  elapsed=$((t1 - t0))
  TOTAL_MS=$((TOTAL_MS + elapsed))

  # 状态分类:
  #   200 = 成功 (公开路由)
  #   401/403 = 成功 (认证路由编译完了, 只是没 auth)
  #   405 = 成功 (路由存在, GET 不支持但编译完了)
  #   其他 = 失败
  case "$http_code" in
    2*|401|403|405)
      SUCCESS=$((SUCCESS + 1))
      status_mark="✓"
      ;;
    *)
      FAIL=$((FAIL + 1))
      status_mark="✗"
      ;;
  esac

  if ! $QUIET; then
    printf "   %s %3d  %5dms  %s\n" "$status_mark" "$http_code" "$elapsed" "$url_path"
  fi
done

END_TS=$(date +%s)
TOTAL_S=$((END_TS - START_TS))

# ---------- 3. 汇总 ----------
title "3. 汇总"

ok "预编译完成: $SUCCESS/$ROUTE_COUNT 成功, $FAIL 失败"
log "总耗时: ${TOTAL_S}s (sum ${TOTAL_MS}ms, 平均 $((TOTAL_MS / (ROUTE_COUNT == 0 ? 1 : ROUTE_COUNT)))ms/route)"

if [[ $FAIL -gt 0 ]]; then
  warn "⚠ $FAIL 个路由失败 (可能: dev server 异常 / 路由 bug / 网络中断)"
  warn "  详情: $LOG_FILE"
fi

# ---------- 4. 写日志 ----------
{
  echo "[$(date -Iseconds)] prewarm: $SUCCESS/$ROUTE_COUNT ok, ${TOTAL_S}s"
  for route in "${ROUTES[@]}"; do
    echo "  $route"
  done
} >> "$LOG_FILE" 2>/dev/null || true

echo ""
ok "✅ dev 路由预编译完成 — 现在打开 /app-preview, API 响应会快 (<500ms)"
ok "   下次冷启动 (重启 nextjs / 改新路由) 后再跑一次本脚本"

exit 0
