-- ============================================
-- 0025 idea 表回滚 (破坏性, 但主人拍板时回滚用)
-- 删触发器 → 删表 → 删 enum, 顺序反一下 up
-- ============================================

DROP TRIGGER IF EXISTS "idea_audit" ON "idea";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_idea_user_status";--> statement-breakpoint
DROP INDEX IF EXISTS "idx_idea_user_updated";--> statement-breakpoint
DROP TABLE IF EXISTS "idea";--> statement-breakpoint
DROP TYPE IF EXISTS "idea_status";