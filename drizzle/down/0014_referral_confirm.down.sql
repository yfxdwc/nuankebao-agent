-- down: 0014_referral_confirm (推荐关系加"推荐人确认"时间戳)
-- 加性 migration (ADD COLUMN nullable); 回滚只丢确认时间, 不影响权益天数
ALTER TABLE "referral_reward" DROP COLUMN IF EXISTS "confirmed_at";
ALTER TABLE "referral_reward" DROP COLUMN IF EXISTS "rejected_at";
