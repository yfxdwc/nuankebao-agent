-- ============================================
-- 0019 拆栏: 「推荐人」与「点位父」分家 (placement_parent_id)
-- 主人 2026-09-21 拍: 「拆 —— 加一栏 placement_parent_id 专门记"上层点位", 推荐人那栏从此只记推荐人」
--
-- 为什么要拆 (两栏原先共用 referrer_id 一栏):
--   ① 管理员「协商处理后强改上层」为了不让新上层那条线"看着空、其实有人", 只能连带改
--      referrer_id → **改上层会篡改"谁推荐了她"** (业务关系被结构改动污染)
--   ② placeNewFranchisee 的"这个位置有没有人"按 referrer_id 判 → 「推荐人 ≠ 点位父」的节点
--      (三方确认落位时 发起人≠落位父 就会这样) 被判成空位 → 生成两条相同 placement_path
--
-- 纯 additive: 加 1 列 + 1 索引 + 回填 (向后兼容 ADR-0004)
--   语义: placement_parent_id = 点位父 (她的"上层点位")
--         referrer_id         = 推荐人 (谁把她拉进来的) —— 本 migration **不动**它
--   根节点: placement_parent_id = NULL (没有上层)
-- ============================================

ALTER TABLE "franchisee" ADD COLUMN IF NOT EXISTS "placement_parent_id" BIGINT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_franchisee_placement_parent" ON "franchisee" USING btree ("placement_parent_id");--> statement-breakpoint

-- 回填 主口径: 点位父 = placement_path 去尾段 + 同 root_id 的那个节点
--   (与 getPlacementUpline / admin-users 图谱 同一口径; path 段固定 2 字符)
UPDATE franchisee f
SET placement_parent_id = p.id
FROM franchisee p
WHERE f.placement_parent_id IS NULL
  AND f.deleted_at IS NULL
  AND f.placement_path <> ''
  AND p.root_id = f.root_id
  AND p.placement_path = CASE
        WHEN length(f.placement_path) <= 2 THEN ''
        ELSE left(f.placement_path, length(f.placement_path) - 2)
      END
  AND p.id <> f.id
  AND p.deleted_at IS NULL;--> statement-breakpoint

-- 回填 兜底: path 断链 (父节点已软删 / 脏数据) 的少数行 → 沿用 referrer_id
--   有总比 NULL 好: 点位算法按本列导航, NULL 会让这棵子树"看不见"
UPDATE franchisee f
SET placement_parent_id = f.referrer_id
FROM franchisee p
WHERE f.placement_parent_id IS NULL
  AND f.deleted_at IS NULL
  AND f.placement_path <> ''
  AND f.referrer_id IS NOT NULL
  AND p.id = f.referrer_id
  AND p.deleted_at IS NULL;--> statement-breakpoint

-- 回填完后自检 (断了就 abort 整个 migration, 不许半吊子上线):
--   非根节点必须有点位父 —— 没有 = 上面两条都没兜住, 需要人工看
DO $$
DECLARE orphan_count INTEGER;
BEGIN
  SELECT count(*) INTO orphan_count
  FROM franchisee
  WHERE deleted_at IS NULL AND placement_path <> '' AND placement_parent_id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION '0019 回填失败: 还有 % 个非根节点没有点位父, 需人工处理', orphan_count;
  END IF;
END $$;
