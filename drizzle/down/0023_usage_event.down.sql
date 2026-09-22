-- 回滚 0023: 去 usage_event (纯新增表, 回滚 = 删表)
-- ⚠️ 删表会丢使用数据: 这是唯一副本 (无 FK 依赖方 / 不挂审计触发器)
DROP TABLE IF EXISTS "usage_event";
