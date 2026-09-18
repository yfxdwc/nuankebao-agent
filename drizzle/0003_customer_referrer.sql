-- ============================================
-- 0003_customer_referrer: 客户推荐人字段 (客户页图谱数据源)
-- 背景: 用户反馈客户页缺图谱视图, 选择「客户推荐人网络图」作为图谱形态之一
--   (图谱 = 加盟商树状组织图 + 客户推荐关系网络图, 一棵树多语义)
-- 依据: CHARTER §3.5 + ADR-0004
-- 兼容性:
--   - ADD COLUMN nullable bigint → ✅ 无 DEFAULT 也安全 (大表 ALTER 默认 NULL)
--   - CREATE INDEX 用 IF NOT EXISTS → ✅ Drizzle journal 拦截二次跑, 幂等仅 dev helper
--   - 不 DROP / 不 RENAME / 不 ALTER TYPE
-- 配套:
--   - drizzle/down/0003_customer_referrer.down.sql (反向操作, CHARTER §3.5 红线)
-- ============================================

ALTER TABLE "customer" ADD COLUMN "referrer_id" bigint;--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_customer_referrer" ON "customer" USING btree ("referrer_id");--> statement-breakpoint
