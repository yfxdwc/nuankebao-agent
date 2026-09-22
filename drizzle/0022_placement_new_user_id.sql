-- ============================================
-- 0022 落位单记住"是哪个账号": franchise_placement_request.new_user_id
-- ADR-0016 D1/P6 (主人 2026-09-22 拍):
--   「手机号不作为用户识别内容, 用户的唯一识别码是邀请码」
--   「落位/建节点改成按邀请码找账号」
--
-- 为什么加这一列:
--   落位单原先只存 new_phone_hash —— 执行时按手机号找账号、确认时按手机号认"本人"。
--   手机号既可能换也可能同号 → 认错人。现在请求创建时就按**邀请码**解析出账号,
--   把 user id 记在单子上: 执行按 id 校验、本人确认按 id 认人。
--
-- 纯 additive (ADR-0004): 加 1 列 + 1 索引 + 回填 (存量单按 new_phone_hash 找到就填)
--   ⚠ franchise_placement_request 无审计触发器 → 回填不进 audit_log (结构列, 留痕靠本文件)
-- ============================================

ALTER TABLE "franchise_placement_request" ADD COLUMN IF NOT EXISTS "new_user_id" BIGINT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_placement_new_user" ON "franchise_placement_request" USING btree ("new_user_id");--> statement-breakpoint

-- 回填: 存量单按手机号 hash 找账号 (找不到 = 当时那个号还没账号 → 保持 NULL, 执行时按老路径报错)
UPDATE franchise_placement_request r
SET new_user_id = u.id
FROM "user" u
WHERE r.new_user_id IS NULL
  AND r.new_phone_hash IS NOT NULL
  AND u.phone_hash = r.new_phone_hash;--> statement-breakpoint

-- 自检: pending 单里"有手机号 hash 却没有 new_user_id"的数量 → 只提示 (它们在执行时本来就会报错)
DO $$
DECLARE unresolved INTEGER;
BEGIN
  SELECT count(*) INTO unresolved
  FROM franchise_placement_request
  WHERE status = 'pending' AND new_phone_hash IS NOT NULL AND new_user_id IS NULL;
  RAISE NOTICE '0022: % 张 pending 落位单没解析到账号 (存量单, 执行时按老路径处理)', unresolved;
END $$;
