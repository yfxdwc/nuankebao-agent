// ============================================
// RBAC 行级过滤 (Plan W5)
// 根据 session.user.role 返回 SQL 过滤条件
// - admin: 全网 (返回 undefined, 不加过滤)
// - manager: 本店 (managed store_ids 列表)
// - sales: 自己 (created_by = me OR 默认 store_id = my store)
//
// 边界: CHARTER §3.6 + §3.1 红线
//   - 行级过滤不能完全靠应用层, 必须配合审计日志
//   - sales 看不到其他 sales 的客户 (除非同店)
//   - manager 不能跨店看数据 (RBAC §3.6 红线)
// ============================================

import { db } from "@/lib/db";
import { user, storeStaff, customer, franchisee } from "@/lib/db/schema";
import { eq, inArray, or, and, isNull, sql } from "drizzle-orm";

export type UserRole = "admin" | "manager" | "sales";

export interface RbacContext {
  userId: bigint;
  role: UserRole;
  defaultStoreId: bigint | null;
  managedStoreIds: bigint[];
}

/**
 * 从 session 提取 RBAC 上下文
 * 如果 store 关系没找到, 降级为 sales 视角 (只看自己)
 */
export async function getRbacContext(
  sessionUserId: bigint,
  sessionRole: string,
): Promise<RbacContext> {
  const role = (sessionRole as UserRole) || "sales";

  // 查 user.default_store_id
  const [u] = await db
    .select({ defaultStoreId: user.defaultStoreId })
    .from(user)
    .where(eq(user.id, sessionUserId))
    .limit(1);

  const defaultStoreId = u?.defaultStoreId ?? null;

  // 查 managed store_ids (如果是 manager)
  let managedStoreIds: bigint[] = [];
  if (role === "manager" || role === "admin") {
    const rows = await db
      .select({ storeId: storeStaff.storeId })
      .from(storeStaff)
      .where(
        and(
          eq(storeStaff.staffId, sessionUserId),
          eq(storeStaff.isManager, true),
        ),
      );
    managedStoreIds = rows.map((r) => r.storeId);
  }

  return {
    userId: sessionUserId,
    role,
    defaultStoreId,
    managedStoreIds,
  };
}

/**
 * 返回 customer 表的查询过滤条件
 * - admin: 无过滤
 * - manager: store_id IN managed_store_ids
 * - sales: created_by = me OR (store_id = my default_store AND store_id IS NOT NULL)
 *   (老数据 store_id NULL 兼容, Q1-A 决策)
 */
export function customerRbacFilter(ctx: RbacContext) {
  if (ctx.role === "admin") return undefined;

  if (ctx.role === "manager") {
    if (ctx.managedStoreIds.length === 0) return eq(customer.id, sql`0`); // 无店 = 看不到任何
    return inArray(customer.storeId, ctx.managedStoreIds);
  }

  // sales: 自己创建的 OR 同店
  const conditions = [eq(customer.createdBy, ctx.userId)];
  if (ctx.defaultStoreId != null) {
    conditions.push(eq(customer.storeId, ctx.defaultStoreId));
  }
  return or(...conditions)!;
}

/**
 * franchisee 表的过滤条件
 * - admin: 无
 * - manager: 不限 (manager 实际不查 franchisee, 但兜底)
 * - sales: 自己 + 上下级 (≤3 层, depth-based 过滤)
 *
 * 简化策略: sales 看到:
 *   - 自己 (id = my_franchisee_id)
 *   - 直接下线 (referrer_id = my_franchisee_id)
 *   - 直接上线的下线 (depth=2, 需要递归 - 用 materialized path LIKE)
 */
export async function franchiseeRbacFilter(ctx: RbacContext) {
  if (ctx.role === "admin" || ctx.role === "manager") return undefined;

  // sales: 查自己的 franchisee_id
  const [u] = await db
    .select({ franchiseeId: user.franchiseeId })
    .from(user)
    .where(eq(user.id, ctx.userId))
    .limit(1);

  const myFid = u?.franchiseeId;
  if (myFid == null) {
    // 没有加盟关系 = 看不到任何
    return eq(franchisee.id, sql`0`);
  }

  // 我 + 我的下线 (≤3 层) + 我的上线 (简化: 1 层)
  // depth 1: referrer_id = myFid
  // depth 2: path LIKE 'myPath.%.%'
  // depth 3: path LIKE 'myPath.%.%.%'
  // 简化为: 我 + 我直接下线 + 我的上线的下线 (depth ≤ 3)
  const [my] = await db
    .select({ path: franchisee.placementPath, rootId: franchisee.rootId })
    .from(franchisee)
    .where(eq(franchisee.id, myFid))
    .limit(1);
  const myPath = my?.path ?? "";
  // 多根 (B1): 子树判定必须同树; 少了它, 根用户 (path='') 会看见所有树的节点
  const myRootId = my?.rootId ?? myFid;

  const conditions = [
    eq(franchisee.id, myFid),                 // 我自己
    eq(franchisee.referrerId, myFid),        // 我的直接下线
    eq(franchisee.id, sql`(SELECT referrer_id FROM franchisee WHERE id = ${myFid})`), // 我的上级
  ];

  // 我的上级的下线 (depth=2)
  if (myPath) {
    // 任意以 myPath 开头的: 表示在我的子树里
    // 但更精确: referrer = my_referrer, depth <= 3
    // 简化: 包括所有 path LIKE 'myPath%' 但 depth - my_depth <= 3
    // 这里我们用 placement_path LIKE myPath% 覆盖子树
    conditions.push(
      sql`(${franchisee.rootId} = ${myRootId} AND ${franchisee.placementPath} LIKE ${myPath + "%"})`
    );
  }

  return or(...conditions)!;
}

/**
 * wellness_record 表过滤 (基于 customer.store_id)
 */
export function wellnessRecordRbacFilter(ctx: RbacContext) {
  if (ctx.role === "admin") return undefined;

  // wellness_record 没有 store_id 直接 FK, 通过 customer join
  // 简化: sales 只看自己创建的记录 (created_by)
  if (ctx.role === "sales") {
    return undefined; // TODO: 实现基于 customer.store_id 的过滤
  }

  if (ctx.role === "manager") {
    // 简化: manager 看本店所有 wellness_records
    // 实际: 需要 join customer 并用 inArray(customer.storeId, managedStoreIds)
    return undefined; // TODO
  }

  return undefined;
}

/**
 * franchisee 深度硬限 (≤3 层)
 * 检查 referrer 的 depth, 如果 >= 3 拒绝创建
 */
export async function checkMaxDepth(
  referrerId: bigint,
): Promise<{ allowed: boolean; reason?: string }> {
  const [ref] = await db
    .select({ depth: franchisee.placementDepth })
    .from(franchisee)
    .where(eq(franchisee.id, referrerId))
    .limit(1);

  if (!ref) {
    return { allowed: false, reason: "推荐人不存在" };
  }

  if (ref.depth >= 3) {
    return {
      allowed: false,
      reason: "加盟树深度上限 3 层, 不能再添加下线 (ADR-0006 / 《禁止传销条例》红线)",
    };
  }

  return { allowed: true };
}