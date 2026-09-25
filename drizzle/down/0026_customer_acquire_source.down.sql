-- 回滚 0026: 来源两列 (纯 additive, 回滚 = 去列去索引)
-- 注意: 期间录入的来源数据会丢失; 建议先导出 customer.acquire_source +
--   source_referrer_name 快照再回滚。
DROP INDEX IF EXISTS "idx_customer_acquire_source";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "source_referrer_name";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "acquire_source";