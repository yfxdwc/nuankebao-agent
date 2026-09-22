#!/usr/bin/env bash
# ============================================================
# 使用数据保留期清理 — systemd timer 入口 (nuankebao-usage-retention.timer)
# ============================================================
# 主人 2026-09-22 拍: 原始用量事件 180 天后删 (USAGE_RETENTION_DAYS 可配)
#
# 目标库选择:
#   1. 生产栈在跑 (nuankebao-prod-postgres) 且 .env.prod 存在 → 通过 compose
#      migrate 镜像跑 (只有它带 tsx + 完整源码; 与 dev 数据隔离)
#   2. 否则退回 dev (.env.local)
#
# 幂等: 删除是时间条件操作, 重复跑第二次删 0 条
# 手动跑: bash deploy/run-usage-retention.sh                    (真删 180 天前)
#         USAGE_RETENTION_DAYS=90 bash deploy/run-usage-retention.sh
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DAYS="${USAGE_RETENTION_DAYS:-180}"

if [ -f .env.prod ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^nuankebao-prod-postgres$'; then
  echo "==> 生产库保留期清理 (days=$DAYS) $(date -Is)"
  docker compose -p nuankebao-prod -f docker-compose.prod.yml --env-file .env.prod \
    run --rm --no-deps migrate npx tsx scripts/usage-retention.ts --days="$DAYS"
  echo "==> 完成 $(date -Is)"
  exit 0
fi

if [ ! -f .env.local ]; then
  echo "❌ 既无生产栈在跑, 也没有 .env.local — 无法执行保留期清理" >&2
  exit 1
fi

echo "==> dev 库保留期清理 (days=$DAYS) $(date -Is)"
npx tsx scripts/usage-retention.ts --days="$DAYS"
echo "==> 完成 $(date -Is)"
