-- down: 0028_customer_share (上级推送表)
--
-- 加性 migration 的逆运算 (CREATE TABLE 的反向 DROP)。
-- ⚠ 跑之前想清楚: 回滚会**丢掉全部推送记录** (推送关系 + 撤销时间)。
--    生产上真要回滚, 先 pg_dump customer_share。
--
-- ⚠ 审计触发器 customer_share_audit 在 drizzle/audit_trigger.sql 里挂,
--    回滚时 DROP TABLE IF EXISTS 会**连带把触发器**丢掉; 但 audit_log
--    表里的历史行**不会**自动清掉, 主人需要时可单独清理。
--    (这与既有过渡: salon / franchisee / idea 表的 down.sql 同口径)

DROP TABLE IF EXISTS "customer_share";
