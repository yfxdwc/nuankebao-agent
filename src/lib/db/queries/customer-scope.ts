// ============================================
// 客户可见范围 (「谁的客户」) —— 单一真相源
// ============================================
// ADR-0015 Q2 (主人 2026-09-22 拍「全按建议」):
//   「我的客户」= 归属我的人 (customer.owner_id = 我)
//                 ∪ 我的直推加盟 (franchisee.placement_parent_id = 我的节点)
//
// Phase D (主人 2026-09-25 拍 D4 + ADR-0019) 扩围:
//   `viewerCustomerScopeSql(viewer)` = 四段式 (a + b1 + b2 + c):
//     (a)  customer.owner_id = viewer.user_id                     — 我的归属客户
//     (b1) 我的下层加盟节点 (placement_parent_id = 我) 本身档案 [结构口径, 保留]
//     (b2) customer.owner_id IN (我的下层归属客户)                [新增, 唯一真相源收窄点]
//     (c)  customer_share (上级推送)                              [新增, Phase D]
//
// 集中点 (主文档 §3.4 + ADR-0019 §2.2):
//   - 列表 / 计数 / /api/me 概览 / 行级过滤 一律走 `viewerCustomerScopeSql(viewer)`
//   - 收窄策略: 默认 (b) = 全下层 (与图谱同源); 未来改「仅直接下级」时**只动 (b2) 子句**,
//     调用方零改动
//   - 现有 `myCustomerScopeSql` (两段式) 保留不动 — 老调用方零影响
//   - `customer.deleted_at IS NULL` 在 viewerCustomerScopeSql 外层统一加, 调用方禁止裸拼 (E1)
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
import { customer, franchisee, user as userTable } from "@/lib/db/schema";

/**
 * 「这位客户 (按 phone_hash 认人) 是不是我的**直推**加盟商」
 *
 * 直推 = 结构口径: 她的点位父 (`placement_parent_id`) 就是我 (= 第 1 层)
 *   - 2026-09-22 主人拍「列表加盟 = 只算我直推的」(与图谱"整个子树"故意不同)
 *   - 软删加盟商不算
 *   - viewerFranchiseeId = null (未加盟 / dev 无 session) → 永远 false
 *
 * ⚠ supersede (主人 2026-09-25, docs/customer-identity-system.md §2):
 *   本函数仍走 `placement_parent_id` 口径 —— 但**这是「列表/计数可见集合」的判定**,
 *   与图谱 (`classifyRelation`) 的 referrer 口径**故意不同** (图谱要全树)。
 *   「客户**类型**判定」(加盟·直推 / 加盟·非直推) 已切到 `referredFranchiseeSql`
 *   (下条), supersede 现 `customer.ts:535-540` 旧 placement 口径。
 *   ⚠⚠ 本函数与 `referredFranchiseeSql` 同时存在是有意的:
 *     · `directDownlineFranchiseeSql` = 可见性扩围用 (placement 仍是同枝判定最简)
 *     · `referredFranchiseeSql`       = 身份类型标用 (与图谱同真相源)
 *   单一真相源 = `customer.ts::resolveCustomerType` (口径迁移) +
 *               `customer.ts::isMyDirectDownlineFranchisee` (单行查询)。
 *   改本函数 = 改可见性, 走 Phase D; 改 `referredFranchiseeSql` = 改身份标, 走 Phase A。
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
      AND u.customer_id = "customer"."id"
      AND f.placement_parent_id = ${viewerFranchiseeId}
  )`;
}

/**
 * 「这位客户是不是我的**直推**加盟商」—— supersede 口径 (主人 2026-09-25, §2.1):
 *
 * 直推 = **referrer_id** 口径: 把她带进加盟的人 (f.referrer_id) 就是我
 *   与图谱 `franchisee.ts:450` `classifyRelation` **同真相源**,
 *   修掉 "图谱说直推 / 列表说非直推" 的同屏打架 (I-2 不变量允许 referrer ≠ placement)。
 *   软删加盟商不算 (B1 INV-4)。
 *   viewerFranchiseeId = null → 永远 false (B2 INV-3)。
 *
 * ★★★ 必须显式写 `"customer"."id"` 表限定:
 *   drizzle 在子查询里把内联列渲染成裸 `"id"`, 子查询里被解析成 `u.id`,
 *   语义变成 `u.customer_id = u.id` → 恒 false (tests/customer-scope.test.ts 回归守卫)。
 *
 * 用法 (Phase A supersede, docs/customer-identity-system.md §2.3 改动列表):
 *   - `customer.ts::resolveCustomerType` (类型枚举, supersede 现 placement 口径)
 *   - `customer.ts::isMyDirectDownlineFranchisee` (单行查询)
 *   - `customer.ts::customerTypeCounts` (胶囊计数, 同上 supersede)
 *   - 列表可见性 (myCustomerScopeSql) **不动** —— 仍走 directDownlineFranchiseeSql,
 *     可见性扩围属 Phase D
 */
export function referredFranchiseeSql(
  viewerFranchiseeId: bigint | null
): SQL {
  if (viewerFranchiseeId === null) return sql`false`;
  return sql`EXISTS (
    SELECT 1 FROM franchisee f
    JOIN "user" u ON u.franchisee_id = f.id
    WHERE f.deleted_at IS NULL
      AND u.customer_id = "customer"."id"
      AND f.referrer_id = ${viewerFranchiseeId}
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
  return sql`"customer"."owner_id" = ${ownerUserId}`;
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

/**
 * Viewer 完整上下文 (主文档 §3.4 集中点 / Phase D 接入用)
 *
 * - 不强求 viewer.userId / viewer.franchiseeId 都在
 * - viewer.userId = null → (a)/(c) 自动退化 (admin / dev skip-auth 路径不走可见集)
 * - viewer.franchiseeId = null → (b1)/(b2) 自动退化, 只剩 (a) (B2 INV-3)
 */
export interface CustomerScopeViewer {
  userId: bigint | null;
  franchiseeId: bigint | null;
}

/**
 * 客户可见集合 = 四段式 (a + b1 + b2 + c) (主文档 §3.4 v1.3 字面)
 *
 * ★★★ 唯一真相源 — 列表 / 计数 / /api/me 概览 / 行级过滤 一律走本函数 (主文档 §3.4 集中点)。
 *    收窄为「仅直接下级」时**只动 (b2) 子句**, 其它三段零改动 — 调用方零影响。
 *
 * 口径来源 (主文档 §3.4 / ADR-0019 §2.2):
 *   (a)  customer.owner_id = viewer.user_id                                  — 我的归属客户
 *   (b1) f.placement_parent_id = viewer.franchisee_id ∧ u.customer_id = ...  — 我的下层加盟节点**本人档案**
 *   (b2) customer.owner_id IN (我的下层归属客户)                              — 我枝内下层 owner_id 引用的客户
 *   (c)  customer_share 存在 ∧ revoked_at IS NULL ∧ 双方账号 active ∧ 同枝   — 上级推送的客户
 *
 * 边界与不变量:
 *   - **本函数内自带 `customer.deleted_at IS NULL`** (E1): 调用方禁止自行写
 *   - viewer.franchiseeId IS NULL → (a) 单段 (B2 INV-3: 未加盟 viewer 不返 null 列表, 只返部分集合)
 *   - (c) 的四个隐含条件全部进 SELECT: 接收人 active + 推送人 active + 推送人在我同枝 (admin 无枝豁免)
 *   - receiver 与 viewer 自己不同枝身份不广 (本函数看的是「viewer 可见集合」,推送人于本语境同一校验集)
 */
export function viewerCustomerScopeSql(viewer: CustomerScopeViewer): SQL {
  // ★ 设计守卫 (主文档 §3.4 v1.3 + 四轮评审 P0): viewer 无加盟节点 → **只可能 (a)**
  //   否则 (c) 段的跨树比较会退化成 NULL vs NULL = TRUE, 让无节点用户看到别人推的客户
  if (viewer.franchiseeId == null) {
    return viewer.userId != null
      ? sql`("customer"."deleted_at" IS NULL AND ${ownedByUserSql(viewer.userId)})`
      : sql`("customer"."deleted_at" IS NULL AND false)`;
  }

  // (a) 单段: 归属 = viewer.user_id; viewer.userId = null → 退化 (同 (b2) viewer.userId=null)
  const segmentA = viewer.userId != null ? ownedByUserSql(viewer.userId) : sql`false`;

  // (b1) 我的下层加盟节点本人档案 (结构口径, placement_parent_id = 我)
  //   viewer.franchiseeId = null → 退化 (B2 INV-3)
  const segmentB1 = directDownlineFranchiseeSql(viewer.franchiseeId);

  // (b2) 我的下层归属的客户 (新增, §3.4 (b2))
  //   候选 = viewer 同 root_id 下:
  //     - viewer 是根 (path=''): 下层 = path <> '' 的所有节点
  //     - viewer 非根 (path<>''): 下层 = path LIKE viewer.path || '%' (前缀匹配)
  //   排除自己 (viewer.franchiseeId), 排除软删节点
  //   viewer.franchiseeId = null → 退化
  const segmentB2 =
    viewer.franchiseeId != null
      ? sql`EXISTS (
        SELECT 1 FROM "user" sub_u
        JOIN franchisee sub_f ON sub_f.id = sub_u.franchisee_id
        JOIN franchisee me_f ON me_f.id = ${viewer.franchiseeId}
        WHERE sub_f.deleted_at IS NULL
          AND sub_f.id <> ${viewer.franchiseeId}
          AND sub_f.root_id IS NOT DISTINCT FROM me_f.root_id
          AND (
            (me_f.placement_path = ''  AND sub_f.placement_path <> '')
            OR
            (me_f.placement_path <> '' AND sub_f.placement_path LIKE (me_f.placement_path || '%'))
          )
          AND "customer"."owner_id" = sub_u.id
      )`
      : sql`false`;

  // (c) 上级推送 (Phase D, §3.4 (c))
  //   四个隐含条件 (评审补):
  //     ① 接收人 (to_user = viewer.userId) active
  //     ② 推送人 (from_user) active
  //     ③ 推送人 ≠ 自己是同枝人 (跨枝防护) — admin 无枝时豁免
  //     ④ 推送人节点未软删 (ff.deleted_at IS NULL)
  //   viewer.userId = null → 退化 (推送必须指向一个 user)
  const segmentC =
    viewer.userId != null
      ? sql`EXISTS (
        SELECT 1 FROM customer_share cs
        WHERE cs.customer_id = "customer"."id"
          AND cs.to_user_id  = ${viewer.userId}
          AND cs.revoked_at IS NULL
          AND EXISTS (SELECT 1 FROM ${userTable} r WHERE r.id = cs.to_user_id AND r.is_active = true)
          AND EXISTS (SELECT 1 FROM ${userTable} f WHERE f.id = cs.from_user_id AND f.is_active = true)
          AND (
            NOT EXISTS (SELECT 1 FROM ${userTable} f
                        WHERE f.id = cs.from_user_id AND f.franchisee_id IS NOT NULL)
            OR EXISTS (SELECT 1 FROM ${userTable} f
                       JOIN franchisee ff ON ff.id = f.franchisee_id
                       WHERE f.id = cs.from_user_id AND ff.deleted_at IS NULL
                         AND ff.root_id IS NOT DISTINCT FROM ${viewer.franchiseeId == null ? sql`NULL::bigint` : sql`(
                             SELECT root_id FROM franchisee WHERE id = ${viewer.franchiseeId}
                           )`})
          )
      )`
      : sql`false`;

  // 四段汇集 + customer.deleted_at IS NULL (E1) + **viewer 自己的节点必须活着**
  //   (评审补: 离职/退出后节点被软删 → 四段全退, 不能继续看下层客户)
  return sql`(
    "customer"."deleted_at" IS NULL
    AND EXISTS (SELECT 1 FROM franchisee me_live
                WHERE me_live.id = ${viewer.franchiseeId} AND me_live.deleted_at IS NULL)
    AND (${segmentA} OR ${segmentB1} OR ${segmentB2} OR ${segmentC})
  )`;
}
