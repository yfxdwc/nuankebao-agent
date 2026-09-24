#!/usr/bin/env bash
# ============================================
# 暖客宝 dev 健康检查 (3003)
#
# 触发: nuankebao-dev-healthcheck.timer (每 2 分钟, systemd user)
# 行为:
#   - 健康 → 静默退出 (不写日志, 免刷屏)
#   - 冷却期内 → 写一行 [SKIP] 日志后静默退出 (防 flapping)
#   - 不健康 → restart nuankebao-nextjs.service → 等待冷编译 → 复检 (最多 3 次)
#     复检成功: 记 [OK] 日志; 仍失败: 记 [FATAL] 日志 + exit 1 (journal 可见)
#
# 与 prod-healthcheck (3004) 互补:
#   - prod 是 docker 容器, restart 几秒就绪, 复检窗口短;
#     dev 是 next dev, 冷编译可能 10-30s (首次访问 /login 触发 webpack 编译),
#     所以复检最多等 ~45s (15s × 3 次).
#   - 只动 dev (nuankebao-nextjs.service), 绝不碰 prod 容器.
#
# 存在理由 (主人 2026-09-24 提问):
#   systemd `Restart=always` 只在进程**退出**时生效;
#   next dev 涨到 1.5G 卡死时**进程还活着**, 所以 systemd 不会救.
#   本守护通过主动 curl 探测发现"端口在但 HTTP 假死", 触发 restart.
# ============================================
set -uo pipefail

PORT="${DEV_WEB_PORT:-3003}"
URL="http://127.0.0.1:${PORT}/login"
LOG="${NUANKEBAO_DEV_HEALTH_LOG:-$HOME/nuankebao-databackups/logs/dev-healthcheck.log}"
COOLDOWN="${DEV_HEALTH_COOLDOWN_SECONDS:-300}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
mkdir -p "$(dirname "$LOG")"

# ---- 冷却期保护 (防 flapping) ----
# 若 nuankebao-nextjs.service 距上次进入 active 不超过 COOLDOWN 秒,
# 认为服务"刚被重启, 还在冷编译/稳定期", 跳过本次检查 (写一行 SKIP).
# 典型场景: systemd RestartSec=30 自己救活一次, 我们 2 分钟后立刻又 restart,
#           叠加可能让服务永远在冷编译里出不来.
NOW_EPOCH="$(date +%s)"
LAST_RESTART_TS="$(systemctl --user show -p ActiveEnterTimestamp --value nuankebao-nextjs.service 2>/dev/null || true)"
if [[ -n "$LAST_RESTART_TS" ]]; then
    LAST_RESTART_EPOCH="$(date -d "$LAST_RESTART_TS" +%s 2>/dev/null || echo 0)"
    if [[ "$LAST_RESTART_EPOCH" =~ ^[0-9]+$ ]] && (( LAST_RESTART_EPOCH > 0 )); then
        AGE=$(( NOW_EPOCH - LAST_RESTART_EPOCH ))
        if (( AGE < COOLDOWN )); then
            echo "$(ts) [SKIP] 冷却期内 (nuankebao-nextjs.service 距上次启动 ${AGE}s < ${COOLDOWN}s), 不重启" >> "$LOG"
            exit 0
        fi
    fi
fi

# ---- 健康探测 ----
if curl -fsS -m 10 "$URL" >/dev/null 2>&1; then
    exit 0
fi

# ---- 不健康 → 重启 + 复检 ----
echo "$(ts) [WARN] health check 失败: $URL → 重启 nuankebao-nextjs.service" >> "$LOG"
if ! systemctl --user restart nuankebao-nextjs.service >> "$LOG" 2>&1; then
    echo "$(ts) [FATAL] systemctl restart nuankebao-nextjs.service 失败" >> "$LOG"
    exit 1
fi

# dev 冷编译可能 10-30s; 复检最多 3 次 (每次 sleep 15 + curl -m 15)
for attempt in 1 2 3; do
    sleep 15
    if curl -fsS -m 15 "$URL" >/dev/null 2>&1; then
        echo "$(ts) [OK] 重启后已恢复 (attempt ${attempt}/3)" >> "$LOG"
        exit 0
    fi
    echo "$(ts) [RETRY] attempt ${attempt}/3 仍未恢复, 再等 15s" >> "$LOG"
done

echo "$(ts) [FATAL] 重启后仍不健康, 需人工排查: journalctl --user -u nuankebao-nextjs -n 200" >> "$LOG"
exit 1
