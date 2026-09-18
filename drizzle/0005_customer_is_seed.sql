-- ============================================
-- 0005_customer_is_seed: 客户「种子」标记 (客户列表筛选: 全部/加盟/普通/种子)
-- 背景: 主人 2026-09-18 拍「客户列表胶囊筛选接真过滤」, 类型判定 = 混合方案 (C):
--   - 加盟 franchisee: 派生 (franchisee 表存在同 phone_hash 记录, 不存字段)
--   - 种子 seed:       显式勾选 (本字段, 潜在客户开关)
--   - 普通 normal:     其余 (默认值, 不存字段)
--   优先级: 加盟 > 种子 > 普通 (queries/customer.ts resolveCustomerType)
-- 依据: CHARTER §3.5 + ADR-0004
-- 兼容性 (红线自检):
--   - ADD COLUMN boolean NOT NULL DEFAULT false → ✅ 老 APK INSERT 不带该列也能跑 (走 DEFAULT)
--   - 不 DROP / 不 RENAME / 不 ALTER TYPE / 无 SET NOT NULL 无 DEFAULT
--   - 存量行自动回填 false (= 不是种子, 跟改动前行为一致)
-- 配套:
--   - drizzle/down/0005_customer_is_seed.down.sql (反向操作, CHARTER §3.5 红线)
-- ============================================

ALTER TABLE "customer" ADD COLUMN "is_seed" boolean DEFAULT false NOT NULL;--> statement-breakpoint
