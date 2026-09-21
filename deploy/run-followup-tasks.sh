#!/usr/bin/env bash
# ============================================================
# 每日跟进任务生成 — systemd timer 入口 (nuankebao-followup-tasks.timer)
# ============================================================
# 为什么套一层而不是 timer 直接跑 tsx:
#   1. systemd 的 ExecStart 不走 shell → 拿不到 .env.local / pnpm 的 PATH 解析
#   2. 脚本要**显式**加载 .env.local (scripts/_env.ts 只解析项目根的文件, 但 cwd 得先对)
#   3. 失败要能被 journalctl 看到 (set -euo pipefail + 明确 exit code)
#
# 幂等: 一人同时只留一条 pending + 同客户 7 天内只建一条 → 重复跑安全
# 手动跑: bash deploy/run-followup-tasks.sh           (真跑)
#         bash deploy/run-followup-tasks.sh --dry-run (只看会建几条)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if [ ! -f .env.local ]; then
  echo "❌ 缺 .env.local (DATABASE_URL) — 无法跑任务生成" >&2
  exit 1
fi

echo "==> 跟进任务生成 $(date -Is)"
npx tsx scripts/refresh-follow-up-tasks.ts "$@"
echo "==> 完成 $(date -Is)"
