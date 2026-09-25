-- ============================================
-- down: 0029_customer_list_indexes (R-9 索引补齐)
--
-- 加性 migration 的逆运算 (CREATE INDEX 的反向 DROP INDEX)。
-- ⚠️ 回滚后 sort='new' / sort='name' / 「我的客户 + 最近联系」查询
--    会**退化为全表 scan + sort**, 大表场景性能下降 (回到 0029 之前)。
--    生产上真要回滚, 先看 EXPLAIN ANALYZE。
-- ============================================

DROP INDEX IF EXISTS "idx_customer_created_at_desc";
DROP INDEX IF EXISTS "idx_customer_name";
DROP INDEX IF EXISTS "idx_customer_owner_last_interaction";