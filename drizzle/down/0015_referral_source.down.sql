-- down: 0015_referral_source (推荐关系来源区分 admin / self_signup)
-- 加性 migration (ADD COLUMN NOT NULL DEFAULT 'admin'); 回滚只丢"来源"信息
ALTER TABLE "referral_reward" DROP COLUMN IF EXISTS "source";
