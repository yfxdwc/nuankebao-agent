-- ============================================
-- 0018 向上认领: 支持「认领一个已在 app 里的节点当上级」
-- 主人 2026-09-21 拍: 「一个人已经在别的树里是节点, 可以被认领为我的上级,
--   前提是这个人的一层 2 个点位必需有空位」
--
-- 纯 additive: 加 1 列 + 1 索引 (向后兼容 ADR-0004)
--   upline_fid = 认领的上级**已存在**的节点 id (复用该节点, 不新建副本)
--   null       = 上级不在 app 里 → 执行 promote 时才新建他的节点
-- 语义: promote 的两棵子树在此**合并** (同一加盟系统上不同枝 → 上溯到共同上层)
-- ============================================

ALTER TABLE "franchise_placement_request" ADD COLUMN IF NOT EXISTS "upline_fid" BIGINT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_placement_upline_fid" ON "franchise_placement_request" USING btree ("upline_fid");
