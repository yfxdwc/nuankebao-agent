-- ============================================
-- 0006_customer_birthday_allergy.down.sql
-- 反向操作: 移除生日细化字段 + 过敏史
-- 依据: CHARTER §3.5 红线 (破坏性 migration 必带 down.sql)
-- 警告: 跑这条会丢失「月/日 + 农历标记 + 生日提醒设置 + 过敏史」全部数据!
--   - 仅用于回滚到 0006 之前的状态
--   - 生产跑前必先备份 PG (deploy/backup.sh)
--   - birth_year 不受影响 (老字段)
-- ============================================

ALTER TABLE "customer" DROP COLUMN IF EXISTS "birth_month";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "birth_day";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "birth_calendar";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "birthday_remind_days";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "allergy_history_encrypted";
