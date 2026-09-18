-- ============================================
-- 0004_w5_rbac_store_id DOWN (反向操作)
-- 警告: DROP COLUMN / DROP TABLE 是破坏性操作 (CHARTER §3.5 红线).
--   生产跑前必须确认:
--     1. 旧版 APK 已下线 (避免 INSERT 缺列失败)
--     2. customer / user / franchisee / store_staff 没有依赖业务数据
--     3. RBAC 强制 store_id NOT NULL 之前 (本 migration 是 nullable, 安全)
-- 依据: CHARTER §3.5 红线
-- ============================================

-- index 先删 (依赖列)
DROP INDEX IF EXISTS "idx_user_default_store";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_user_franchisee";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_customer_store";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_store_staff_staff";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_store_staff_store";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_franchisee_deleted_at";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_franchisee_path";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_franchisee_referrer_side";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_franchisee_referrer";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_franchisee_phone_hash";--> statement-breakpoint

-- 列后删
ALTER TABLE "user" DROP COLUMN IF EXISTS "default_store_id";--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN IF EXISTS "franchisee_id";--> statement-breakpoint
ALTER TABLE "customer" DROP COLUMN IF EXISTS "store_id";--> statement-breakpoint

-- 表最后删 (依赖关系兜底)
DROP TABLE IF EXISTS "store_staff";--> statement-breakpoint
DROP TABLE IF EXISTS "franchisee";
