-- ============================================
-- 0027 落位单可选「直推者」: franchise_placement_request.referrer_fid
-- Phase B 客户标识体系 §6 (docs/customer-identity-system.md)
--
-- 主人 2026-09-25 拍 E1 (落位时可选直推者; 默认 = 发起人):
--   - 现 franchisee-placement.ts:1186 写死 referrerId = initiatorFid
--     → 落位后她的"推荐人" = 落位的发起人 (AGENTS §6.8 拆栏后 referrer 与 placement 父分家)
--   - 改成「发起人在落位时显式选直推者; 不传 → 默认 = 发起人」
--   - 候选 = 落位后她的**祖先链** = targetParentFid 本身 + 其上层直系 3 层
--     (与 getUplineAncestors(fid, 3) 同口径)
--
-- 边界 (硬约束, E2):
--   - 写入时校验: 显式选的 referrerFid 必须在候选链里 (否则 400)
--   - 搬树后 referrer 不在链上 → **不**级联改 referrer_id (保拆栏, AGENTS §6.8)
--     → audit-placement-integrity.ts 加例外报告 + 老节点白名单
--   - admin 强改上层 (adminReparentNode) **不动** referrer_id
--
-- 纯 additive (ADR-0004):
--   - 1 个 nullable 列 + 1 个索引, 不加 NOT NULL, 不加 DEFAULT
--     (老 APK / 老落位单不带此列 → INSERT 兼容, §5 M1)
--   - 不挂审计触发器 (与 0022 new_user_id 同口径: 结构列, 不写业务变更留痕)
--   - 不动其他列
-- ============================================

ALTER TABLE "franchise_placement_request"
  ADD COLUMN IF NOT EXISTS "referrer_fid" BIGINT;--> statement-breakpoint

CREATE INDEX IF NOT EXISTS "idx_placement_referrer_fid"
  ON "franchise_placement_request" USING btree ("referrer_fid");--> statement-breakpoint

COMMENT ON COLUMN "franchise_placement_request"."referrer_fid" IS
  '落位发起时显式选的直推者 (E1); NULL = 执行段回退到 initiatorFid (默认行为); 候选 = 落位后她的祖先链 (targetParentFid + 其上层直系 3 层, 与 getUplineAncestors 同口径); 写入时校验, 搬树后不在链上不级联改 (E2, 保 AGENTS §6.8 拆栏)';