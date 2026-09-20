-- 回滚 0016: 客户跟进时间戳 (纯 additive, 回滚 = 去掉两列两索引)
-- ⚠ 回滚会丢「上次联系/上次到店」冗余值 —— 但这两列可从 interaction / wellness_record 重新回填,
--   回滚后跑 scripts/backfill-last-contact.ts 即可恢复 (scripts/backfill-last-contact.ts 正向用)
DROP INDEX IF EXISTS "idx_customer_last_interaction";
DROP INDEX IF EXISTS "idx_customer_last_visit";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "last_interaction_at";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "last_visit_at";
