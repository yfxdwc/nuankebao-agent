-- 0019 down: 撤掉拆栏 (只丢新列; referrer_id 全程没被本 migration 改过 → 无业务数据损失)
DROP INDEX IF EXISTS "idx_franchisee_placement_parent";
ALTER TABLE "franchisee" DROP COLUMN IF EXISTS "placement_parent_id";
