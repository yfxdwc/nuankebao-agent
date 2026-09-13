#!/usr/bin/env bash
# ============================================================
# ⚠ DEPRECATED 2026-09-08 — 已迁移到 deploy/restore_verify.sh
#
# 老版是覆盖式恢复 (DROP SCHEMA + pg_restore), 危险.
# 新版 deploy/restore_verify.sh 是隔离演练 (起临时 PG:5435 + 行数比对), 不覆盖生产.
#
# 真实灾难恢复 (覆盖生产):
#   1. 手动: 解密 + pg_restore 到生产 (参考历史逻辑, 但手动跑)
#   2. 验证: 跑 deploy/restore_verify.sh 确认备份链路通
#
# 本脚本保留供历史. 自动转月度演练.
# 详见 deploy/README.md §10.5 + ~/.muse/skills/dev-domain-backup/SKILL.md
# ============================================================

echo "⚠ DEPRECATED: 转到 deploy/restore_verify.sh (隔离演练, 不覆盖生产)"
echo "  如真要覆盖生产恢复, 请主人手动决策 (本脚本不再自动执行 DROP SCHEMA)"
exit 1