-- down: 0007_user_avatar_url
-- 加性 migration 的回滚 (ADD COLUMN 的逆运算)。
-- ⚠ 跑之前想清楚: 回滚会**丢掉所有人已选的头像** (数据在列里)。
ALTER TABLE "user" DROP COLUMN IF EXISTS "avatar_url";
