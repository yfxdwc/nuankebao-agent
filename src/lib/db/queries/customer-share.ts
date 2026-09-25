// ============================================
// 客户推送模块 (customer_share 表 DAL)
// Phase D (docs/customer-identity-system.md §6.5 / ADR-0019)
// ============================================
// 推送机制 = **归属人显式授权可见性** (不像 owner 直接归属, 这里只是授权我代为跟进)
// 主文档 §6.5.4 API 与 §6.5.6 不变量; ADR-0019 §2.4 推送规则 (RBAC-3)
//
// S1-S7 规则 (主文档 §6.5.2):
//   S1  只有该客户的归属人 (customer.owner_id) 或 role='admin' 能推送
//   S2  接收人 to_user_id 必须是推送者所在枝的下层用户 (同 root_id + placement_path 前缀)
//       admin 不受此限
//   S3  推送 ≠ 转移归属 (customer.owner_id 不变)
//   S4  同 (customer, to_user) 仅一条 active 推送 (部分唯一索引 + ON CONFLICT → 409)
//   S5  接收人 / 推送人 / 当前归属人 / admin 四方都能撤销 (revoked_at = NOW())
//   S6  扩散上限: 同客户 active 推送数 ≤ 5 (可配); 同一接收人每日收到 ≤ 100
//       超限 → 400 SHARE_LIMIT_EXCEEDED
//   S7  禁止二次转发: 被推送人不能把收到的客户再推给她的下层
//
// 不变量 (主文档 §6.5.6):
//   SHARE-1  推送不写 customer.owner_id
//   SHARE-2  推送不改变紧急度算法结果
//   SHARE-3  被推送人看的是同一份客户档案, 不是副本 (无 customer_copy)
//   SHARE-4  推送双方任一停用 → 列表不可见 (在 SQL 层加 EXISTS user active)
//   SHARE-5  customer_share 必挂审计触发器 (audit_trigger.sql)
//   SHARE-6  customer.owner_id 被 transfer 后, 该客户 active 推送**保留**
//            (推送是独立可见性授权, 与归属无关); 新 owner 可撤销
//   SHARE-7  (b1) 命中的客户其 ownership 必须是 direct_downline (不得落 other)
//
// 错误码常量 (主文档 §6.5.4):
//   - 400 SHARE_LIMIT_EXCEEDED        推送扩散上限
//   - 400 ZERO_PUSH_TO_SELF           推送给自己 = 无意义
//   - 400 TO_USER_NOT_IN_SAME_BRANCH  S2 跨枝拒绝
//   - 400 FORBIDDEN_RE_SHARE          S7 禁止二次转发
//   - 400 REQUIRES_SAME_BRANCH_ROOT   推送者无 franchisee 枝时不可下推 (admin 豁免)
//   - 403 NOT_OWNER                   S1 非归属人/非 admin
//   - 404 CUSTOMER_NOT_FOUND
//   - 404 ACTIVE_SHARE_NOT_FOUND      撤销: 没有 active 推送
//   - 409 ALREADY_SHARED              S4 重复推送
// ============================================

import { sql, and, eq, isNull, count, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  customerShare,
  franchisee,
  user as userTable,
} from "@/lib/db/schema";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { decryptField } from "@/lib/crypto/field";
import { maskPhone } from "@/lib/utils";

// ============================================
// 错误码常量 (集中声明, 路由层 / 测试层共用)
// ============================================

export const SHARE_ERROR_CODES = {
  SHARE_LIMIT_EXCEEDED: "SHARE_LIMIT_EXCEEDED",
  ZERO_PUSH_TO_SELF: "ZERO_PUSH_TO_SELF",
  TO_USER_NOT_IN_SAME_BRANCH: "TO_USER_NOT_IN_SAME_BRANCH",
  FORBIDDEN_RE_SHARE: "FORBIDDEN_RE_SHARE",
  REQUIRES_SAME_BRANCH_ROOT: "REQUIRES_SAME_BRANCH_ROOT",
  NOT_OWNER: "NOT_OWNER",
  CUSTOMER_NOT_FOUND: "CUSTOMER_NOT_FOUND",
  ACTIVE_SHARE_NOT_FOUND: "ACTIVE_SHARE_NOT_FOUND",
  ALREADY_SHARED: "ALREADY_SHARED",
  RECIPIENT_INACTIVE: "RECIPIENT_INACTIVE",
  RECIPIENT_NOT_FOUND: "RECIPIENT_NOT_FOUND",
  REASON_REQUIRED: "REASON_REQUIRED",
} as const;

export type ShareErrorCode =
  (typeof SHARE_ERROR_CODES)[keyof typeof SHARE_ERROR_CODES];

// ============================================
// 错误类 (推送 / 撤销 / 查询 共用)
// ============================================

export class CustomerShareError extends Error {
  readonly code: ShareErrorCode;
  readonly detail?: string;
  constructor(code: ShareErrorCode, message: string, detail?: string) {
    super(message);
    this.name = "CustomerShareError";
    this.code = code;
    this.detail = detail;
  }
}

// ============================================
// 推送上限 (S6) — 主文档 §6.5.2 S6 字面
// ============================================

/** 同一客户 active 推送数上限 (D8 明文风险配套) */
export const MAX_ACTIVE_SHARES_PER_CUSTOMER = 5;
/** 同一接收人每日最多接收推送 (D8 明文风险配套) */
export const MAX_DAILY_SHARES_PER_RECIPIENT = 100;

// ============================================
// 输入类型
// ============================================

export interface ShareCustomerInput {
  customerId: bigint;
  /** 推送者 user.id (调用方注入, 通常 = session.user.id; 不能由 client 传) */
  fromUserId: bigint;
  /** 接收人 user.id (前端从 picker 选) */
  toUserId: bigint;
  /** 推送说明 (≤ 200 字, zod refine 负责, 这里再 defensive 截断) */
  note?: string | null;
}

export interface ShareCustomerOk {
  id: string;
  customerId: string;
  fromUserId: string;
  toUserId: string;
  note: string | null;
  createdAt: Date;
}

export type ShareCustomerFailure =
  | "CUSTOMER_NOT_FOUND"
  | "NOT_OWNER"
  | "ZERO_PUSH_TO_SELF"
  | "RECIPIENT_NOT_FOUND"
  | "RECIPIENT_INACTIVE"
  | "TO_USER_NOT_IN_SAME_BRANCH"
  | "FORBIDDEN_RE_SHARE"
  | "REQUIRES_SAME_BRANCH_ROOT"
  | "ALREADY_SHARED"
  | "SHARE_LIMIT_EXCEEDED";

export type ShareCustomerResult =
  | { ok: true; alreadyShared: boolean; row: ShareCustomerOk }
  | { ok: false; code: ShareCustomerFailure; detail?: string };

// ============================================
// 工具: 取 (推送者) 是否 admin (db 真相源, 与 src/lib/auth/rbac.ts 一致)
// ============================================

async function isAdmin(userId: bigint): Promise<boolean> {
  const [u] = await db
    .select({ role: userTable.role, isActive: userTable.isActive })
    .from(userTable)
    .where(eq(userTable.id, userId))
    .limit(1);
  return u?.role === "admin" && u.isActive === true;
}

/**
 * 推送者所在枝的下层 user.id 集合 (S2 同枝判定)
 *   - viewer.franchiseeId = null (admin) → 返回 null (admin 不受限)
 *   - viewer.franchiseeId 存在 → 同 root_id + placement_path 前缀 + 排除自己
 *     (与主文档 §3.4 (b2) 同一三元化)
 *
 * 本函数返回**子集查询的 SQL 片段**, 供 shareCustomer 校验 toUserId 是否在枝内。
 */
function isSameBranchSql(
  fromUserId: bigint,
  toUserFranchiseeId: bigint,
): SQL {
  // toUserId 不必是当前 fromUserId = admin — admin 不限枝
  // toUserId 的 franchisee_id 必须与 fromUserId 的 franchisee 同 root_id + placement_path 前缀
  // (排除自推)
  return sql`EXISTS (
    SELECT 1 FROM franchisee me_f
    JOIN franchisee sub_f ON sub_f.id = ${toUserFranchiseeId}
    JOIN "user" me_u ON me_u.franchisee_id = me_f.id
    WHERE me_u.id = ${fromUserId}
      AND me_u.franchisee_id IS NOT NULL
      AND sub_f.deleted_at IS NULL
      AND sub_f.id <> me_f.id
      AND sub_f.root_id IS NOT DISTINCT FROM me_f.root_id
      AND (
        (me_f.placement_path = ''  AND sub_f.placement_path <> '')
        OR
        (me_f.placement_path <> '' AND sub_f.placement_path LIKE (me_f.placement_path || '%'))
      )
  )`;
}

// ============================================
// shareCustomer — S1-S7 全部校验
// ============================================

/**
 * 推送客户档案给同枝下层用户 (或 admin 推送)
 *
 * @param ctx 审计上下文 (userId / ipAddress 透传 audit_trigger)
 * @returns 成功 / 失败结果 (失败含 code, 调用方 4xx 状态映射)
 *
 * 校验顺序 (主文档 §6.5.4 zod refine + S1-S7):
 *   1. 客户档案存在 / 未软删        → 404 CUSTOMER_NOT_FOUND
 *   2. 推送者 = 归属人 OR role=admin → 403 NOT_OWNER
 *   3. toUserId != fromUserId       → 400 ZERO_PUSH_TO_SELF (自推无用)
 *   4. toUserId 存在 + active       → 404 / 400 错码
 *   5. S2 同枝判定 (admin 豁免)
 *        admin 推送无 franchisee → 400 REQUIRES_SAME_BRANCH_ROOT?  本 admin 豁免
 *        fromUser 非 admin 无 franchisee → 400 (不能下推, 这是「加盟枝内推送」)
 *   6. S4 重复推送检查 (部分唯一索引兜底)
 *   7. S7 禁止二次转发: 接收人转推送过给 fromUser 的同样禁止再推 → FORBIDDEN_RE_SHARE
 *   8. S6 上限检查: 同客户 active ≤5, 同一接收人每日 ≤100 → 400 SHARE_LIMIT_EXCEEDED
 *   9. INSERT customer_share (revoked_at = NULL)
 *
 * 失败就抛 CustomerShareError (route 层 catch → 4xx); 成功返回 row
 */
export async function shareCustomer(
  input: ShareCustomerInput,
  ctx: AuditContext,
): Promise<ShareCustomerResult> {
  // 0. 基础参数断言 (调用方传错 = 立即可读错误)
  if (input.fromUserId === input.toUserId) {
    return { ok: false, code: "ZERO_PUSH_TO_SELF", detail: "不能把客户推给自己" };
  }

  // 1. 客户档案存在 / 未软删
  const [cust] = await db
    .select({ id: customer.id, ownerId: customer.ownerId, deletedAt: customer.deletedAt })
    .from(customer)
    .where(eq(customer.id, input.customerId))
    .limit(1);
  if (!cust || cust.deletedAt != null) {
    return { ok: false, code: "CUSTOMER_NOT_FOUND", detail: "客户档案不存在或已删除" };
  }

  // 2. S1: 只有归属人或 admin 能推
  const adminPusher = await isAdmin(input.fromUserId);
  if (!adminPusher && cust.ownerId !== input.fromUserId) {
    return { ok: false, code: "NOT_OWNER", detail: "只有归属人或系统管理员能推送客户" };
  }

  // 3. 接收人存在 + active
  const [toUser] = await db
    .select({
      id: userTable.id,
      isActive: userTable.isActive,
      franchiseeId: userTable.franchiseeId,
      customerId: userTable.customerId,
    })
    .from(userTable)
    .where(eq(userTable.id, input.toUserId))
    .limit(1);
  if (!toUser) {
    return { ok: false, code: "RECIPIENT_NOT_FOUND", detail: "接收人账号不存在" };
  }
  if (toUser.isActive !== true) {
    return { ok: false, code: "RECIPIENT_INACTIVE", detail: "接收人账号已停用" };
  }

  // 4. S2 同枝判定 — admin 豁免枝限制; fromUser 非 admin 必须有 franchisee (在枝内)
  if (!adminPusher) {
    // S2: 接收人必须有 franchisee 且与推送者同枝 (admin 推送则豁免)
    if (toUser.franchiseeId == null) {
      return {
        ok: false,
        code: "TO_USER_NOT_IN_SAME_BRANCH",
        detail: "接收人未接入加盟节点, 不能推送 (推送机制针对加盟枝内下层)",
      };
    }
    const sameBranch = await db.execute<{ x: boolean }>(
      sql`SELECT ${isSameBranchSql(input.fromUserId, toUser.franchiseeId)} AS x`,
    );
    if (!sameBranch[0]?.x) {
      return {
        ok: false,
        code: "TO_USER_NOT_IN_SAME_BRANCH",
        detail: "接收人与推送者不在同一加盟枝 (§6.5.2 S2 跨枝防护)",
      };
    }
  }

  // 5. S4 重复推送幂等检查 — 部分唯一索引 `uniq_customer_share_active`
  //   但先 SELECT, 给出友好 409 (而不是让唯一索引报错)
  const [existing] = await db
    .select({ id: customerShare.id })
    .from(customerShare)
    .where(
      and(
        eq(customerShare.customerId, input.customerId),
        eq(customerShare.toUserId, input.toUserId),
        isNull(customerShare.revokedAt),
      ),
    )
    .limit(1);
  if (existing) {
    return {
      ok: false,
      code: "ALREADY_SHARED",
      detail: "这个客户已经推送给这人了 (§6.5.2 S4 幂等)",
    };
  }

  // 6. S7 禁止二次转发: 接收人对这位客户是否**已有被推送过来的记录**
  //   如果是, toUser 是被推送人, 不能二次转发 (她没转发权)
  if (!adminPusher) {
    const [prior] = await db
      .select({ id: customerShare.id })
      .from(customerShare)
      .where(
        and(
          eq(customerShare.customerId, input.customerId),
          eq(customerShare.toUserId, input.fromUserId), // 我是被推送人
          isNull(customerShare.revokedAt),
        ),
      )
      .limit(1);
    if (prior) {
      return {
        ok: false,
        code: "FORBIDDEN_RE_SHARE",
        detail: "你是收到推送的客户, 不能二次转发 (§6.5.2 S7 二次转发禁令)",
      };
    }
  }

  // 7. S6 扩散上限检查 (两条一并查, 一并触发)
  const [perCustomerRow] = await db
    .select({ n: count() })
    .from(customerShare)
    .where(
      and(
        eq(customerShare.customerId, input.customerId),
        isNull(customerShare.revokedAt),
      ),
    );
  if (Number(perCustomerRow?.n ?? 0) >= MAX_ACTIVE_SHARES_PER_CUSTOMER) {
    return {
      ok: false,
      code: "SHARE_LIMIT_EXCEEDED",
      detail: `同一客户 active 推送数已到上限 ${MAX_ACTIVE_SHARES_PER_CUSTOMER} 条 (§6.5.2 S6)`,
    };
  }
  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);
  const [perRecipientRow] = await db
    .select({ n: count() })
    .from(customerShare)
    .where(
      and(
        eq(customerShare.toUserId, input.toUserId),
        isNull(customerShare.revokedAt),
        sql`${customerShare.createdAt} >= ${todayStart.toISOString()}::timestamptz`,
      ),
    );
  if (Number(perRecipientRow?.n ?? 0) >= MAX_DAILY_SHARES_PER_RECIPIENT) {
    return {
      ok: false,
      code: "SHARE_LIMIT_EXCEEDED",
      detail: `同一接收人今日已收 ${MAX_DAILY_SHARES_PER_RECIPIENT} 条 (§6.5.2 S6)`,
    };
  }

  // 8. INSERT — using withAuditContext 让 audit_trigger 抓 userId / ip
  const noteTrim = input.note ? input.note.trim().slice(0, 200) : null;
  let insertedId: bigint;
  try {
    await withAuditContext(ctx, async (tx) => {
      const [row] = await tx
        .insert(customerShare)
        .values({
          customerId: input.customerId,
          fromUserId: input.fromUserId,
          toUserId: input.toUserId,
          note: noteTrim,
        })
        .returning({ id: customerShare.id });
      insertedId = row.id;
    });
  } catch (e) {
    // 部分唯一索引兜底: 极端并发下两个 shareCustomer 同时通过 SELECT 检查后撞唯一索引
    //   → 这里识到 unique 违例后返 ALREADY_SHARED (幂等语义)
    if (String((e as Error).message).includes("uniq_customer_share_active")) {
      return {
        ok: false,
        code: "ALREADY_SHARED",
        detail: "该客户已推送给此用户 (并发落库 §6.5.2 S4)",
      };
    }
    throw e;
  }

  return {
    ok: true,
    alreadyShared: false,
    row: {
      id: String(insertedId!),
      customerId: input.customerId.toString(),
      fromUserId: input.fromUserId.toString(),
      toUserId: input.toUserId.toString(),
      note: noteTrim,
      createdAt: new Date(),
    },
  };
}

// ============================================
// revokeCustomerShare — S5 (撤销权 = from / to / 当前 owner / admin 四方)
// ============================================

export interface RevokeShareInput {
  customerId: bigint;
  /** URL `/api/customers/[id]/share/[userId]` 中的 userId (接收人) */
  toUserId: bigint;
  /** 撤销执行者 (URL 里没传, 走 session) */
  actorUserId: bigint;
  /** 撤销原因 (admin / 当前 owner 撤销必填, 走审计) — S5 */
  reason?: string | null;
}

export type RevokeShareFailure =
  | "CUSTOMER_NOT_FOUND"
  | "ACTIVE_SHARE_NOT_FOUND"
  | "NOT_AUTHORIZED"
  | "REASON_REQUIRED";

export type RevokeShareResult =
  | { ok: true; alreadyRevoked: boolean }
  | { ok: false; code: RevokeShareFailure; detail?: string };

/**
 * 撤销推送 (S5, 主文档 §6.5.2)
 *
 * 撤销权:
 *   - 推送人 (customer_share.from_user_id)
 *   - 接收人 (customer_share.to_user_id)
 *   - 当前归属人 (customer.owner_id)
 *   - 系统管理员 (role='admin')
 *
 * 撤销 ≠ 真 DELETE (主文档 §3.4 E1): 只 UPDATE revoked_at = NOW(), revoked_by = actor
 * `reason` 必填 (admin / 当前 owner 撤销时); 其它人撤销可选; 用 superRefine 校验
 *
 * 幂等: 重复撤销返回 alreadyRevoked=true (200) 而非 404 (主文档 §6.5.4 字面)
 */
export async function revokeCustomerShare(
  input: RevokeShareInput,
  ctx: AuditContext,
): Promise<RevokeShareResult> {
  // 1. 查找 active 推送 (含 from_user_id / to_user_id)
  const [existing] = await db
    .select({
      id: customerShare.id,
      fromUserId: customerShare.fromUserId,
      toUserId: customerShare.toUserId,
      revokedAt: customerShare.revokedAt,
      reason: customerShare.reason,
    })
    .from(customerShare)
    .where(
      and(
        eq(customerShare.customerId, input.customerId),
        eq(customerShare.toUserId, input.toUserId),
        isNull(customerShare.revokedAt),
      ),
    )
    .limit(1);
  if (!existing) {
    // 尝试看是否已被撤销过 (幂等返回)
    const [revoked] = await db
      .select({ id: customerShare.id })
      .from(customerShare)
      .where(
        and(
          eq(customerShare.customerId, input.customerId),
          eq(customerShare.toUserId, input.toUserId),
          sql`${customerShare.revokedAt} IS NOT NULL`,
        ),
      )
      .limit(1);
    if (revoked) {
      return { ok: true, alreadyRevoked: true };
    }
    return {
      ok: false,
      code: "ACTIVE_SHARE_NOT_FOUND",
      detail: "该客户的这条推送不存在",
    };
  }

  // 2. 撤销权校验
  const [customerRow] = await db
    .select({ ownerId: customer.ownerId, deletedAt: customer.deletedAt })
    .from(customer)
    .where(eq(customer.id, input.customerId))
    .limit(1);
  if (!customerRow || customerRow.deletedAt != null) {
    return { ok: false, code: "CUSTOMER_NOT_FOUND", detail: "客户档案不存在或已删除" };
  }
  const actorAdmin = await isAdmin(input.actorUserId);
  const isFrom = existing.fromUserId === input.actorUserId;
  const isTo = existing.toUserId === input.actorUserId;
  const isCurrentOwner = customerRow.ownerId === input.actorUserId;
  if (!actorAdmin && !isFrom && !isTo && !isCurrentOwner) {
    return {
      ok: false,
      code: "NOT_AUTHORIZED",
      detail: "只有推送人 / 接收人 / 当前归属人 / 系统管理员能撤销推送 (§6.5.2 S5)",
    };
  }

  // 3. reason 校验 (admin / 当前 owner 撤销必填)
  const reasonTrim = input.reason?.trim() ?? "";
  if ((actorAdmin || isCurrentOwner) && reasonTrim.length === 0) {
    return {
      ok: false,
      code: "REASON_REQUIRED",
      detail: "系统管理员 / 当前归属人撤销时必填原因 (写审计, §6.5.2 S5)",
    };
  }

  // 4. UPDATE revoked_at (E1: 不真 DELETE)
  await withAuditContext(ctx, async (tx) => {
    await tx
      .update(customerShare)
      .set({
        revokedAt: new Date(),
        revokedBy: input.actorUserId,
        reason: reasonTrim.length > 0 ? reasonTrim.slice(0, 200) : null,
      })
      .where(eq(customerShare.id, existing.id));
  });

  return { ok: true, alreadyRevoked: false };
}

// ============================================
// listReceivedShares — 当前 user 收到的 active 推送 (角标 / 元数据用)
// ============================================

export interface ReceivedShareRow {
  id: string;
  customerId: string;
  /** 推送人姓名 */
  fromUserName: string;
  /** 推送人手机号 (maskPhone 强制, 主文档 §9.3 注: 推送管理角标的「元数据」一律 mask) */
  fromUserPhoneMasked: string;
  /** 推送时间 */
  createdAt: Date;
  /** 推送说明 */
  note: string | null;
  /** 被推送的客户姓名 (mask 不在此做 — 详情路径走 viewerCustomerScopeSql) */
  customerName: string;
  /** 客户手机号 = 该客户归属人给当前接收人**作为元数据** → 同上, maskPhone (主文档 §9.3) */
  customerPhoneMasked: string;
}

/**
 * 当前 user (viewer) 收到的 active 推送 (角标 / 元数据)
 *
 * 元数据 (主文档 §9.3):
 *   - 所有手机号一律 mask (不论归属如何) — 角标**不是客户档案详情**, 不能透露完整信息
 *   - mask 函数 = src/lib/utils.ts:24 maskPhone
 */
export async function listReceivedShares(
  toUserId: bigint,
  options: { limit?: number } = {},
): Promise<ReceivedShareRow[]> {
  const { limit = 100 } = options;
  const rows = await db.execute<{
    id: string;
    customer_id: string;
    from_user_id: string;
    from_user_name: string;
    from_user_phone_encrypted: string | null;
    note: string | null;
    created_at: Date;
    customer_name: string;
    customer_phone_encrypted: string;
  }>(sql`
    SELECT cs.id::text         AS id,
           cs.customer_id::text AS customer_id,
           cs.from_user_id::text AS from_user_id,
           fu.name              AS from_user_name,
           fu.phone_encrypted   AS from_user_phone_encrypted,
           cs.note              AS note,
           cs.created_at        AS created_at,
           c.name               AS customer_name,
           c.phone_encrypted    AS customer_phone_encrypted
    FROM customer_share cs
    JOIN "user" fu ON fu.id = cs.from_user_id
    JOIN "user" tu ON tu.id = cs.to_user_id
    JOIN customer c ON c.id = cs.customer_id
    WHERE cs.to_user_id = ${toUserId}
      AND cs.revoked_at IS NULL
      AND c.deleted_at IS NULL
      AND fu.is_active = true
      AND tu.is_active = true  -- ★ SHARE-4: 接收人停用也失效 (与 §3.4 (c) 的 EXISTS user active 对齐)
    ORDER BY cs.created_at DESC
    LIMIT ${limit}
  `);
  // ★ mask 在这里做; 不暴露明文; 来自被推送的客户手机号也 mask (主文档 §9.3)
  return rows.map((r) => ({
    id: r.id,
    customerId: r.customer_id,
    fromUserName: r.from_user_name,
    fromUserPhoneMasked: maskPhone(
      r.from_user_phone_encrypted ? decryptField(r.from_user_phone_encrypted) : "",
    ),
    createdAt: r.created_at,
    note: r.note,
    customerName: r.customer_name,
    customerPhoneMasked: maskPhone(decryptField(r.customer_phone_encrypted)),
  }));
}



/**
 * 「这个客户当前推给过谁」 —— 归属卡上的「已推送」列表 + 撤销入口用。
 *
 * 与 listReceivedShares 的分工:
 *   - listReceivedShares: 我**收到**的推送 (被推送人视角, 「上级推送 · X」来源)
 *   - listSharesOfCustomer: 我**发出**的推送 (归属人视角, 撤销入口)
 *
 * @param fromUserId 传入时只回该用户发出的 (UI 用); admin 传 null = 全部
 */
export interface CustomerShareEntry {
  toUserId: string;
  toName: string;
  note: string | null;
  createdAt: string;
}

export async function listSharesOfCustomer(
  customerId: bigint,
  fromUserId: bigint | null,
): Promise<CustomerShareEntry[]> {
  const rows = await db.execute<{
    to_user_id: string;
    to_name: string;
    note: string | null;
    created_at: string;
  }>(sql`
    SELECT cs.to_user_id::text AS to_user_id,
           tu.name             AS to_name,
           cs.note             AS note,
           cs.created_at::text AS created_at
    FROM customer_share cs
    JOIN "user" tu ON tu.id = cs.to_user_id
    WHERE cs.customer_id = ${customerId}
      AND cs.revoked_at IS NULL
      ${fromUserId != null ? sql`AND cs.from_user_id = ${fromUserId}` : sql``}
    ORDER BY cs.created_at DESC
  `);
  return rows.map((r) => ({
    toUserId: r.to_user_id,
    toName: r.to_name,
    note: r.note,
    createdAt: r.created_at,
  }));
}
