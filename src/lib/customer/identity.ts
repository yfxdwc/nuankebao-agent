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
  /**
   * 登录者 user.id (唯一识别码, ADR-0016 D1)。
   * ★ nullable: 列表查询等可能拿不到 userId (老 caller / dev skip-auth);
   *   ownedByMeSql 在 null 时走恒 false (与「不是同一个人」语义一致)。
   */
  userId: bigint | null;
  /** 我的加盟节点 id (viewer.franchisee_id; 未加盟 = null) */
  franchiseeId: bigint | null;
  /** ★ 我的客户档案 id (user.customer_id; admin 豁免建档 → null, Q5) */
  customerId: bigint | null;
}

/**
 * 客户标识 (Phase A + Phase D 口径, 列表/详情/概览共用)
 *
 * 字段语义:
 *   - affiliation: "none" (未加盟) / "direct" (加盟·直推 = 我的 referrer) / "nondirect" (加盟·非直推)
 *   - ownership: "mine" / "direct_downline" (我的下层加盟节点**本人档案**, §3.4 (b1) 第 6 态)
 *                 / "subordinate" (我的下层归属客户, §3.4 (b2)) / "upline" (上级推送客户, §3.4 (c))
 *                 / "other" / "none" (无归属); §3.4 六态
 *                 优先级 mine > direct_downline > subordinate > upline > other > none
 *   - member: 该客户关联账号的会员状态 (role='admin' OR member_until > NOW())
 *   - registered: 该客户档案对应一个 app 账号吗 (EXISTS user WHERE customer_id = ...)
 *   - source: 来源 + 转介绍介绍人; kind=null 表示未填写
 */
export interface CustomerIdentity {
  affiliation: "none" | "direct" | "nondirect";
  ownership: "mine" | "direct_downline" | "subordinate" | "upline" | "other" | "none";
  member: boolean;
  registered: boolean;
  source: { kind: AcquireSource | null; referrerName: string | null };
  /** 归属人姓名 (「下级的客户 · 张三」用); 无归属 = null */
  ownerName: string | null;
  /** 上级推送人姓名 (「上级推送 · 张三」用; 仅 ownership = upline 时有值) */
  sharedByName: string | null;
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
 *
 * ★ P1-A 修复 (reviewer 第二轮, 2026-09-26): 子树判定**三元化**对齐设计文档 §3.4。
 *   旧实现 `sub.placement_path LIKE me.placement_path || '%'` 在 me.path = '' 时退化为
 *   `LIKE '%'` → 命中**所有** root (其他 root 的 path 也是 '') → 把同树其他 root 误判成自己下层。
 *   设计文档 §3.4 (b2) 段明确写法:
 *     (me.path = ''  AND sub.path <> '')
 *   OR (me.path <> '' AND sub.path LIKE me.path || '%')
 *   —— 我是根 = 下层必须是**非根**; 我非根 = 走原 LIKE 前缀。
 *
 * ★ export (Phase A 收口, 防 list / single 漂移): 列表口径**必须**复用本片段
 *   (src/lib/db/queries/customer.ts::listCustomers), 禁止在 customer.ts 里另写第二套。
 *   调用方: identity.ts::resolveCustomerIdentity + customer.ts::listCustomers。
 */
export function ownedBySubordinateSql(viewer: ViewerContext): SQL {
  if (viewer.franchiseeId === null) return sql`false`;
  // 内联子查询: viewer 的 path / root → 下层 user.id → 命中 customer.owner_id
  // ★★★ (b2) 三元化 (P1-A): me.path = '' 走 path <> ''; me.path <> '' 走 LIKE 前缀
  return sql`EXISTS (
    SELECT 1 FROM franchisee sub_f
    JOIN franchisee me ON me.id = ${viewer.franchiseeId}
    JOIN "user" sub_u ON sub_u.franchisee_id = sub_f.id
    WHERE sub_f.deleted_at IS NULL
      AND sub_f.id <> ${viewer.franchiseeId}
      AND sub_f.root_id IS NOT DISTINCT FROM me.root_id
      AND (
        (me.placement_path = ''  AND sub_f.placement_path <> '')
        OR
        (me.placement_path <> '' AND sub_f.placement_path LIKE (me.placement_path || '%'))
      )
      AND "customer"."owner_id" = sub_u.id
  )`;
}

/**
 * 「这位客户是不是我的上级归属客户 (upline)」 — Phase D 上线后由 customer_share 表供能
 *
 * Phase D 接入 (主文档 §3.4 (c) 字面):
 *   - 接收人 = viewer.userId, 推送 active (cs.revoked_at IS NULL)
 *   - 双方账号 active (SHARE-4: 一方停用 → 推送失效)
 *   - 推送人与 viewer 同枝 (跨枝防护)
 *
 * ★ export (Phase A 收口): 与 ownedBySubordinateSql 同 — 列表与单条共用。
 *   ⚠ 调用方 caller 需传入 viewer.userId (null 时 退化, 与其它 SQL 片段同处理)
 */
export function ownedByUplineSql(viewer: ViewerContext): SQL {
  if (viewer.userId == null) return sql`false`;
  // 四隐含条件 (主文档 §3.4 (c) 评审补):
  //   ① 接收人 (viewer.userId) active
  //   ② 推送人 active
  //   ③ 推送人节点未软删
  //   ④ 推送人与 viewer 同枝 — viewer 无 franchisee 时不护同枝 (推送人以 viewer 同枝为前提,
  //     viewer 是 admin / dev 时跳过枝护)
  //   ⑤ admin 推送 (无枝) 跳枝护
  //   ⑥ customer.deleted_at IS NULL 在 viewerCustomerScopeSql 外层处理 (E1), 本函数专注存在性
  return sql`EXISTS (
    SELECT 1 FROM customer_share cs
    WHERE cs.customer_id = "customer"."id"
      AND cs.to_user_id = ${viewer.userId}
      AND cs.revoked_at IS NULL
      AND EXISTS (SELECT 1 FROM "user" r WHERE r.id = cs.to_user_id  AND r.is_active = true)
      AND EXISTS (SELECT 1 FROM "user" f WHERE f.id = cs.from_user_id AND f.is_active = true)
      AND (
        NOT EXISTS (SELECT 1 FROM "user" f
                    WHERE f.id = cs.from_user_id AND f.franchisee_id IS NOT NULL)
        OR EXISTS (SELECT 1 FROM "user" f
                   JOIN franchisee ff ON ff.id = f.franchisee_id
                   WHERE f.id = cs.from_user_id AND ff.deleted_at IS NULL
                     AND ff.root_id IS NOT DISTINCT FROM (
                       SELECT root_id FROM franchisee WHERE id = ${viewer.franchiseeId ?? sql`NULL::bigint`} LIMIT 1
                     ))
      )
  )`;
}

/**
 * 「这位客户是不是我的直接加盟下线 (direct_downline) 本人档案」 — Phase D 第 6 态 (SHARE-7)
 *
 * 主文档 §3.4 (b1) 第 6 态: 这位客户是**我的下层加盟节点** (placement_parent_id = viewer.franchisee_id)
 * 的**本人档案** — 即下层节点的 user.customer_id 对应这个 customer.id。
 * 其 `owner_id` 可能既不是 viewer 也不是下层 (例: 被 transfer 过、不是下层归属的客户),
 * 不加本判定会被 (b1) 命中但 ownership 落到 `other`, 触发「scope 漏检告警」。
 *
 * 口径 (§3.4 (b1) + §6.5.6 SHARE-7):
 *   - f.placement_parent_id = viewer.franchisee_id
 *   - u.customer_id = "customer"."id"
 *   - f.deleted_at IS NULL
 *   - u.is_active = true (本人在册)
 *
 * ★ 与 `directDownlineFranchiseeSql` 同口径 (单一真相源, Phase A 收口防漂移)。
 *   viewer.franchiseeId = null → 退化。
 */
export function ownedByDirectDownlineSql(viewer: ViewerContext): SQL {
  if (viewer.franchiseeId == null) return sql`false`;
  return sql`EXISTS (
    SELECT 1 FROM franchisee f
    JOIN "user" u ON u.franchisee_id = f.id
    WHERE f.deleted_at IS NULL
      AND f.placement_parent_id = ${viewer.franchiseeId}
      AND u.customer_id = "customer"."id"
      AND u.is_active = true
  )`;
}

/**
 * 「这位客户是不是我的直接归属客户 (mine)」
 * —— 归属人 (customer.owner_id) = viewer.userId。
 *
 * ★ export (Phase A 收口): 列表与单条共用, 禁止 customer.ts 里另写 `owner_id = ?`。
 *   SQL 形态极简, 但抽出单一入口仍是防漂移的关键。
 */
export function ownedByMeSql(viewer: ViewerContext): SQL {
  if (viewer.userId == null) return sql`false`;
  return sql`("customer"."owner_id" = ${viewer.userId})`;
}

/**
 * 「这位客户是不是一位 active 加盟商」= 任一 active 加盟节点对应这位客户
 *   (EXISTS franchisee f JOIN user u ON u.franchisee_id = f.id WHERE u.customer_id = customer.id)
 *
 * 维度 1 判定 (affiliation 计算起点)。★ export (Phase A 收口): 与 identity.ts 其它 SQL 片段同口径。
 */
export function isFranchiseeSql(): SQL<boolean> {
  return sql<boolean>`EXISTS (
    SELECT 1 FROM franchisee f
    JOIN "user" u ON u.franchisee_id = f.id
    WHERE f.deleted_at IS NULL
      AND u.customer_id = "customer"."id"
  )`;
}

/**
 * 一次性拿全部判定标志 (单条 SQL, 避免 5 次往返)
 *  - direct: 我的直推加盟商 (referrer 口径)
 *  - isFranchisee: 任一 active 加盟节点对应这位客户 (维度 1)
 *  - ownedByMe: owner_id = viewer.userId (维度 5 'mine')
 *  - ownedBySub: owner_id = 某位下层 user.id (维度 5 'subordinate')
 *  - ownedByUpl: 上级推送 (§3.4 (c), Phase D 接入 customer_share)
 *  - ownedByDirectDownline: 我的下层加盟节点本身 = viewer 下线 (Phase D 第 6 态 SHARE-7)
 *  - isMember: memberExistsSql (维度 3)
 *  - hasAccount: hasAccountSql (维度 4)
 *  - acquireSource / sourceReferrerName: 直接读列 (维度 6)
 *
 * ★ Phase A + D 收口 (reviewer 第二轮): 同一组 SQL 片段同时被单条 resolveCustomerIdentity
 *   与列表 listCustomers 复用。SQL 编排集中在 renderIdentitySelectFields(); 改变量时
 *   两边自动一致 —— 禁止在 customer.ts 另写一套。
 */
async function loadIdentityRow(
  customerId: bigint,
  viewer: ViewerContext
): Promise<IdentityFlags | null> {
  // ★ 注意: 全部用一行 SELECT 包起来, EXISTS 子查询内对外层 customer.id 必须限定
  //   (customer."id" 显式), 跟 customer-scope.ts:56 hasAccountSql 同口径。
  const fields = renderIdentitySelectFields(viewer);
  const rows = await db.execute<{
    is_franchisee: boolean;
    direct: boolean;
    owned_by_me: boolean;
    owned_by_sub: boolean;
    owned_by_upl: boolean;
    owned_by_direct_downline: boolean;
    owner_id: string | null;
    is_member: boolean;
    has_account: boolean;
    acquire_source: AcquireSource | null;
    source_referrer_name: string | null;
    owner_name: string | null;
    shared_by_name: string | null;
  }>(sql`
    SELECT
      ${fields.isFranchisee}             AS is_franchisee,
      ${fields.direct}                  AS direct,
      ${fields.ownedByMe}               AS owned_by_me,
      ${fields.ownedBySub}              AS owned_by_sub,
      ${fields.ownedByUpl}              AS owned_by_upl,
      ${fields.ownedByDirectDownline}  AS owned_by_direct_downline,
      ${fields.ownerId}                 AS owner_id,
      ${fields.isMember}                AS is_member,
      ${fields.hasAccount}              AS has_account,
      ${fields.acquireSource}           AS acquire_source,
      ${fields.sourceReferrerName}      AS source_referrer_name,
      ${fields.ownerName}               AS owner_name,
      ${fields.sharedByName}            AS shared_by_name
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
    ownedByDirectDownline: r.owned_by_direct_downline === true,
    ownerId: r.owner_id != null ? BigInt(r.owner_id) : null,
    isMember: r.is_member === true,
    hasAccount: r.has_account === true,
    acquireSource: (r.acquire_source ?? null) as AcquireSource | null,
    sourceReferrerName: r.source_referrer_name ?? null,
    ownerName: r.owner_name ?? null,
    sharedByName: r.shared_by_name ?? null,
  };
}

/**
 * 行级判定标志 —— `loadIdentityRow` / 列表 SELECT 共用同一组片段。
 * 改本函数 = 同时改两个调用方, 不会出现「列表漏更新」的漂移。
 *
 * 列表口径 (src/lib/db/queries/customer.ts::listCustomers) 通过把每个字段塞进 SELECT,
 * 然后用 `identityFromFlags()` 映射成 CustomerIdentity, 与单条 resolveCustomerIdentity
 * 走完全相同的 `identityFromFlags()`。
 */
export interface IdentityFlags {
  exists: boolean;
  isFranchisee: boolean;
  direct: boolean;
  ownedByMe: boolean;
  ownedBySub: boolean;
  ownedByUpl: boolean;
  ownedByDirectDownline: boolean;
  ownerId: bigint | null;
  isMember: boolean;
  hasAccount: boolean;
  acquireSource: AcquireSource | null;
  sourceReferrerName: string | null;
  ownerName: string | null;
  sharedByName: string | null;
}

/**
 * 渲染身份 SELECT 字段 (11 个标量 / 布尔表达式)。
 *
 * ★ 单一真相源: 改其中任何一个片段, **单条 / 列表**都会同步变化。
 *   - `isFranchisee` 走 isFranchiseeSql() (本文件 §6 维度 1)
 *   - `direct`       走 referredFranchiseeSql() (customer-scope, referrer 口径)
 *   - `ownedByMe`    走 ownedByMeSql() (本文件 §5)
 *   - `ownedBySub`   走 ownedBySubordinateSql() (本文件 §2, ★ P1-A 修复后)
 *   - `ownedByUpl`   走 ownedByUplineSql() (本文件 §3, Phase D 接入 customer_share)
 *   - `ownedByDirectDownline` 走 ownedByDirectDownlineSql() (本文件 §3.5, 第 6 态 SHARE-7)
 *   - `ownerId`      直接读 "customer"."owner_id" 列
 *   - `isMember`     走 memberExistsSql (billing/member-flag)
 *   - `hasAccount`   走 hasAccountSql (customer-scope)
 *   - `acquireSource` / `sourceReferrerName`: 直接读列 (维度 6)
 *
 * 返回的对象可在 db.select({ ... }) 里直接展开:
 *   db.select({ row: customer, ...renderIdentitySelectFields(viewer) }).from(customer)
 */
export function renderIdentitySelectFields(viewer: ViewerContext): {
  isFranchisee: SQL<boolean>;
  direct: SQL<boolean>;
  ownedByMe: SQL;
  ownedBySub: SQL;
  ownedByUpl: SQL;
  ownedByDirectDownline: SQL;
  ownerId: SQL;
  isMember: SQL<boolean>;
  hasAccount: SQL<boolean>;
  acquireSource: SQL<AcquireSource | null>;
  sourceReferrerName: SQL<string | null>;
  ownerName: SQL<string | null>;
  sharedByName: SQL<string | null>;
} {
  // 归属人姓名 (「下级的客户 · 张三」) —— 只回姓名, 不回手机号
  const ownerNameSql = sql<string | null>`(
    SELECT u.name FROM "user" u WHERE u.id = "customer"."owner_id"
  )`;
  // 上级推送人姓名 (「上级推送 · 张三」) —— 仅当 viewer 是该推送的接收人
  const sharedByNameSql =
    viewer.userId != null
      ? sql<string | null>`(
          SELECT f.name FROM customer_share cs
          JOIN "user" f ON f.id = cs.from_user_id
          WHERE cs.customer_id = "customer"."id"
            AND cs.to_user_id = ${viewer.userId}
            AND cs.revoked_at IS NULL
          LIMIT 1
        )`
      : sql<string | null>`NULL::text`;

  return {
    isFranchisee: isFranchiseeSql(),
    direct: referredFranchiseeSql(viewer.franchiseeId) as SQL<boolean>,
    ownedByMe: ownedByMeSql(viewer),
    ownedBySub: ownedBySubordinateSql(viewer),
    ownedByUpl: ownedByUplineSql(viewer),
    ownedByDirectDownline: ownedByDirectDownlineSql(viewer),
    ownerId: sql`"customer"."owner_id"`,
    isMember: memberExistsSql(sql`u.customer_id = "customer"."id"`),
    hasAccount: hasAccountSql as SQL<boolean>,
    acquireSource: sql`"customer"."acquire_source"`,
    sourceReferrerName: sql`"customer"."source_referrer_name"`,
    ownerName: ownerNameSql,
    sharedByName: sharedByNameSql,
  };
}

/**
 * 把判定标志映射成 CustomerIdentity (纯函数; 单条 / 列表共用)。
 *
 * 优先级 (与设计文档 §3.4 + §6.5.6 SHARE-7 一致, Phase D 第 6 态):
 *   affiliation:
 *     !isFranchisee → 'none'
 *     isFranchisee && direct  → 'direct'
 *     isFranchisee && !direct → 'nondirect' (在我的可见树内但不是我的直推)
 *   ownership (B2 INV-3: viewer 无节点时只可能 none/mine):
 *     mine > direct_downline > subordinate > upline > other > none
 *     mine              我的归属客户 (a)
 *     direct_downline   我的下层加盟节点本人档案 (b1, Phase D 第 6 态 SHARE-7:
 *                      b1 命中时 覆写  不得落 other — 否则误报 scope 漏检)
 *     subordinate       我的下层归属客户 (b2, 同枝下层 user 归属)
 *     upline            上级推送客户 (c, Phase D customer_share)
 *     other             ownerId 有值但都不是 (scope 漏检告警用)
 *     none              ownerId IS NULL
 *
 * ★ export: 测试 / listCustomers / resolveCustomerIdentity 三处共用, 防漂移。
 */
export function identityFromFlags(flags: IdentityFlags): CustomerIdentity {
  let affiliation: CustomerIdentity["affiliation"];
  if (!flags.isFranchisee) {
    affiliation = "none";
  } else if (flags.direct) {
    affiliation = "direct";
  } else {
    affiliation = "nondirect";
  }

  let ownership: CustomerIdentity["ownership"];
  if (flags.ownedByMe) {
    ownership = "mine";
  } else if (flags.ownedByDirectDownline) {
    // ★ Phase D (b1) 第 6 态: 下层加盟节点本人档案命中时 覆写  | (SHARE-7)
    //   不能落到 other — 不然误报 scope 漏检
    ownership = "direct_downline";
  } else if (flags.ownedBySub) {
    ownership = "subordinate";
  } else if (flags.ownedByUpl) {
    ownership = "upline";
  } else {
    ownership = flags.ownerId != null ? "other" : "none";
  }

  return {
    affiliation,
    ownership,
    member: flags.isMember,
    registered: flags.hasAccount,
    source: {
      kind: flags.acquireSource,
      referrerName: flags.sourceReferrerName,
    },
    ownerName: flags.ownerName,
    sharedByName: flags.sharedByName,
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

  // ★ 单一映射入口 (reviewer 第二轮, 防 list / single 漂移): 改判定逻辑 → 改 identityFromFlags,
  //   单条 + 列表同步生效。
  return identityFromFlags(row);
}