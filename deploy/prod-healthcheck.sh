#!/usr/bin/env bash
# ============================================
# 暖客宝 生产健康检查 (P3)
#
# 触发: nuankebao-prod-healthcheck.timer (每 5 分钟, systemd user)
# 行为:
#   - 健康 → 静默退出 (不写日志, 免刷屏)
#   - 不健康 → restart nuankebao-prod-web → 10s 后复检
#     复检成功: 记 OK 日志; 仍失败: 记 FATAL 日志 + exit 1 (journal 可见)
#
# 只动 prod 容器 (nuankebao-prod-web); dev (3003) 不碰。
# ============================================
set -uo pipefail

PORT="${PROD_WEB_PORT:-3004}"
URL="http://127.0.0.1:${PORT}/api/health"
LOG="${NUANKEBAO_PROD_HEALTH_LOG:-$HOME/nuankebao-databackups/prod/logs/healthcheck.log}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
mkdir -p "$(dirname "$LOG")"

if curl -fsS -m 5 "$URL" >/dev/null 2>&1; then
    exit 0
fi

echo "$(ts) [WARN] health check 失败: $URL → 重启 nuankebao-prod-web" >> "$LOG"
if ! docker restart nuankebao-prod-web >> "$LOG" 2>&1; then
    echo "$(ts) [FATAL] docker restart nuankebao-prod-web 失败" >> "$LOG"
    exit 1
fi

sleep 10
if curl -fsS -m 5 "$URL" >/dev/null 2>&1; then
    echo "$(ts) [OK] 重启后已恢复" >> "$LOG"
    exit 0
fi

echo "$(ts) [FATAL] 重启后仍不健康, 需人工排查: docker compose -p nuankebao-prod logs web" >> "$LOG"
exit 1
