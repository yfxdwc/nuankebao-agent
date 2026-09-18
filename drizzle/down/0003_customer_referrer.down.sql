-- ============================================
-- 0003_customer_referrer.down.sql
-- 反向操作: 移除 referrer_id 字段 + 索引
-- 依据: CHARTER §3.5 红线 (破坏性 migration 必带 down.sql)
-- 警告: 跑这条会丢失所有客户的推荐人关系数据!
--   - 仅用于回滚到 0003 之前的状态
--   - 生产跑前必先备份 PG (deploy/backup.sh)
-- ============================================

DROP INDEX IF EXISTS "idx_customer_referrer";--> statement-breakpoint

ALTER TABLE "customer" DROP COLUMN IF EXISTS "referrer_id";
