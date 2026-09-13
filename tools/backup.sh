#!/usr/bin/env bash
# ============================================================
# ⚠ DEPRECATED 2026-09-08 — 已迁移到 deploy/backup.sh (dev-domain-backup SOP §3.1)
#
# 新版脚本:
#   - 工业级: PG + Media + GPG + 异地 + GFS 双保险 + atomic JSON health state
#   - GPG 密钥文件 (passphrase-file) 取代 BACKUP_PASSPHRASE env (SOP §2.2 红线)
#   - 调度改 systemd timer (Persistent + RandomizedDelay) 取代 cron
#   - 月度演练脚本 deploy/restore_verify.sh (隔离演练, 不覆盖生产)
#
# 本脚本保留供历史. 调用时自动转新版.
# 详见 deploy/README.md §10 + ~/.muse/skills/dev-domain-backup/SKILL.md
# ============================================================

# 自动推导 deploy/backup.sh 路径 (不依赖项目根位置, AGENTS §6.3)
exec "$(cd "$(dirname "$0")/.." && pwd)/deploy/backup.sh" "$@"