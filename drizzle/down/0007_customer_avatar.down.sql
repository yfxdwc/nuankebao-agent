-- ============================================
-- 0007_customer_avatar.down.sql
-- 反向操作: 移除客户头像字段
-- 依据: CHARTER §3.5 红线 (破坏性 migration 必带 down.sql)
-- 警告: 跑这条会丢失所有客户头像设置 (上传的图片文件本身还在 public/uploads)
--   - 仅用于回滚到 0007 之前的状态
--   - 生产跑前必先备份 PG (deploy/backup.sh)
-- ============================================

ALTER TABLE "customer" DROP COLUMN IF EXISTS "avatar";
