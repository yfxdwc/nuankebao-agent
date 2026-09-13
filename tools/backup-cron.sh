#!/usr/bin/env bash
# ============================================================
# ⚠ DEPRECATED 2026-09-08 — 已迁移到 systemd timer
#
# 新版调度 (dev-domain-backup SOP §3.0.3):
#   - nuankebao-backup.timer (日 03:00) + nuankebao-backup.service
#   - 装: ./deploy/install-systemd.sh
#   - 验证: systemctl --user list-timers nuankebao-*
#
# 本脚本保留供历史 (cron 老配置仍能跑, 但不推荐).
# 详见 deploy/README.md §10 + ~/.muse/skills/dev-domain-backup/SKILL.md
# ============================================================

echo "⚠ DEPRECATED: 调度已迁 systemd timer"
echo "  装: ./deploy/install-systemd.sh"
echo "  验证: systemctl --user list-timers nuankebao-*"
exit 1
