-- 回滚 0022: 落位单的"账号列" (纯 additive, 回滚 = 去列去索引)
-- 回滚后退回"按 new_phone_hash 找账号"的老路径 (功能不受影响, 只是又有了同号误判风险)
DROP INDEX IF EXISTS "idx_placement_new_user";
ALTER TABLE "franchise_placement_request" DROP COLUMN IF EXISTS "new_user_id";
