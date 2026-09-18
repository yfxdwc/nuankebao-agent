-- ============================================
-- 0004_w5_rbac_store_id: W5 RBAC 行级过滤所需 schema 漂移补齐
-- 背景: W5 RBAC 改造加了 customer/store_staff/franchisee/user 多处列,
--   schema.ts 已声明, 但 migration 漏出, dev 机 PG 缺列导致 API 500
-- 范围:
--   - 新建 franchisee 表 (加盟关系, CHARTER §4.3)
--   - 新建 store_staff 表 (店员-门店多对多, RBAC 关键)
--   - customer 新增 store_id (行级过滤, CHARTER §3.6)
--   - user 新增 franchisee_id / default_store_id (登录态定位)
-- 依据: CHARTER §3.5 + ADR-0004
-- 兼容性 (本迁移):
--   - CREATE TABLE IF NOT EXISTS → 幂等
--   - ADD COLUMN nullable bigint → ✅ 无 DEFAULT, 大表 ALTER 默认 NULL
--   - CREATE INDEX IF NOT EXISTS → 幂等
--   - 不 DROP / 不 RENAME / 不 ALTER TYPE
-- 删去的 (已存在于前序 migration):
--   - ALTER TABLE customer ADD COLUMN referrer_id    (0003_customer_referrer 已加)
--   - CREATE INDEX idx_customer_referrer             (0003_customer_referrer 已建)
-- 配套: drizzle/down/0004_w5_rbac_store_id.down.sql (CHARTER §3.5 红线)
-- ============================================

CREATE TABLE IF NOT EXISTS "franchisee" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"phone_encrypted" text NOT NULL,
	"phone_hash" text NOT NULL,
	"referrer_id" bigint,
	"placement_side" text,
	"placement_path" text DEFAULT '' NOT NULL,
	"placement_depth" integer DEFAULT 0 NOT NULL,
	"joined_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"notes_encrypted" text,
	"created_by" bigint NOT NULL,
	"created_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "store_staff" (
	"store_id" bigint NOT NULL,
	"staff_id" bigint NOT NULL,
	"is_manager" boolean DEFAULT false NOT NULL,
	"joined_at" timestamp with time zone DEFAULT NOW() NOT NULL,
	CONSTRAINT "store_staff_store_id_staff_id_pk" PRIMARY KEY("store_id","staff_id")
);
--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN "store_id" bigint;--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "franchisee_id" bigint;--> statement-breakpoint
ALTER TABLE "user" ADD COLUMN "default_store_id" bigint;--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_franchisee_phone_hash" ON "franchisee" USING btree ("phone_hash");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_referrer" ON "franchisee" USING btree ("referrer_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_referrer_side" ON "franchisee" USING btree ("referrer_id","placement_side");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_path" ON "franchisee" USING btree ("placement_path");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_deleted_at" ON "franchisee" USING btree ("deleted_at");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_store_staff_store" ON "store_staff" USING btree ("store_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_store_staff_staff" ON "store_staff" USING btree ("staff_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_store" ON "customer" USING btree ("store_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_user_franchisee" ON "user" USING btree ("franchisee_id");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_user_default_store" ON "user" USING btree ("default_store_id");
