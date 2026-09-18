-- down: 0008_rich_ink (沙龙模块 6 张表 + 6 个枚举)
--
-- 加性 migration 的逆运算 (CREATE TABLE / CREATE TYPE 的反向 DROP)。
-- ⚠ 跑之前想清楚: 回滚会**丢掉全部沙龙数据** (议程 / 邀请 / 带约 / 二级客人 / 动态 / 资料)。
--    生产上真要回滚, 先 pg_dump 这 6 张表。
--
-- 依据: CHARTER §3.5 + ADR-0004 (破坏性 migration 必带 down)

-- 先删子表, 再删主表 (无 FK, 顺序只为可读性)
DROP TABLE IF EXISTS "salon_activity";
DROP TABLE IF EXISTS "salon_attachment";
DROP TABLE IF EXISTS "salon_guest";
DROP TABLE IF EXISTS "salon_quota";
DROP TABLE IF EXISTS "salon_invitation";
DROP TABLE IF EXISTS "salon";

-- 枚举 (drizzle generate 时创建)
DROP TYPE IF EXISTS "salon_visibility";
DROP TYPE IF EXISTS "salon_activity_type";
DROP TYPE IF EXISTS "salon_guest_status";
DROP TYPE IF EXISTS "salon_invitation_status";
DROP TYPE IF EXISTS "salon_role";
DROP TYPE IF EXISTS "salon_status";
