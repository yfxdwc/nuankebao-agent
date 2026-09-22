-- 回滚 0021: 去掉账号↔档案的列连接 (纯 additive, 回滚 = 去列去索引)
-- 回滚后退回 phone_hash 约定口径 (功能不受影响, 只是少了一条可查的列)
DROP INDEX IF EXISTS "idx_user_customer";
ALTER TABLE "user" DROP COLUMN IF EXISTS "customer_id";
