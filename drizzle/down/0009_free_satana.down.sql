-- down: 0009_free_satana (wellness_knowledge.category 索引: 普通 → 恢复 UNIQUE)
--
-- ⚠ 恢复 UNIQUE 前必须确保同 category 没有重复行, 否则会失败:
--   SELECT category, count(*) FROM wellness_knowledge GROUP BY 1 HAVING count(*) > 1;
-- 本 migration 只改索引, 不动数据。

DROP INDEX IF EXISTS "idx_knowledge_category";
CREATE UNIQUE INDEX IF NOT EXISTS "idx_knowledge_category" ON "wellness_knowledge" USING btree ("category");
