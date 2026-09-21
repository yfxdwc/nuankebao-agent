-- 回滚 0017: 多根 root_id + 预占索引收紧
-- ⚠ 回滚会丢 root_id (纯冗余列, 可从 referrer_id 链重算 → 重跑 up 的 CTE 即可恢复)
--   预占索引恢复成"不筛 kind"的旧口径 (unjoin 也会占用 slot, 见 0010)
DROP INDEX IF EXISTS "idx_placement_pending_slot";
CREATE UNIQUE INDEX IF NOT EXISTS "idx_placement_pending_slot"
  ON "franchise_placement_request" USING btree ("target_parent_fid", "target_side")
  WHERE status = 'pending';
DROP INDEX IF EXISTS "idx_franchisee_root";
ALTER TABLE "franchisee" DROP COLUMN IF EXISTS "root_id";
