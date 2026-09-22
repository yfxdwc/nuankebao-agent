-- 回滚 0020: 归属列 (纯 additive, 回滚 = 去列去索引)
-- created_by 全程没被本 migration 改过 → 无业务数据损失。
-- ⚠ 回滚后「我的客户」退回 created_by 口径 (含"建号即自动归属推荐人"的老语义);
--    期间用显式添加 (claim) 产生的归属信息会丢失 —— 建议先导出 owner_id 快照再回滚。
DROP INDEX IF EXISTS "idx_customer_owner";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "owner_id";
