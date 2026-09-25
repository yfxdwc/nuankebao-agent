// ============================================
// 客户标识体系 (Phase A, 主人 2026-09-25 拍)
// ============================================
// 文档: docs/customer-identity-system.md §3
// 落地: 客户/详情/列表/表单四屏用同一套标识口径
//
// 维度映射 (一表概览, 详细见 §1 表):
//   affiliation = 加盟·直推 / 加盟·非直推 / 未加盟 (维度 1+2 合并)
//   ownership   = 我的客户 / 下级的客户 / 上级的客户 / 他人客户 / 无归属 (维度 5)
//   member      = 会员 / 免费 (维度 3, 走 member-flag.ts)
//   registered  = 已注册 / 未注册 (维度 4, 走 hasAccountSql)
//   source      = 来源 + 转介绍介绍人 (维度 6, 走新列 acquire_source + source_referrer_name)
//
// 不变量 (与文档 §3.3 / §9.1 一一对应):
//   B1 (INV-4): 加盟判定必加 franchisee.deleted_at IS NULL
//   B2 (INV-3): viewer 无加盟节点 → affiliation = none; ownership ∈ {none, mine}; 禁止 null
//   B3 (INV-2): "直推" 一词只能来自 referrer_id 口径 (§2.1 supersede)
//   B4 (INV-5): ownership ≠ mine 时手机号走 maskPhone (D8 例外 upline_shared → 明文,
//                但本函数不做手机号 mask, 由调用方 toView 决定, 见 docs §3.4)
//   E1: 所有 identity SQL 必加 customer.deleted_at IS NULL
//
// 边界 (Phase A 现状, Phase D 扩围点):
//   - ownership 的 subordinate/upline/other 判定已落 (SQL 查得到), 但**列表可见集合**
//     暂不扩 (仍走 myCustomerScopeSql 的 owner ∪ placement_parent); 标注 ≠ 可见性
//   - Phase D 上级推送 (customer_share 表) 落地后, ownership 的 upline 判定
//     要追加 (c) 段 EXISTS 子查询 (§3.4); 本期留空, 字段返回 "none"
//   - viewer 无加盟节点 → ownership 只可能 none 或 mine (按 owner_id 判定)
// ============================================

import { sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import {
  hasAccountSql,
  referredFranchiseeSql,
} from "@/lib/db/queries/customer-scope";
import { memberExistsSql } from "@/lib/billing/member-flag";

/** 来源枚举 (与 schema.ts acquireSource 一致; §5 M2 命名) */
export type AcquireSource = "friend" | "referral" | "cold_visit" | "ground_promo";

/**
 * viewer 上下文 (调用方传入; 与 src/lib/auth/viewer.ts / rbac.ts 的解析口径一致)
 *
 * 三种 caller 都能直接拼出来:
 *   - /api/customers/[id] route → getRbacContextForSession(session)
 *   - /api/customers route     → 同上
 *   - 内部 service / 单测     → 直接传 bigint
 */
export interface ViewerContext {
  /** 登录者 user.id (唯一识别码, ADR-0016 D1) */
  userId: bigint;
  /** 我的加盟节点 id (viewer.franchisee_id; 未加盟 = null) */
  franchiseeId: bigint | null;
  /** ★ 我的客户档案 id (user.customer_id; admin 豁免建档 → null, Q5) */
  customerId: bigint | null;
}

/**
 * 客户标识 (Phase A 口径, 列表/详情/概览共用)
 *
 * 字段语义:
 *   - affiliation: "none" (未加盟) / "direct" (加盟·直推 = 我的 referrer) / "nondirect" (加盟·非直推)
 *   - ownership: "mine" / "subordinate" (下级归属) / "upline" (上级归属, Phase D 后才有数据)
 *                 / "other" / "none" (无归属); §3.4 五态
 *   - member: 该客户关联账号的会员状态 (role='admin' OR member_until > NOW())
 *   - registered: 该客户档案对应一个 app 账号吗 (EXISTS user WHERE customer_id = ...)
 *   - source: 来源 + 转介绍介绍人; kind=null 表示未填写
 */
export interface CustomerIdentity {
  affiliation: "none" | "direct" | "nondirect";
  ownership: "mine" | "subordinate" | "upline" | "other" | "none";
  member: boolean;
  registered: boolean;
  source: { kind: AcquireSource | null; referrerName: string | null };
}

// ============================================
// SQL 构造 (与现 customer-scope.ts 同一风格, 单一真相源)
// ============================================
// referredFranchiseeSql 现由 customer-scope.ts 单一真相源 export (Phase A supersede);
//   本文件 re-use, 不重复定义 (避免口径漂移)。

/**
 * 「这位客户是不是我的下级归属客户 (subordinate)」
 * (Phase A 标注能力; 列表可见性扩围属 Phase D, 本函数只为 identity 标注)
 *
 * 口径: customer.owner_id = 某位下层 user.id
 *   - 下层 user = 同 root_id (多根防护, ADR-0015 Q13)
 *   - 同 placement_path 前缀 (我 + 后代)
 *   - 排除 viewer 自己 (viewer.franchisee_id)
 */
function ownedBySubordinateSql(viewer: ViewerContext): SQL {
  if (viewer.franchiseeId === null) return sql`false`;
  // 内联子查询: viewer 的 path / root → 下层 user.id → 命中 customer.owner_id
  return sql`EXISTS (
    SELECT 1 FROM franchisee sub_f
    JOIN franchisee me ON me.id = ${viewer.franchiseeId}
    JOIN "user" sub_u ON sub_u.franchisee_id = sub_f.id
    WHERE sub_f.deleted_at IS NULL
      AND sub_f.id <> ${viewer.franchiseeId}
      AND sub_f.root_id IS NOT DISTINCT FROM me.root_id
      AND sub_f.placement_path LIKE (me.placement_path || '%')
      AND ${customer.ownerId} = sub_u.id
  )`;
}

/**
 * 「这位客户是不是我的上级归属客户 (upline)」
 *
 * Phase A 留空: 上级推送 (customer_share) 在 Phase D 才落地 (§3.4 (c) 段);
 * 没有推送表 → 本判定恒 false。Phase D 接入点 = 在此函数里追加
 * `EXISTS (SELECT 1 FROM customer_share cs WHERE cs.customer_id = customer.id
 *    AND cs.to_user_id = ${viewer.userId} AND cs.revoked_at IS NULL)`。
 */
function ownedByUplineSql(viewer: ViewerContext): SQL {
  // Phase A: 上级推送表尚未建 → 永远 false (B2 INV-3: viewer 无节点时也别返 null)
  void viewer;
  return sql`false`;
}

/**
 * 一次性拿全部判定标志 (单条 SQL, 避免 5 次往返)
 *  - direct: 我的直推加盟商 (referrer 口径)
 *  - isFranchisee: 任一 active 加盟节点对应这位客户 (维度 1)
 *  - ownedByMe: owner_id = viewer.userId (维度 5 'mine')
 *  - ownedBySub: owner_id = 某位下层 user.id (维度 5 'subordinate')
 *  - ownedByUpl: 上级推送 (Phase A 留空恒 false; Phase D 接入)
 *  - isMember: memberExistsSql (维度 3)
 *  - hasAccount: hasAccountSql (维度 4)
 *  - acquireSource / sourceReferrerName: 直接读列 (维度 6)
 */
async function loadIdentityRow(
  customerId: bigint,
  viewer: ViewerContext
): Promise<{
  exists: boolean;
  isFranchisee: boolean;
  direct: boolean;
  ownedByMe: boolean;
  ownedBySub: boolean;
  ownedByUpl: boolean;
  ownerId: bigint | null;
  isMember: boolean;
  hasAccount: boolean;
  acquireSource: AcquireSource | null;
  sourceReferrerName: string | null;
} | null> {
  // ★ 注意: 全部用一行 SELECT 包起来, EXISTS 子查询内对外层 customer.id 必须限定
  //   (customer."id" 显式), 跟 customer-scope.ts:56 hasAccountSql 同口径。
  const directSql = referredFranchiseeSql(viewer.franchiseeId);
  const ownedByMeSql =
    viewer.userId != null
      ? sql`(${customer.ownerId} = ${viewer.userId})`
      : sql`false`;
  const ownedBySubSql = ownedBySubordinateSql(viewer);
  const ownedByUplSql = ownedByUplineSql(viewer);

  const rows = await db.execute<{
    is_franchisee: boolean;
    direct: boolean;
    owned_by_me: boolean;
    owned_by_sub: boolean;
    owned_by_upl: boolean;
    owner_id: string | null;
    is_member: boolean;
    has_account: boolean;
    acquire_source: AcquireSource | null;
    source_referrer_name: string | null;
  }>(sql`
    SELECT
      EXISTS (
        SELECT 1 FROM franchisee f
        JOIN "user" u ON u.franchisee_id = f.id
        WHERE f.deleted_at IS NULL
          AND u.customer_id = "customer"."id"
      ) AS is_franchisee,
      ${directSql} AS direct,
      ${ownedByMeSql} AS owned_by_me,
      ${ownedBySubSql} AS owned_by_sub,
      ${ownedByUplSql} AS owned_by_upl,
      "customer"."owner_id" AS owner_id,
      ${memberExistsSql(sql`u.customer_id = "customer"."id"`)} AS is_member,
      ${hasAccountSql} AS has_account,
      "customer"."acquire_source" AS acquire_source,
      "customer"."source_referrer_name" AS source_referrer_name
    FROM "customer"
    WHERE "customer"."id" = ${customerId} AND "customer"."deleted_at" IS NULL
    LIMIT 1
  `);
  const r = rows[0];
  if (!r) return null;
  return {
    exists: true,
    isFranchisee: r.is_franchisee === true,
    direct: r.direct === true,
    ownedByMe: r.owned_by_me === true,
    ownedBySub: r.owned_by_sub === true,
    ownedByUpl: r.owned_by_upl === true,
    ownerId: r.owner_id != null ? BigInt(r.owner_id) : null,
    isMember: r.is_member === true,
    hasAccount: r.has_account === true,
    acquireSource: (r.acquire_source ?? null) as AcquireSource | null,
    sourceReferrerName: r.source_referrer_name ?? null,
  };
}

// ============================================
// 主入口 (route 层 / service 层都用这一个)
// ============================================

/**
 * 解析一位客户的 6 维标识
 *
 * @param customerId 客户档案 id (bigint)
 * @param viewer     当前登录者 (从 session 解析; viewer.franchiseeId = null 也合法)
 * @returns CustomerIdentity; customer 不存在或已软删 → null
 *
 * 边界:
 *   - customer 已软删 / 不存在 → null (调用方据此 404)
 *   - viewer.userId 不存在 / 无效 → 当作未加盟 (返回 none + ownedByMe=false)
 *   - viewer.franchiseeId = null → affiliation='none', ownership ∈ {none, mine} (B2 INV-3)
 *   - 老 APK 不带 acquireSource → 来源字段为 null (= 未填写, 不报错)
 */
export async function resolveCustomerIdentity(
  customerId: bigint,
  viewer: ViewerContext
): Promise<CustomerIdentity | null> {
  const row = await loadIdentityRow(customerId, viewer);
  if (!row) return null;

  // ===== affiliation (维度 1+2 合并) =====
  //   isFranchisee=false → 'none' (维度 1: 未加盟)
  //   isFranchisee=true ∧ direct=true → 'direct' (加盟·直推)
  //   isFranchisee=true ∧ direct=false → 'nondirect' (加盟·非直推, 在我的可见树内)
  //   (B2 INV-3: viewer 无加盟节点 → direct 恒 false → isFranchisee=true 时仍给 'nondirect')
  let affiliation: CustomerIdentity["affiliation"];
  if (!row.isFranchisee) {
    affiliation = "none";
  } else if (row.direct) {
    affiliation = "direct";
  } else {
    affiliation = "nondirect";
  }

  // ===== ownership (维度 5; 五态) =====
  //   owned_by_me    → 'mine'
  //   owned_by_sub   → 'subordinate' (我的下级 user 归属)
  //   owned_by_upl   → 'upline' (上级推送; Phase A 留空, Phase D 接入)
  //   owner_id 有值但都不是我/下级/上级 → 'other' (理论上不该出现, scope 漏检告警用)
  //   owner_id IS NULL → 'none'
  let ownership: CustomerIdentity["ownership"];
  if (row.ownedByMe) {
    ownership = "mine";
  } else if (row.ownedBySub) {
    ownership = "subordinate";
  } else if (row.ownedByUpl) {
    ownership = "upline";
  } else {
    ownership = row.ownerId != null ? "other" : "none";
  }

  // 兜底: viewer.franchiseeId=null 时 ownedBySub/Upl 恒 false → ownership ∈ {mine, none}
  //   (B2 INV-3 硬约束: 不允许 null)

  return {
    affiliation,
    ownership,
    member: row.isMember,
    registered: row.hasAccount,
    source: {
      kind: row.acquireSource,
      referrerName: row.sourceReferrerName,
    },
  };
}