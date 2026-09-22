// ============================================
// RBAC 行级过滤 (Plan W5 + ADR-0015 步骤 1)
// 根据 user.role (DB 为真相源) 返回 SQL 过滤条件
// - admin: 全网 (返回 undefined, 不加过滤)
// - manager: 本店 (managed store_ids 列表) —— ⚠ store 已冻结 (ADR-0015 Q8), 待 Phase 3 重定义
// - sales: 「我的客户」= 归属我 (customer.owner_id = 我) ∪ 我的直推加盟 (点位父 = 我)
//          (ADR-0015 Q2, 主人 2026-09-22 拍)
//
// 边界: CHARTER §3.6 + §3.1 红线
//   - 行级过滤不能完全靠应用层, 必须配合审计日志
//   - sales 看不到别人的客户 (旧口径 "除非同店" 已随门店维度冻结而废)
//   - manager 不能跨店看数据 (RBAC §3.6 红线)
// ============================================

import { db } from "@/lib/db";
import { user, storeStaff, customer, franchisee } from "@/lib/db/schema";
import { eq, inArray, or, and, isNull, sql } from "drizzle-orm";
import { myCustomerScopeSql } from "@/lib/db/queries/customer-scope";
import { isAuthSkipped } from "./skip-auth";

export type UserRole = "admin" | "manager" | "sales";

export interface RbacContext {
  userId: bigint;
  role: UserRole;
  defaultStoreId: bigint | null;
  managedStoreIds: bigint[];
  /**
   * 我的加盟节点 id (user.franchisee_id; 未加盟 = null)
   *   —— 「我的客户」口径的"直推加盟"半边 (ADR-0015 Q2); 同一次查询带出, 不额外往返
   */
  franchiseeId: bigint | null;
}

/**
 * 从 session 提取 RBAC 上下文
 *
 * 角色真相源 = **数据库** (`user.role`); 参数里的 sessionRole 只作兜底:
 *   - 老 JWT (2026-09-22 ADR-0015 步骤 0 之前签发) 里没有 role 字段
 *   - user 行查不到 (防 500; 理论上不会)
 * 顺带收益: 提权 / 降权立即生效, 不用等用户重新登录。
 *
 * 如果 store 关系没找到, 降级为 sales 视角 (只看自己)
 */
export async function getRbacContext(
  sessionUserId: bigint,
  sessionRole?: string | null,
): Promise<RbacContext> {
  // 一次查询同时取 role + defaultStoreId + franchiseeId (别拆多次往返)
  const [u] = await db
    .select({
      role: user.role,
      defaultStoreId: user.defaultStoreId,
      franchiseeId: user.franchiseeId,
    })
    .from(user)
    .where(eq(user.id, sessionUserId))
    .limit(1);

  const role: UserRole = u?.role ?? ((sessionRole as UserRole) || "sales");
  const defaultStoreId = u?.defaultStoreId ?? null;
  const franchiseeId = u?.franchiseeId ?? null;

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
    franchiseeId,
  };
}

/**
 * 路由便捷入口: session → RBAC 上下文
 *
 * - **dev skip-auth 且无 session** (没有"我"): 返回 `undefined` = **不做行级过滤**
 *   —— 没有身份就不存在"我的客户"口径; 与 ADR-0015 步骤 1 之前的 dev 行为一致
 *   (双门闸保护: NODE_ENV != production && DEV_SKIP_AUTH=1)
 * - 其余 (含生产): 一律 `getRbacContext` (角色真相源 = DB)
 */
export async function getRbacContextForSession(
  session:
    | { user?: { id?: string; role?: string } | null }
    | null
    | undefined
): Promise<RbacContext | undefined> {
  if (isAuthSkipped() && !session?.user?.id) return undefined;
  return getRbacContext(
    session?.user?.id ? BigInt(session.user.id) : BigInt(0),
    session?.user?.role
  );
}

/**
 * 返回 customer 表的查询过滤条件
 * - admin: 无过滤 (全网)
 * - manager: store_id IN managed_store_ids (⚠ store 冻结 —— 见下方注释)
 * - sales: 「我的客户」= 归属我 ∪ 我的直推加盟 (ADR-0015 Q2; 口径唯一真相源
 *          = queries/customer-scope.ts, 与列表 / 计数 / 概览共用)
 */
export function customerRbacFilter(ctx: RbacContext) {
  if (ctx.role === "admin") return undefined;

  if (ctx.role === "manager") {
    // ⚠ store / staff 已冻结 (ADR-0015 Q8, 0 行): 本分支保留旧行为
    //   (无店 → 看不到任何), "manager 视角" 待 Phase 3 多店台账重新定义。
    //   现网无 manager 账号, 不影响实际行为。
    if (ctx.managedStoreIds.length === 0) return eq(customer.id, sql`0`);
    return inArray(customer.storeId, ctx.managedStoreIds);
  }

  // sales (主人 2026-09-22 拍「全按建议」):
  //   旧口径 created_by = 我 OR store_id = 我的店 已废 ——
  //     created_by → owner_id (ADR-0015 Q11: 建档 ≠ 归属)
  //     store_id   → 直推加盟 (Q8 门店维度冻结; 结构口径 = 点位父, AGENTS §6.8)
  return myCustomerScopeSql({
    ownerUserId: ctx.userId,
    franchiseeId: ctx.franchiseeId,
  });
}

/**
 * franchisee 表的过滤条件 (ADR-0015 Q13, 主人 2026-09-22 拍「全按建议」)
 * - admin: 无 (全森林 + 未接入)
 * - manager: 不限 (manager 实际不查 franchisee, 但兜底)
 * - sales: 我 + **我的枝全部下层** + **上 3 层直系**
 *   (多根语义: 必须以 root_id 限定同树, 否则根用户 path='' 会串到别的树)
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

  // 我的 path / root (子树与祖判定都要用)
  const [my] = await db
    .select({ path: franchisee.placementPath, rootId: franchisee.rootId })
    .from(franchisee)
    .where(eq(franchisee.id, myFid))
    .limit(1);
  const myPath = my?.path ?? "";
  // 多根 (B1): 子树判定必须同树; 少了它, 根用户 (path='') 会看见所有树的节点
  const myRootId = my?.rootId ?? myFid;

  // 我 + 我整棵子树 + **上 3 层直系** (ADR-0015 Q13, 主人 2026-09-22 拍「全按建议」)
  //   旧口径: 我 + 直接下线 + 上级(1 层) + 子树 → 上层看不到第 2/3 层直系
  //   ⚠ 结构口径用 **点位父** (`placement_parent_id`, 拆栏见 schema.ts):
  //     我的直接下线 = 挂在我下面的人; 我的上层 = 我挂在谁下面 —— 与"推荐人"是两件事
  const conditions = [
    eq(franchisee.id, myFid), // 我自己
    eq(franchisee.placementParentId, myFid), // 我的直接下线
  ];

  // 上层直系 (最多 3 层): 沿 path 去尾 → 祖先 path 集合 (近 → 远), 同树内 path 唯一
  const ancestorPaths = uplineAncestorPaths(myPath, 3);
  if (ancestorPaths.length > 0) {
    conditions.push(
      and(
        sql`${franchisee.rootId} IS NOT DISTINCT FROM ${myRootId}`,
        inArray(franchisee.placementPath, ancestorPaths)
      )!
    );
  }

  // 我的枝 (全部下层, 不限层):
  //   - 非根: path 前缀匹配 (myPath + '%')
  //   - 根 (myPath=''): 整棵树 = 我的子树 —— 旧代码这里 if(myPath) 把根用户漏了,
  //     根用户只看得到 2 层邻居 (ADR-0015 Q13 要求「自己所在枝的下层全部」)
  conditions.push(
    myPath
      ? sql`(${franchisee.rootId} IS NOT DISTINCT FROM ${myRootId} AND ${franchisee.placementPath} LIKE ${myPath + "%"})`
      : sql`${franchisee.rootId} IS NOT DISTINCT FROM ${myRootId}`
  );

  return or(...conditions)!;
}

/**
 * 沿 placement_path 向上取 N 层祖先的 path (由近到远; 不含自己)
 *   例: 'L.R.' + N=3 → ['L.', '', ] (只有 2 层就停)
 *   与 queries/franchisee.ts::getUplineAncestors 同一算法 (那边在函数内联了一份)
 */
function uplineAncestorPaths(myPath: string, maxLevels: number): string[] {
  const out: string[] = [];
  let cur = myPath;
  for (let i = 0; i < maxLevels; i++) {
    const segs = cur.split(".").filter(Boolean);
    if (segs.length === 0) break; // 已经是根 → 没有更高层
    segs.pop();
    const parent = segs.length === 0 ? "" : segs.join(".") + ".";
    out.push(parent);
    cur = parent;
  }
  return out;
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