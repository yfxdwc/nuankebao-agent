#!/usr/bin/env bash
# ============================================================
# 暖客宝 ADB watchdog - 自动重连无线调试 (防手机断线)
#
# 用法:
#   ./tools/adb-watchdog.sh <手机IP> [端口]         # 单次跑 (手动/cron 都调这个)
#   ./tools/adb-watchdog.sh --install-cron <手机IP> # 装 */2 分钟 cron (幂等)
#   ./tools/adb-watchdog.sh --remove-cron           # 卸 cron
#
# cron 装好后:
#   */2 * * * * $SELF_PATH 192.168.1.10 >> /tmp/adb-watchdog.log 2>&1
#
# 退出码:
#   0 = 已连接 / 重连成功 / install/remove 成功
#   1 = 重连失败 (需要人工介入: 重插 USB 或重新无线配对)
# ============================================================
set -uo pipefail

# 自动推导项目根 + 自己路径 (AGENTS §6.3)
BBT_DIR="${BBT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SELF_PATH="$BBT_DIR/tools/adb-watchdog.sh"

CRON_MARKER="# 暖客宝 adb-watchdog (auto-installed, do not edit)"
CRON_LINE_TEMPLATE="*/2 * * * * $SELF_PATH __TARGET__ >> /tmp/adb-watchdog.log 2>&1"

# ---------- 子命令分发 ----------
case "${1:-}" in
  --install-cron)
    PHONE_IP="${2:?用法: $0 --install-cron <手机IP>}"
    PHONE_PORT="${3:-5555}"
    TARGET="${PHONE_IP}:${PHONE_PORT}"
    CRON_LINE_ACTUAL="${CRON_LINE_TEMPLATE//__TARGET__/$TARGET}"
    # 幂等: 先按 marker 删旧 (含空行), 再追加新
    (crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" | grep -vF "adb-watchdog.sh ${TARGET}" || true
     echo "$CRON_MARKER"
     echo "$CRON_LINE_ACTUAL") | crontab -
    echo "✅ cron 已装: $CRON_LINE_ACTUAL"
    echo "   验证: crontab -l | grep adb-watchdog"
    echo "   日志: tail -f /tmp/adb-watchdog.log"
    exit 0
    ;;
  --remove-cron)
    (crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" | grep -vF "adb-watchdog.sh" || true) | crontab -
    echo "✅ cron 已卸"
    exit 0
    ;;
esac

# ---------- 默认: 单次跑 ----------
PHONE_IP="${1:?用法: $0 <手机IP> [端口] | --install-cron <手机IP> | --remove-cron}"
PHONE_PORT="${2:-5555}"
TARGET="${PHONE_IP}:${PHONE_PORT}"
LOG="${ADB_WATCHDOG_LOG:-/tmp/adb-watchdog.log}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ADB 不在 → 直接退出 (不报错)
if ! command -v adb >/dev/null 2>&1; then
  log "SKIP: adb 未安装"
  exit 0
fi

# 已经在 connected 状态
if adb devices 2>/dev/null | awk 'NR>1 && $1=="'"$TARGET"'" {print $2}' | grep -q "^device$"; then
  log "OK: $TARGET 已连接"
  exit 0
fi

# 杀旧连接 (如有)
adb disconnect "$TARGET" 2>/dev/null || true
sleep 1

# 尝试重连 (5 次, 间隔 3s)
for i in 1 2 3 4 5; do
  log "尝试重连 $TARGET ($i/5)"
  if adb connect "$TARGET" 2>&1 | grep -q "connected to"; then
    # 验证设备就绪
    sleep 2
    if adb devices 2>/dev/null | grep -q "$TARGET.*device$"; then
      log "✅ $TARGET 重连成功"
      exit 0
    else
      log "⚠️  $TARGET 连接了但设备未就绪 (unauthorized?)"
    fi
  fi
  sleep 3
done

log "❌ $TARGET 重连失败, 需要人工介入"
log "   检查: 1) 手机和服务器同 WiFi  2) 无线调试还开着  3) 重新无线配对"
exit 1
