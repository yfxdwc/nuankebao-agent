#!/usr/bin/env bash
# ============================================================
# 暖客宝 开机自检 — reboot 后 60s 自动跑 (@reboot cron)
#
# 验证 7 件:
#   1. docker daemon
#   2. nuankebao-stack.service 状态 (装了的话)
#   3. nuankebao-* 容器存活
#   4. port 3003 监听
#   5. nuankebao-cloudflared.service active
#   6. /home 磁盘使用率 (warn if >80%)
#   7. /api/health (可选, dev 模式可能没起)
#
# 输出: /tmp/nuankebao-boot-check.log
# 退出码: 永远 0 (不让 cron 邮件噪音; 错误看日志)
# ============================================================
set -uo pipefail

LOG="${BBT_BOOT_LOG:-/tmp/nuankebao-boot-check.log}"
PROJECT_DIR="${BBT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
TS() { date '+%Y-%m-%d %H:%M:%S'; }

{
  echo "===== 暖客宝 post-boot check @ $(TS) ====="
  echo "host: $(hostname) kernel=$(uname -r)"

  # 1. docker
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ FAIL: docker 未安装"
  elif ! docker info >/dev/null 2>&1; then
    echo "❌ FAIL: docker daemon 未运行"
  else
    echo "✅ docker daemon OK"
  fi

  # 2. nuankebao-stack.service
  if systemctl list-unit-files nuankebao-stack.service >/dev/null 2>&1; then
    STATE=$(systemctl show nuankebao-stack.service -p ActiveState --value 2>/dev/null || echo "unknown")
    echo "ℹ️  nuankebao-stack.service: ${STATE}"
    if [ "$STATE" != "active" ]; then
      echo "   (主人需要时: sudo systemctl start nuankebao-stack.service)"
    fi
  else
    echo "ℹ️  nuankebao-stack.service 未装 (跑 tools/install-guards.sh 装)"
  fi

  # 3. containers
  RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -cE '^nuankebao-' || true)
  TOTAL=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -cE '^nuankebao-' || true)
  echo "ℹ️  nuankebao-* 容器: ${RUNNING}/${TOTAL} running"
  docker ps -a --format '   {{.Names}}\t{{.Status}}' 2>/dev/null \
    | grep -E '^nuankebao-' || echo "   (无 nuankebao-* 容器 — 还没起 stack)"

  # 4. port 3003
  if ss -tlnp 2>/dev/null | grep -q ':3003 '; then
    echo "✅ port 3003 listening"
  else
    echo "⚠️  port 3003 未监听 (dev mode 未跑 或 stack 未起)"
  fi

  # 5. cloudflared
  if systemctl is-active --quiet nuankebao-cloudflared.service 2>/dev/null; then
    echo "✅ nuankebao-cloudflared.service active"
  else
    echo "⚠️  nuankebao-cloudflared.service not active"
  fi

  # 6. disk
  DISK_PCT=$(df /home 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
  if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt 80 ] 2>/dev/null; then
    echo "⚠️  disk /home: ${DISK_PCT}% (>80%, 建议清理)"
  elif [ -n "$DISK_PCT" ]; then
    echo "✅ disk /home: ${DISK_PCT}%"
  fi

  # 7. /api/health (stack 起了再探)
  HEALTH=$(curl -sf -m 5 http://localhost:3003/api/health 2>/dev/null || true)
  if [ -n "$HEALTH" ]; then
    echo "✅ /api/health: ${HEALTH}"
  else
    echo "ℹ️  /api/health 未响应 (正常 — dev/stack 未起 或无此端点)"
  fi

  echo "===== done @ $(TS) ====="
  echo ""
} >> "$LOG" 2>&1

# 保留最近 50 行 (避免 /tmp 膨胀)
if [ -f "$LOG" ]; then
  tail -n 50 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG" 2>/dev/null || true
fi

exit 0
