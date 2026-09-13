#!/usr/bin/env bash
# ============================================================
# 暖客宝 守护安装 (idempotent, 重跑安全)
#
# 装:
#   1. systemd unit: nuankebao-stack.service → /etc/systemd/system/ + enable
#   2. crontab (mm7): @reboot post-boot-check
#
# 不装 (需主人先配置):
#   - backup cron      (需 BACKUP_PASSPHRASE in .env.local)
#   - adb-watchdog cron (需 PHONE_IP in .env.local + 真手机连上)
#
# 用法:
#   sudo ./tools/install-guards.sh
#
# 卸载:
#   sudo ./tools/install-guards.sh uninstall
# ============================================================
set -euo pipefail

BBT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="nuankebao-stack.service"
SERVICE_SRC="$BBT_DIR/tools/$SERVICE_NAME"
SERVICE_DST="/etc/systemd/system/$SERVICE_NAME"
CRON_USER="mm7"
POSTBOOT_LINE="@reboot sleep 60 && $BBT_DIR/tools/post-boot-check.sh >> /tmp/nuankebao-boot-check.log 2>&1"

say()  { printf '\033[36m[install-guards]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[install-guards]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[install-guards]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[install-guards]\033[0m %s\n' "$*" >&2; exit 1; }

# ============ uninstall 路径 ============
if [ "${1:-}" = "uninstall" ]; then
  [ "$(id -un)" = "root" ] || die "uninstall 需 sudo"
  say "卸载 $SERVICE_NAME"
  systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_DST"
  systemctl daemon-reload
  ok "systemd unit 已卸"

  say "卸 crontab post-boot-check (mm7)"
  TMP="$(mktemp)"
  crontab -u "$CRON_USER" -l 2>/dev/null > "$TMP" || true
  if grep -Fq "post-boot-check.sh" "$TMP"; then
    grep -Fv "post-boot-check.sh" "$TMP" > "${TMP}.new" && mv "${TMP}.new" "$TMP"
    crontab -u "$CRON_USER" "$TMP"
    ok "  cron 卸了"
  else
    warn "  cron 没装, 跳过"
  fi
  rm -f "$TMP" "${TMP}.new"
  ok "done — uninstall"
  exit 0
fi

# ============ install 路径 ============
[ "$(id -un)" = "root" ] || die "需 sudo 跑 (sudo ./tools/install-guards.sh)"
[ -f "$SERVICE_SRC" ] || die "缺 $SERVICE_SRC"
[ -f "$BBT_DIR/tools/post-boot-check.sh" ] || die "缺 post-boot-check.sh"

say "==== install 暖客宝 守护 ===="

# ---------- 1. systemd unit ----------
say "[1/2] 装 $SERVICE_NAME"
# sed 渲染 __PROJECT_DIR__ 占位符 → BBT_DIR (service 文件本身用占位符, 适配多机器)
sed "s|__PROJECT_DIR__|$BBT_DIR|g" "$SERVICE_SRC" > "$SERVICE_DST"
chmod 644 "$SERVICE_DST"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
ok "    enabled (reboot 后自动 docker compose up -d)"
warn "  当前未 start — 避免和 pnpm dev 撞 3003"
warn "  主人切换时: sudo systemctl start $SERVICE_NAME (起 docker stack)"
warn "  回切 dev:   sudo systemctl stop  $SERVICE_NAME"

# ---------- 2. crontab: post-boot-check ----------
say "[2/2] 装 crontab: @reboot post-boot-check (user=$CRON_USER)"

CRON_TMP="$(mktemp)"
crontab -u "$CRON_USER" -l 2>/dev/null > "$CRON_TMP" || true

if grep -Fq "post-boot-check.sh" "$CRON_TMP"; then
  warn "  已存在, 跳过"
else
  echo "$POSTBOOT_LINE" >> "$CRON_TMP"
  crontab -u "$CRON_USER" "$CRON_TMP"
  ok "    装了: $POSTBOOT_LINE"
fi
rm -f "$CRON_TMP"

# ---------- 3. 可选 cron (主人手动启用提示) ----------
echo ""
say "==== 可选 cron (主人在 .env.local 配密钥后手动启用) ===="
echo ""
echo "  # 备份 (每天 3 点, 需 BACKUP_PASSPHRASE=xxx in .env.local):"
echo "  0 3 * * * $BBT_DIR/tools/backup-cron.sh >> /tmp/nuankebao-backup.log 2>&1"
echo ""
echo "  # adb watchdog (每 2 分钟, 需 PHONE_IP in .env.local):"
echo "  */2 * * * * $BBT_DIR/tools/adb-watchdog.sh \$PHONE_IP >> /tmp/adb-watchdog.log 2>&1"
echo ""
ok "==== done ===="
echo ""
echo "验证命令:"
echo "  systemctl is-enabled $SERVICE_NAME"
echo "  crontab -u $CRON_USER -l"
echo "  sudo systemctl start $SERVICE_NAME   # 真要切 docker stack 时"
echo ""
