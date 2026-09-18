-- ============================================
-- 0005_customer_is_seed.down.sql
-- 反向操作: 移除客户「种子」标记字段
-- 依据: CHARTER §3.5 红线 (破坏性 migration 必带 down.sql)
-- 警告: 跑这条会丢失所有「种子客户」标记!
--   - 仅用于回滚到 0005 之前的状态
--   - 生产跑前必先备份 PG (deploy/backup.sh)
--   - 不影响「加盟」判定 (那是 franchisee 表派生, 无字段)
-- ============================================

ALTER TABLE "customer" DROP COLUMN IF EXISTS "is_seed";
