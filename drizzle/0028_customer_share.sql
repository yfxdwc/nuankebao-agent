-- ============================================
-- 0028 上级推送表: customer_share
-- Phase D 客户标识体系 (docs/customer-identity-system.md §6.5 / §8.4 + ADR-0019)
--
-- 主人 2026-09-25 拍 (ADR-0019 ✅ Accepted):
--   「下级的客户要在列表显示且与自己的区分; 上级的客户需上级推送才显示」(D4)
--   上级推送 = **归属人显式授权可见性** (不像 owner 直接归属, 这里只是授权我代为跟进)
--
-- 角色 (一致送/restate §6.5.4 字面):
--   from_user_id = 推送人 (拍下时**该客户的归属人快照**, 不是当时 viewer)
--   to_user_id   = 接收人 = 推送者所在枝的下层用户 (S2 跨枝防护)
--   推送 ≠ 转移归属 (S3): customer.owner_id 不变 → 推送不写 owner_id
--   接收人/推送人/当前 owner/admin 四方都能撤销 (S5)
--   同 (customer, to_user) 仅一条 active 推送 (S4, 部分唯一索引)
--   活跃 ≤5 / 每日接收 ≤100 (S6, D8 明文风险配套)
--   被推送人不能把收到的客户再推给她的下层 (S7)
--   推送双方任一停用 → 推送失效 (SHARE-4, 与 §3.4 (c) 的 EXISTS user active 对齐)
--
-- 纯 additive (ADR-0004 / CHARTER §3.5):
--   - 1 表 + 4 索引 (1 部分唯一) + 1 个外键关系; 不动现有列 / 不写 default / 不挂 deleted_at
--     (撤销走 revoked_at, 主文档 §3.4 E1 「不挂 deleted_at」 + §6.5.6 SHARE-4)
--   - 列可空: note / reason / revoked_at / revoked_by
--   - 老 APK 不受本表影响 (app INSERT 路径不写 customer_share)
--   - 挂审计触发器 customer_share_audit (SHARE-5, 照 audit_trigger.sql:41-44
--     franchisee_audit 模式) → 推送 / 撤销都进 audit_log
--     (触发器定义在 drizzle/audit_trigger.sql, 本文件不加 → 与既有过渡一致)
--
-- 与既有名空间: dev (DATABASE_URL=nuankebao) / test (DATABASE_URL=nuankebao_test)
-- 都会跑本 migration, 测试库被含 (migrate.ts 默认全库跑)
-- ============================================

-- 推送主表 (含 BIGSERIAL id, 不挂 deleted_at 走 revoked_at, 见主文档 §6.5.6)
CREATE TABLE IF NOT EXISTS "customer_share" (
  "id"            BIGSERIAL PRIMARY KEY,
  "customer_id"   BIGINT NOT NULL REFERENCES "customer"("id") ON DELETE CASCADE,
  -- 推送人 = 当时该客户的归属人 (S1, 拍下快照; 不是当时 viewer)
  "from_user_id"  BIGINT NOT NULL REFERENCES "user"("id"),
  -- 接收人 = 同枝下层 (S2, 同 root_id + placement_path 前缀, 不含自己)
  "to_user_id"    BIGINT NOT NULL REFERENCES "user"("id"),
  -- 推送说明 (≤ 200 字, zod refine 校验; 主文档 §6.5.4)
  "note"          TEXT,
  -- 撤销原因 (admin / 当前 owner 撤销时必填, 写审计; S5)
  "reason"        TEXT,
  "created_at"    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- 撤销时间 (NULL = 有效; 撤销即失效, 主文档 §6.5.6 SHARE-4)
  "revoked_at"    TIMESTAMPTZ,
  -- 撤销人 (S5 四方: 推送人 / 接收人 / 当前 owner / admin)
  "revoked_by"    BIGINT REFERENCES "user"("id")
);
--> statement-breakpoint

-- 索引 1: (to_user_id, revoked_at) 命中 §3.4 (c) 可见集 + R-10 即时过滤
CREATE INDEX IF NOT EXISTS "idx_customer_share_to_active"
  ON "customer_share" ("to_user_id", "revoked_at");
--> statement-breakpoint

-- 索引 2: (customer_id, revoked_at) 命中 §3.4 列表/详情外的「S6 同客户 ≤5」计数
CREATE INDEX IF NOT EXISTS "idx_customer_share_customer_active"
  ON "customer_share" ("customer_id", "revoked_at");
--> statement-breakpoint

-- 索引 3 (部分唯一, S4): 同一 (customer, to_user) 仅一条 active 推送 (revoked_at IS NULL)
--   撤销后 NULL 行允许再次推送 (幂等: ON CONFLICT → 409 ALREADY_SHARED)
CREATE UNIQUE INDEX IF NOT EXISTS "uniq_customer_share_active"
  ON "customer_share" ("customer_id", "to_user_id")
  WHERE "revoked_at" IS NULL;
--> statement-breakpoint

-- 索引 4: 仅供 S6「同客户 active 推送数计数」的 index-only scan
CREATE INDEX IF NOT EXISTS "idx_customer_share_customer_active_only"
  ON "customer_share" ("customer_id")
  WHERE "revoked_at" IS NULL;
--> statement-breakpoint

COMMENT ON COLUMN "customer_share"."customer_id" IS
  '被推送的客户档案 (S1 归属人才能推, 否则越权)';
COMMENT ON COLUMN "customer_share"."from_user_id" IS
  '推送人 (拍下时该客户归属人快照, 不随归属 transfer 改写; SHARE-6)';
COMMENT ON COLUMN "customer_share"."to_user_id" IS
  '接收人 (推送者所在枝下层用户, S2 同 root_id + placement_path 前缀 + 非自己; admin 豁免枝限制)';
COMMENT ON COLUMN "customer_share"."note" IS
  '推送说明 (≤ 200 字, zod refine 校验; 主文档 §6.5.4)';
COMMENT ON COLUMN "customer_share"."reason" IS
  '撤销原因 (admin / 当前 owner 撤销必填, 写审计; S5 接收人/推送人撤销可选)';
COMMENT ON COLUMN "customer_share"."created_at" IS
  '推送时间 (S4 幂等键之一)';
COMMENT ON COLUMN "customer_share"."revoked_at" IS
  '撤销时间 (NULL = 有效; 不挂 deleted_at, 主文档 §3.4 E1 注 + §6.5.6 SHARE-4)';
COMMENT ON COLUMN "customer_share"."revoked_by" IS
  '撤销人 (S5: 推送人 / 接收人 / 当前 owner / admin 四方)';
