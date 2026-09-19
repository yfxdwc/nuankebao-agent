-- down: 0012_membership_billing (S0 会员骨架 + 推荐码)
-- ⚠ 破坏性: 会删掉会员状态 / 权益发放流水 / 推荐关系。
--   回滚前先导出这几张表 (付费功能上线后, 这些是**账与权益的唯一记录**)。
DROP TABLE IF EXISTS "referral_reward";
DROP TABLE IF EXISTS "referral_code";
DROP TABLE IF EXISTS "entitlement_grant";
DROP TABLE IF EXISTS "membership";
DROP TABLE IF EXISTS "plan";
