-- 回滚 0018: 向上认领的上级节点列 (纯 additive, 回滚 = 去列去索引)
-- ⚠ 回滚会丢"认领的是哪个已有节点" → 相关 pending 认领单将退化成"新建上级"语义, 建议先 cancel 掉 pending 单
DROP INDEX IF EXISTS "idx_placement_upline_fid";
ALTER TABLE "franchise_placement_request" DROP COLUMN IF EXISTS "upline_fid";
