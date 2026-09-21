-- ============================================
-- 0017 多根支持 (root_id) + 向上认领 (kind=promote)
-- 主人 2026-09-21 拍: 「要支持多根」+「原有往下生长的三方确认不变, 需增加往根部发展的方案」
-- 前身: docs/backlog.md ⑤ (多根时 placement_path 跨根串味)
--
-- 三件事 (全 additive / 向后兼容 ADR-0004):
--   1. franchisee.root_id 新列 (值 = 所在树的根 franchisee.id; 根自己 = 自己)
--   2. 老数据回填 root_id (沿 referrer_id 往上爬到顶层祖先)
--   3. 预占唯一索引收紧到 kind='create'
--      (unjoin 不占新位; promote 的 target_parent_fid 是"锚点"而非空位, 不该占锚点子位)
--
-- 注: franchisee 表**没有**审计触发器 → 本 migration 的 UPDATE 不进 audit_log
--     (root_id 是结构列, 不是业务数据; 留痕靠本文件 + CHANGELOG)
-- ============================================

ALTER TABLE "franchisee" ADD COLUMN IF NOT EXISTS "root_id" BIGINT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_root" ON "franchisee" USING btree ("root_id");--> statement-breakpoint

-- 回填: 每个节点爬到"没有上级"的最高祖先 = 它所在树的根
--   recursive: 起点 = 所有 root_id 为空的节点, 每次沿 referrer_id 上跳一层
--   steps 用来在 DISTINCT ON 时取"跳到最后"的那一行 (= 顶层祖先)
--   p.deleted_at IS NULL: 不爬进已软删的父节点 (否则 root_id 指向一个已删节点)
WITH RECURSIVE climb AS (
  SELECT f.id AS node_id, f.id AS cur_id, f.referrer_id AS parent_id, 0 AS steps
  FROM franchisee f
  WHERE f.root_id IS NULL
  UNION ALL
  SELECT c.node_id, p.id, p.referrer_id, c.steps + 1
  FROM climb c
  JOIN franchisee p ON p.id = c.parent_id AND p.deleted_at IS NULL
)
UPDATE franchisee f
SET root_id = t.cur_id
FROM (
  SELECT DISTINCT ON (node_id) node_id, cur_id
  FROM climb
  ORDER BY node_id, steps DESC
) t
WHERE f.id = t.node_id AND f.root_id IS NULL;--> statement-breakpoint

DROP INDEX IF EXISTS "idx_placement_pending_slot";--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_placement_pending_slot"
  ON "franchise_placement_request" USING btree ("target_parent_fid", "target_side")
  WHERE status = 'pending' AND kind = 'create';
