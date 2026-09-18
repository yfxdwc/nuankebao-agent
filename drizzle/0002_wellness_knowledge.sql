-- ============================================
-- 0002_wellness_knowledge: 养生知识库 (RAG 数据源)
-- W9 Phase 2 AI 增强
-- ============================================
-- 依据: CHARTER §3.5 + ADR-0004
-- 本 migration 为加性 (CREATE TABLE + CREATE INDEX), 不需要 down.sql
-- 不使用 Drizzle 生成的 DROP IF EXISTS 幂等 pattern (避免 CHARTER §3.5 警告):
--   - 本文件只跑 1 次 (Drizzle journal tracking)
--   - CREATE TABLE / CREATE INDEX 已用 IF NOT EXISTS 幂等
--   - CREATE TYPE 不支持 IF NOT EXISTS, 但重复跑场景不存在 (journal 拦截)

CREATE TYPE "public"."knowledge_category" AS ENUM(
  'physiotherapy',
  'wellness_tip',
  'product_guide',
  'customer_care',
  'seasonal'
);--> statement-breakpoint

CREATE TABLE IF NOT EXISTS "wellness_knowledge" (
  "id" bigserial PRIMARY KEY NOT NULL,
  "title" text NOT NULL,
  "content" text NOT NULL,
  "category" "knowledge_category" NOT NULL,
  "tags" jsonb DEFAULT '[]'::jsonb,
  "created_by" bigint,
  "created_at" timestamp with time zone DEFAULT NOW() NOT NULL
);--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_knowledge_category" ON "wellness_knowledge" USING btree ("category");