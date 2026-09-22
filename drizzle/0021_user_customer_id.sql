-- ============================================
-- 0021 账号 ↔ 客户档案 的列连接: user.customer_id (ADR-0015 Q7)
-- 主人 2026-09-22 拍「全按建议」: 第一步 additive —— 加可空列 + 唯一索引 + 回填
--
-- 为什么需要:
--   `user` ↔ `customer` 之间**没有任何列连接**, 只靠 `phone_hash` 相等这个"约定"互认
--   (AGENTS §6.6)。后果 (三次改动都被它卡住):
--     ① 改手机号要两处同步, 漏一处 → 账号和档案散架, 谁也查不出来
--     ② 「自己不应该是自己的客户」只能现算 EXISTS(phone_hash 相等)
--     ③ 建号 / 补档 / 复用既有档案 三条路各自维护"档案是谁的", 无列可校
--
-- 语义: user.customer_id = **这个账号对应的客户档案** (她作为"别人的客户"那一面)
--   - admin 豁免建档 (Q5) → 可空 (prod admin 现状就是没有档案)
--   - 唯一索引: 一条档案最多被一个账号认领 (user.phone_hash 本身唯一 → 天然一对一)
--
-- 纯 additive (兼容 ADR-0004): 加 1 列 + 1 唯一索引 + 回填; 列可空, 老 APK INSERT 不带也不炸
-- ⚠ user 表挂了 user_audit 触发器 → 下面的回填 UPDATE 会写 audit_log
--   (user_id = NULL = "系统回填", 不是用户操作; 留痕比静默好)
-- ============================================

ALTER TABLE "user" ADD COLUMN IF NOT EXISTS "customer_id" BIGINT;--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "idx_user_customer" ON "user" USING btree ("customer_id");--> statement-breakpoint

-- 回填: 按手机号 hash 找同人档案 (未软删); 没有档案的账号保持 NULL (admin / 待补档)
UPDATE "user" u
SET customer_id = c.id
FROM customer c
WHERE u.customer_id IS NULL
  AND c.deleted_at IS NULL
  AND c.phone_hash = u.phone_hash;--> statement-breakpoint

-- 自检: 有档案却没回填上 = 回填逻辑坏了 → abort (剩下"本来就没档案"的账号只发 NOTICE)
DO $$
DECLARE missed INTEGER; no_profile INTEGER;
BEGIN
  SELECT count(*) INTO missed
  FROM "user" u
  JOIN customer c ON c.phone_hash = u.phone_hash AND c.deleted_at IS NULL
  WHERE u.customer_id IS NULL;
  IF missed > 0 THEN
    RAISE EXCEPTION '0021 回填失败: % 个账号有客户档案但 customer_id 仍为空', missed;
  END IF;

  SELECT count(*) INTO no_profile
  FROM "user" u
  WHERE u.customer_id IS NULL AND u.role <> 'admin';
  RAISE NOTICE '0021: % 个非 admin 账号暂无客户档案 (存量待补, 见 scripts/audit-subject-integrity.ts)', no_profile;
END $$;
