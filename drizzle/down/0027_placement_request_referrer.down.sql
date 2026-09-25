-- ============================================
-- 0027 回滚: 落位单 referrer_fid 列 + 索引 (纯 additive, 回滚 = 去列去索引)
-- 注意: 期间录入的 referrer_fid 数据会丢失 (落位执行段的默认值会回退到发起人)
-- ============================================

DROP INDEX IF EXISTS "idx_placement_referrer_fid";
ALTER TABLE "franchise_placement_request" DROP COLUMN IF EXISTS "referrer_fid";