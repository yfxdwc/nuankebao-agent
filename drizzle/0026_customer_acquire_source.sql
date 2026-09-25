-- ============================================
-- 0026 客户来源列: customer.acquire_source + customer.source_referrer_name
-- (Phase A 客户标识体系; docs/customer-identity-system.md §5)
--
-- 主人 2026-09-25 拍 D5 + D6 + D7:
--   - 来源选填 (转介绍 referral 时介绍人 source_referrer_name 必填)
--   - 命名 acquire_source (规避与 referral_reward.source 同名混淆, §5 M2)
--   - key: friend / referral / cold_visit / ground_promo; NULL = 未填写
--   - 客户端列表/详情**不**显示来源 (D6); 仅 Flutter + Web admin 详情管理区显示
--
-- 纯 additive (ADR-0004 / CHARTER §3.5):
--   · 两列都 nullable, 不加 NOT NULL, 不加 DEFAULT (老 APK INSERT 不带此列也能跑, §5 M1)
--   · 转介绍介绍人必填走应用层 zod refine (§5 M3); 不加 DB CHECK
--   · 加索引 idx_customer_acquire_source (低基数, 加速"按来源筛选")
-- ============================================

ALTER TABLE "customer" ADD COLUMN IF NOT EXISTS "acquire_source" TEXT;--> statement-breakpoint
ALTER TABLE "customer" ADD COLUMN IF NOT EXISTS "source_referrer_name" TEXT;--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "idx_customer_acquire_source"
  ON "customer" ("acquire_source");--> statement-breakpoint

COMMENT ON COLUMN "customer"."acquire_source" IS
  '客户来源: friend(亲友) / referral(转介绍) / cold_visit(陌生拜访) / ground_promo(地推); NULL=未填写 (Phase A §5 M2 命名; 应用层 zod 校验 enum)';
COMMENT ON COLUMN "customer"."source_referrer_name" IS
  '转介绍介绍人姓名 (仅 acquire_source = referral 时应用层 zod refine 必填; ≤ 50 字)';