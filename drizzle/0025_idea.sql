-- ============================================
-- 0025 主人待开发想法 / 备忘录: idea
--
-- 主人 2026-09-23 拍 (ask_user d3e7f2a1 第二轮, 跟原"开发计划模块"补充):
--   「我需要能手动记录一个待开发的想法, 有些备忘的意思, 可以增删改,
--    完成后勾选完成, 或丢弃」
--
-- 跟 0024 / 0023 的区别: 这是一张**纯 admin 自用**的表 (主人的个人备忘录),
--   不是跨业务域的覆盖层 (app_config) / 行为数据 (usage_event)。三件事各管各:
--     - app_config (0024) = 全店可调参数覆盖层
--     - usage_event (0023) = 真实用户使用行为日志
--     - idea (0025)      = 主人自己的待办 / 备忘
--
-- 设计:
--   1. status 三态: open / done / discarded
--      - open       待办 (主人初始状态, 默认)
--      - done       完成 (填 completed_at)
--      - discarded  丢弃 (主人决定不做了, 软丢 = 状态切换, 保留 audit 留痕)
--      - 任何状态都能再变回 open (清 completed_at)
--   2. description 可空 (主人说"有些备忘的意思" → 一句话标题足够时不要 description 强填)
--      → schema 用 DEFAULT '' (NOT NULL), 不 nullable 但允许空字符串 (前端更省事)
--   3. 不加密 (主人自己的备忘录, 跟 chat log / docs/ 同口径; 真要含商业敏感信息请
--      主人自行评估 —— 字段是 free text)
--   4. 列入 audit_log (跟其他表一致, 主人想看"什么时候改了哪个想法的标题"能查)
--   5. 不做 soft delete: 「丢弃」用 status='discarded' 表达 (软丢),
--      「真删」走 DELETE /api/ideas/[id] (留 audit 行)
--
-- 纯 additive (ADR-0004): CREATE TYPE + CREATE TABLE + CREATE INDEX, 无破坏性变更。
-- 不预置任何行: 没有行 = 主人"还没记过想法"。
--
-- ⚠ 本文件是**手工写的**, 不经 `drizzle-kit generate` (跟 0024 同根原因,
--   仓里 snapshot 落后于实际 schema, generate 会重放老 migration)。
--   migrate.ts 走 drizzle/migrator 自动应用 (按 meta/_journal.json 找文件)。
-- ============================================

CREATE TYPE "idea_status" AS ENUM ('open', 'done', 'discarded');--> statement-breakpoint

CREATE TABLE IF NOT EXISTS "idea" (
  "id" BIGSERIAL PRIMARY KEY,
  "user_id" BIGINT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL DEFAULT '',
  "status" "idea_status" NOT NULL DEFAULT 'open',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "completed_at" TIMESTAMPTZ
);--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_idea_user_status"
  ON "idea" ("user_id", "status", "updated_at" DESC);--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_idea_user_updated"
  ON "idea" ("user_id", "updated_at" DESC);--> statement-breakpoint

COMMENT ON TABLE "idea" IS
  '主人待开发想法 / 备忘录 (开发计划页 CRUD 后端; v0.1.5)';
COMMENT ON COLUMN "idea"."user_id" IS
  '想法归属人 user.id (现阶段仅 admin 自用; 列存留以备多人协作)';
COMMENT ON COLUMN "idea"."title" IS
  '一句话标题 (主人说"有些备忘的意思", 主要信息)';
COMMENT ON COLUMN "idea"."description" IS
  '详细描述 (可空字符串; 不强求填)';
COMMENT ON COLUMN "idea"."status" IS
  'open=待办 / done=已完成 / discarded=已丢弃';
COMMENT ON COLUMN "idea"."completed_at" IS
  'status=open → done 时填; 任何转 open 清空; 不存 done→discarded 的时刻 (那一刻等于丢弃)';