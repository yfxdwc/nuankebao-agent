-- 0011_user_credentials down: 回滚账号密码字段
-- 注意: 回滚会丢失所有密码哈希 (用户将无法登录, 需重新建档)
DROP INDEX IF EXISTS "idx_user_username";
ALTER TABLE "user" DROP COLUMN IF EXISTS "password_hash";
ALTER TABLE "user" DROP COLUMN IF EXISTS "username";
