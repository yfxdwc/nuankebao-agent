-- ============================================
-- 0024 通用「可调参数组」覆盖层: app_config
--
-- 主人 2026-09-23 拍: 「在 admin 里增加管理、调节页面，让评分规则及其他客户管理中的
--   参数可在管理页面进行调节」
--
-- 用途: 一张表装所有"可调参数组"的覆盖值 (key = 'customer.insight' 等)。
--   只存 override, 默认值仍在代码里 → "重置为默认" = 删一行。
--
-- 纯 additive (ADR-0004): CREATE TABLE + CREATE INDEX, 无破坏性变更。
-- 不预置任何行: 没有行 = 全用代码默认值 (落地当天行为与改前**完全一致**)。
--
-- ⚠ 本文件是**手工写的**, 不经 `drizzle-kit generate`。
--   原因 (repo 现状, 2026-09-23 发现): drizzle 的 snapshot 只到 0016, 之后
--   0017-0023 都是手写迁移 → 直接跑 `drizzle-kit generate` 会把 0020-0023 的
--   变更**整段重放**一遍 (建表 + 重复 ALTER), 对已有库是灾难。
--   所以这里只做两件事: ① 写这个 .sql ② 在 drizzle/meta/_journal.json 追加一条
--   (migrate() 靠 journal 找文件, 没有 journal 条目这个文件不会被应用)。
-- ============================================

CREATE TABLE IF NOT EXISTS "app_config" (
  "key" TEXT PRIMARY KEY,
  "value" JSONB NOT NULL,
  "description" TEXT,
  "updated_by" BIGINT,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 按更新时间查"最近改过什么" (admin 页顶部的"最后修改"用)
CREATE INDEX IF NOT EXISTS "idx_app_config_updated_at"
  ON "app_config" ("updated_at" DESC);

COMMENT ON TABLE "app_config" IS
  '可调参数组覆盖层 (只存与代码默认值不同的部分); 改配置挂 audit 触发器留痕';
COMMENT ON COLUMN "app_config"."key" IS
  '逻辑键, 命名 <域>.<物>, 例: customer.insight';
COMMENT ON COLUMN "app_config"."value" IS
  '覆盖值 (jsonb, 不受信; 读取时经 resolve* 夹区间)';
COMMENT ON COLUMN "app_config"."updated_by" IS
  '最后修改人 user.id (追责以 audit_log 为准, 这里只图方便)';
