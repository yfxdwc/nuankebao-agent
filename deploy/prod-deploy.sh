#!/usr/bin/env bash
# ============================================
# 暖客宝 生产部署脚本 (tc 本机 Docker 隔离)
#
# 用法 (仓库根):
#   bash deploy/prod-deploy.sh                 # build → migrate → up → 健康检查
#   SKIP_MIGRATE=1 bash deploy/prod-deploy.sh  # 跳过 migration
#   SKIP_BUILD=1   bash deploy/prod-deploy.sh  # 只重启 (不重建镜像)
#
# 设计 (docs/deploy/production-plan.md §3.E2):
#   1) 前置检查: .env.prod 存在 + PROD_WEB_PORT 已设
#   2) 保存 rollback 镜像 tag (有旧镜像时)
#   3) build web + migrate 镜像
#   4) migrate (compose tools profile)
#   5) up -d + 健康检查 (127.0.0.1:${PROD_WEB_PORT}/api/health)
#   6) 失败 → 回滚镜像 + 重启, 非 0 退出
#
# 备份接入 (P3): deploy/backup.sh 加 prod profile 后, 在步骤 2 前调用。
#
# ⚠️ 只动 nuankebao-prod-* (独立 compose project/卷/端口):
#    dev = next dev :3003 + nuankebao-postgres :5432, 完全不受影响
# ============================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

ENV_FILE=".env.prod"
IMAGE="nuankebao-prod-web"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"

log()  { echo "[$(date '+%F %T')] $*"; }
fail() { echo "[$(date '+%F %T')] ❌ $*" >&2; exit 1; }

# ---- 0. 前置检查 ----
[ -f "$ENV_FILE" ] || fail "$ENV_FILE 不存在 (cp .env.prod.example .env.prod 并填值)"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
PORT="${PROD_WEB_PORT:-3004}"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

COMPOSE=(docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file "$ENV_FILE")

log "生产栈: project=nuankebao-prod web=127.0.0.1:${PORT} env=${ENV_FILE}"

# ---- 1. 保存 rollback 镜像 ----
if docker image inspect "${IMAGE}:latest" >/dev/null 2>&1; then
  docker tag "${IMAGE}:latest" "${IMAGE}:rollback"
  log "[1/5] 已保存 rollback 镜像 tag (${IMAGE}:rollback)"
else
  log "[1/5] 无旧镜像 (首次部署, 无 rollback)"
fi

# ---- 2. build ----
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  log "[2/5] SKIP_BUILD=1, 跳过构建"
else
  log "[2/5] 构建镜像 (web + migrate)..."
  "${COMPOSE[@]}" build web
  "${COMPOSE[@]}" --profile tools build migrate
fi

# ---- 3. migrate ----
if [ "${SKIP_MIGRATE:-0}" = "1" ]; then
  log "[3/5] SKIP_MIGRATE=1, 跳过 migration"
else
  log "[3/5] 数据库 migration (需要 postgres 已在跑)..."
  "${COMPOSE[@]}" up -d postgres
  "${COMPOSE[@]}" run --rm --no-deps migrate pnpm db:migrate \
    || fail "migration 失败: 未重启 web, 请查输出后决定回滚 (drizzle/down/)"
fi

# ---- 4. up ----
log "[4/5] 启动生产栈..."
"${COMPOSE[@]}" up -d

# ---- 5. 健康检查 + 回滚 ----
log "[5/5] 健康检查 ${HEALTH_URL} (最长 ${HEALTH_TIMEOUT}s)..."
ok=0
for _ in $(seq 1 "${HEALTH_TIMEOUT}"); do
  if curl -fsS -m 3 "$HEALTH_URL" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done

if [ "$ok" != "1" ]; then
  log "❌ 健康检查失败, 最近 50 行日志:"
  "${COMPOSE[@]}" logs --tail 50 web || true
  if docker image inspect "${IMAGE}:rollback" >/dev/null 2>&1; then
    log "回滚镜像 → ${IMAGE}:latest"
    docker tag "${IMAGE}:rollback" "${IMAGE}:latest"
    "${COMPOSE[@]}" up -d web || true
  fi
  fail "部署失败 (已尝试回滚; 手工排查: docker compose -p nuankebao-prod logs web)"
fi

log "✅ 部署成功: $(curl -fsS "$HEALTH_URL")"
