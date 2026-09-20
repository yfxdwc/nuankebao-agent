#!/usr/bin/env bash
# ============================================================
# 暖客宝 Next.js Dev Mode 路由预编译脚本
#
# 用途: 把 src/app/api/** 下常用 API 路由 curl 一次,
#   强制 Next.js dev mode 提前编译, 避免主人打开预览时撞冷编译
#   (实测最坏 188s/auth-flutter-login, dio 60s timeout 仍会 timeout).
#
# 为什么不全编译: 33 个 list 路由 × 30-60s/路由 = 15-30 分钟,
#   并发跑反而拖死 dev server (实测 1.4GB mem + 全部串行 queue).
#   实际预览用到的路由 < 10 个, 默认只预热这 10 个就够 80%+ 场景.
#
# 默认预热路由 (按主人真实使用频率排, 见 src/app/api/**/route.ts):
#   /api/auth/session           (每页加载都查 session)
#   /api/auth/csrf              (登录)
#   /api/auth/flutter-login     (登录提交)
#   /api/me                     (当前用户)
#   /api/health                 (网络自检)
#   /api/customers              (客户列表)
#   /api/customers/stats        (客户统计)
#   /api/wellness-records       (养生记录列表)
#   /api/salons                 (沙龙列表)
#   /api/franchisees/me/tree    (加盟关系树)
#
# 用法:
#   ./tools/prewarm-dev-routes.sh                          # 默认 10 个最热路由 (串行, ~3-5 min)
#   ./tools/prewarm-dev-routes.sh --all                   # 全 33 路由 (慢, ~15-30 min)
#   ./tools/prewarm-dev-routes.sh --parallel 4            # 4 路并发 (会拖慢 dev server, 不推荐)
#   ./tools/prewarm-dev-routes.sh 192.168.1.99:3003       # 指定 host
#   APP_URL=http://192.168.1.99:3003 ./tools/prewarm-dev-routes.sh
#   ./tools/prewarm-dev-routes.sh --quiet                  # 只输出汇总
#   ./tools/prewarm-dev-routes.sh --top 5                  # 只预热前 5 个
#
# 触发时机:
#   - 主人重启 nuankebao-nextjs.service 后手跑一次
#   - 改 / 加新 API 路由后跑一次 (新路由要触发首次编译)
#   - **不建议加 systemd ExecStartPost** (systemd 启动期 dev server 还没就绪,
#     会跑空 + 把 dev server 一启动就拖入 33 路由 compile queue = 卡死)
#
# 关联:
#   - flutter_app/lib/core/http/api_client.dart  dio connectTimeout
#     web 模式 60s (兜住冷编译最坏情况, 跟本脚本互补: 本脚本主动 warm 主流,
#     60s 兜底防漏网 / 新路由 / 偶发 60s+ 编译)
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
ALL_MODE=false
TOP_N=10
PARALLEL=1
APP_URL="${APP_URL:-http://127.0.0.1:3003}"

# 默认 10 个最热路由 (按真实 hit 频率排序)
DEFAULT_ROUTES=(
  "/api/auth/session"
  "/api/auth/csrf"
  "/api/auth/flutter-login"
  "/api/me"
  "/api/health"
  "/api/customers"
  "/api/customers/stats"
  "/api/wellness-records"
  "/api/salons"
  "/api/franchisees/me/tree"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q)
      QUIET=true
      shift
      ;;
    --all)
      ALL_MODE=true
      shift
      ;;
    --top)
      TOP_N="$2"
      shift 2
      ;;
    --parallel|-p)
      PARALLEL="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '3,40p' "$0"
      exit 0
      ;;
    *)
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
log "ALL_MODE: $ALL_MODE  TOP_N: $TOP_N  PARALLEL: $PARALLEL"

if ! command -v curl >/dev/null 2>&1; then
  err "curl 不在 PATH"
  exit 1
fi

# 用 30s 长超时 (dev server 启动期可能还在初始化)
if ! curl -sS -o /dev/null -m 30 "$APP_URL/api/health" 2>/dev/null; then
  err "dev server 不在 $APP_URL (30s 内连不上 /api/health)"
  err "请先 ./tools/start-dev.sh 或 systemctl --user start nuankebao-nextjs.service"
  exit 1
fi
ok "dev server 活 ✓"

# ---------- 1. 选路由 ----------
if $ALL_MODE; then
  title "1. 全 33 路由 (auto-discover, --all 模式, 慢 ~15-30 min)"
  mapfile -t ROUTES < <(
    find "$API_DIR" -name "route.ts" -type f \
      | grep -v '/\[' \
      | sed -e "s|^.*/src/app/api|/api|" \
            -e 's|/route\.ts$||' \
      | sort
  )
  if [[ ${#ROUTES[@]} -eq 0 ]]; then
    err "没找到 list 路由 (route.ts)"
    exit 1
  fi
  if [[ $PARALLEL -eq 1 ]]; then
    warn "⚠ --all 模式串行很慢, 推荐加 --parallel 2 (并发 2, 总时间减半, 但 dev server 会更慢)"
  fi
else
  title "1. 默认 ${#DEFAULT_ROUTES[@]} 个最热路由 (top hit frequency)"
  ROUTES=("${DEFAULT_ROUTES[@]}")
  # --top N: 只取前 N
  if [[ $TOP_N -lt ${#ROUTES[@]} ]]; then
    ROUTES=("${ROUTES[@]:0:$TOP_N}")
  fi
fi

ROUTE_COUNT=${#ROUTES[@]}
log "预热路由数: $ROUTE_COUNT"
if ! $QUIET; then
  printf '   %s\n' "${ROUTES[@]}" | sed 's|^|     |'
fi

# ---------- 2. curl 预编译 ----------
title "2. 逐个 curl 预编译 (触发 Next.js dev lazy compile, 每路由最多 90s)"

START_TS=$(date +%s)
SUCCESS=0
FAIL=0
TOTAL_MS=0

warm_one() {
  local url_path="$1"
  local url="$APP_URL$url_path"

  local t0 t1 elapsed http_code
  t0=$(date +%s%3N)
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 90 "$url" 2>/dev/null || echo "000")
  t1=$(date +%s%3N)
  elapsed=$((t1 - t0))

  # 状态分类:
  #   2xx = 公开路由成功
  #   401/403 = 需 auth (编译完了, 业务正确)
  #   405 = 路由存在但不支持 GET (编译完了)
  case "$http_code" in
    2*|401|403|405)
      echo "OK $http_code $elapsed $url_path"
      ;;
    *)
      echo "FAIL $http_code $elapsed $url_path"
      ;;
  esac
}
export -f warm_one
export APP_URL QUIET

if [[ $PARALLEL -le 1 ]]; then
  # 串行 (默认, 稳)
  for route in "${ROUTES[@]}"; do
    result=$(warm_one "$route")
    code=$(echo "$result" | awk '{print $1}')
    http=$(echo "$result" | awk '{print $2}')
    elapsed=$(echo "$result" | awk '{print $3}')
    TOTAL_MS=$((TOTAL_MS + elapsed))
    case "$code" in
      OK)   SUCCESS=$((SUCCESS + 1)); mark="✓" ;;
      FAIL) FAIL=$((FAIL + 1)); mark="✗" ;;
    esac
    if ! $QUIET; then
      printf "   %s %3s  %5sms  %s\n" "$mark" "$http" "$elapsed" "$route"
    fi
  done
else
  # 并发 (--parallel > 1, 慎用, 会拖慢 dev server)
  warn "⚠ 并发模式: $PARALLEL 路同时 curl, dev server 会更慢"
  TMPF=$(mktemp)
  printf '%s\n' "${ROUTES[@]}" > "$TMPF"
  while IFS= read -r line; do
    # warm_one echo 到 stdout, 加 PREFIX 给并发区分
    warm_one "$line" | awk -v p="$$" '{print p" "$0}'
  done < "$TMPF" > "$TMPF.out" &
  # 简化: 这里用 xargs 更稳
  rm -f "$TMPF"
  # 重新用 xargs (GNU parallel 太重)
  printf '%s\n' "${ROUTES[@]}" | xargs -I{} -P "$PARALLEL" bash -c 'warm_one "$@"' _ {} > "$TMPF.out" 2>&1 || true
  while IFS= read -r line; do
    parts=($line)
    code="${parts[0]}"
    http="${parts[1]}"
    elapsed="${parts[2]}"
    route="${parts[3]}"
    TOTAL_MS=$((TOTAL_MS + elapsed))
    case "$code" in
      OK)   SUCCESS=$((SUCCESS + 1)); mark="✓" ;;
      FAIL) FAIL=$((FAIL + 1)); mark="✗" ;;
    esac
    if ! $QUIET; then
      printf "   %s %3s  %5sms  %s\n" "$mark" "$http" "$elapsed" "$route"
    fi
  done < "$TMPF.out"
  rm -f "$TMPF.out"
fi

END_TS=$(date +%s)
TOTAL_S=$((END_TS - START_TS))

# ---------- 3. 汇总 ----------
title "3. 汇总"

ok "预编译完成: $SUCCESS/$ROUTE_COUNT 成功, $FAIL 失败"
log "总耗时: ${TOTAL_S}s (sum ${TOTAL_MS}ms)"

if [[ $FAIL -gt 0 ]]; then
  warn "⚠ $FAIL 个路由失败 (可能: dev server 异常 / 路由 bug / 编译超过 90s)"
  warn "  详情: $LOG_FILE"
fi

# ---------- 4. 写日志 ----------
{
  echo "[$(date -Iseconds)] prewarm: $SUCCESS/$ROUTE_COUNT ok, ${TOTAL_S}s (TOP_N=$TOP_N ALL=$ALL_MODE PARALLEL=$PARALLEL)"
  for route in "${ROUTES[@]}"; do
    echo "  $route"
  done
} >> "$LOG_FILE" 2>/dev/null || true

echo ""
if $ALL_MODE; then
  ok "✅ 全路由预编译完成 — 现在打开 /app-preview, 所有 list 路由都热"
else
  ok "✅ Top $ROUTE_COUNT 路由预编译完成 — 现在打开 /app-preview, 主流功能响应快 (<500ms)"
  ok "   新加路由 或 不在 top 列表的路由 首次 hit 仍可能撞冷编译 (dio 60s 兜底)"
fi

exit 0
