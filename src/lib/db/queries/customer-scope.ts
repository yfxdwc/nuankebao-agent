// ============================================
// 客户可见范围 (「谁的客户」) —— 单一真相源
// ============================================
// ADR-0015 Q2 (主人 2026-09-22 拍「全按建议」):
//   「我的客户」= 归属我的人 (customer.owner_id = 我)
//                 ∪ 我的直推加盟 (franchisee.placement_parent_id = 我的节点)
//
// 为什么独立成文件 (不放 customer.ts / rbac.ts):
//   两边都要用 —— queries/customer.ts (列表 / 计数 / 图谱) 与 auth/rbac.ts (行级过滤);
//   而 customer.ts 已经 import rbac.ts 的 customerRbacFilter → 互相 import 会成环。
//   本文件只依赖 schema + drizzle, 谁都能安全 import。
//
// 口径提醒 (AGENTS §6.8 拆栏): 结构判定一律读 **点位父 placement_parent_id**,
//   不是 referrer_id (推荐人) —— 后者只用于展示, 不参与任何判定 (ADR-0015 Q3)。
// ============================================

import { sql, type SQL } from "drizzle-orm";
import { customer, franchisee } from "@/lib/db/schema";

/**
 * 「这位客户 (按 phone_hash 认人) 是不是我的**直推**加盟商」
 *
 * 直推 = 结构口径: 她的点位父 (`placement_parent_id`) 就是我 (= 第 1 层)
 *   - 2026-09-22 主人拍「列表加盟 = 只算我直推的」(与图谱"整个子树"故意不同)
 *   - 软删加盟商不算
 *   - viewerFranchiseeId = null (未加盟 / dev 无 session) → 永远 false
 */
export function directDownlineFranchiseeSql(
  viewerFranchiseeId: bigint | null
): SQL {
  if (viewerFranchiseeId === null) return sql`false`;
  // ★ ID 化连接 (ADR-0016 D3/D4, 主人 2026-09-22 拍「手机号不作为用户识别内容」):
  //   旧口径 `franchisee.phone_hash = customer.phone_hash` —— 同号不同人 / 改号会误判;
  //   新口径走真连接: 客户的**账号** (user.customer_id) → 她的加盟节点 (user.franchisee_id)
  return sql`EXISTS (
    SELECT 1 FROM franchisee f
    JOIN "user" u ON u.franchisee_id = f.id
    WHERE f.deleted_at IS NULL
      AND u.customer_id = ${customer.id}
      AND f.placement_parent_id = ${viewerFranchiseeId}
  )`;
}

/**
 * 「这条客户档案有对应账号吗」= UI 区分"已注册用户 / 凭空建档的客户" (ADR-0016 D8)
 *
 * ⚠⚠ **必须显式写表限定** (`"customer"."id"`), 不能插值 `${customer.id}`:
 *   drizzle 在 select 里把内联 sql 模板的列引用渲染成**裸列名** `"id"`,
 *   子查询里会被解析成 `u.id` → 语义变成 `u.customer_id = u.id` → **恒 false**。
 *   (2026-09-22 灌演示数据时实测踩到; tests/customer-scope.test.ts 有回归守卫)
 */
export const hasAccountSql = sql<boolean>`EXISTS (
  SELECT 1 FROM "user" u WHERE u.customer_id = "customer"."id"
)`;

/** 「这条客户档案归我」= 归属人 (customer.owner_id) 是我 */
export function ownedByUserSql(ownerUserId: bigint): SQL {
  return sql`${customer.ownerId} = ${ownerUserId}`;
}

/**
 * 「我的客户」可见范围 = 归属我 ∪ 我的直推加盟
 * (ADR-0015 Q2; 列表 / 胶囊计数 / 概览 / 行级过滤共用这一处)
 */
export function myCustomerScopeSql(input: {
  ownerUserId: bigint;
  franchiseeId: bigint | null;
}): SQL {
  return sql`(${ownedByUserSql(input.ownerUserId)} OR ${directDownlineFranchiseeSql(
    input.franchiseeId
  )})`;
}
