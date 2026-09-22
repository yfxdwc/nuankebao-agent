import { db } from "@/lib/db";
import { customer, wellnessRecord, followUpTask, interaction } from "@/lib/db/schema";
import { isNull, sql, eq, ne, and, gte, lt } from "drizzle-orm";
import { customerRbacFilter, type RbacContext } from "@/lib/auth/rbac";

// ============================================
// 仪表盘聚合查询
// 返回值已经全部转 number/string, 无 BigInt 序列化问题
// ============================================

export interface DashboardStats {
  customerCount: number;
  thisMonthVisits: number;
  pendingFollowUps: number;
  totalInteractions: number;
}

export async function getDashboardStats(): Promise<DashboardStats> {
  const now = new Date();
  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const firstStr = firstDayOfMonth.toISOString().split("T")[0];
  const nextStr = nextMonth.toISOString().split("T")[0];

  const [
    [{ customerCount }],
    [{ thisMonthVisits }],
    [{ pendingFollowUps }],
    [{ totalInteractions }],
  ] = await Promise.all([
    db
      .select({ customerCount: sql<number>`count(*)::int` })
      .from(customer)
      .where(isNull(customer.deletedAt)),
    db
      .select({ thisMonthVisits: sql<number>`count(*)::int` })
      .from(wellnessRecord)
      .where(
        and(
          gte(wellnessRecord.serviceDate, firstStr),
          lt(wellnessRecord.serviceDate, nextStr)
        )
      ),
    db
      .select({ pendingFollowUps: sql<number>`count(*)::int` })
      .from(followUpTask)
      .where(eq(followUpTask.status, "pending")),
    db
      .select({ totalInteractions: sql<number>`count(*)::int` })
      .from(interaction),
  ]);

  return {
    customerCount: Number(customerCount ?? 0),
    thisMonthVisits: Number(thisMonthVisits ?? 0),
    pendingFollowUps: Number(pendingFollowUps ?? 0),
    totalInteractions: Number(totalInteractions ?? 0),
  };
}

// ============================================
// 「数据概览」 (Flutter 「我的」页)
// ============================================
// 与 getDashboardStats 的区别 (不是同一个口径, 别混用):
//   - getDashboardStats: 4 个数字的**全库**汇总 (web admin 仪表盘用, 参数最少, 老路径不动)
//   - getStatsOverview: 同上 + 本月新增客户; 可选传 rbacCtx 收紧到「我看得到的客户」
//
// ⚠️ ctx 传不传 = 页面内数字自不自洽的分水岭:
//   Flutter 客户列表 (`GET /api/customers` → listCustomers) **目前没传 rbacCtx**,
//   即销售员看到的是**全库非软删客户**。所以「我的」页现在也传 null (同一口径),
//   否则客户列表写 47 条、「数据概览」写 6 条, 主人一眼以为数字坏了 (2026-09-18 拍)。
//   等客户列表接了行级过滤 (rbac.ts 里的 TODO 完结), 这里把 ctx 传进去即可 —— SQL 已经写好。
//
// 边界: 软删客户 (deleted_at) 一律不计入; **当前登录者自己的客户档案也不计入**
//   (自己不应该是自己的客户, 主人 2026-09-22 —— 必须与客户列表同一口径,
//    否则列表 47 条 / 概览 48 条, 主人一眼以为数字坏了)

export interface StatsOverview extends DashboardStats {
  /** 本月新建档的客户数 */
  newCustomersThisMonth: number;
}

export async function getStatsOverview(
  ctx: RbacContext | null,
  /** 当前登录者的手机号 hash → 排掉他自己的客户档案 (与客户列表同口径, 主人 2026-09-22) */
  opts: { excludePhoneHash?: string | null } = {}
): Promise<StatsOverview> {
  const now = new Date();
  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const firstStr = firstDayOfMonth.toISOString().split("T")[0];
  const nextStr = nextMonth.toISOString().split("T")[0];

  const filter = ctx ? customerRbacFilter(ctx) : undefined;
  const selfExclusion = opts.excludePhoneHash
    ? ne(customer.phoneHash, opts.excludePhoneHash)
    : undefined;
  // 三个条件取 AND: 未软删 + (可选) RBAC + (可选) 排掉自己
  const customerScope = and(isNull(customer.deletedAt), filter, selfExclusion);

  const [
    [{ customerCount }],
    [{ thisMonthVisits }],
    [{ pendingFollowUps }],
    [{ totalInteractions }],
    [{ newCustomersThisMonth }],
  ] = await Promise.all([
    db
      .select({ customerCount: sql<number>`count(*)::int` })
      .from(customer)
      .where(customerScope),
    db
      .select({ thisMonthVisits: sql<number>`count(*)::int` })
      .from(wellnessRecord)
      .innerJoin(customer, eq(wellnessRecord.customerId, customer.id))
      .where(
        and(
          gte(wellnessRecord.serviceDate, firstStr),
          lt(wellnessRecord.serviceDate, nextStr),
          customerScope
        )
      ),
    db
      .select({ pendingFollowUps: sql<number>`count(*)::int` })
      .from(followUpTask)
      .innerJoin(customer, eq(followUpTask.customerId, customer.id))
      .where(and(eq(followUpTask.status, "pending"), customerScope)),
    db
      .select({ totalInteractions: sql<number>`count(*)::int` })
      .from(interaction)
      .innerJoin(customer, eq(interaction.customerId, customer.id))
      .where(customerScope),
    db
      .select({ newCustomersThisMonth: sql<number>`count(*)::int` })
      .from(customer)
      .where(
        and(
          customerScope,
          gte(customer.createdAt, firstDayOfMonth),
          lt(customer.createdAt, nextMonth)
        )
      ),
  ]);

  return {
    customerCount: Number(customerCount ?? 0),
    thisMonthVisits: Number(thisMonthVisits ?? 0),
    pendingFollowUps: Number(pendingFollowUps ?? 0),
    totalInteractions: Number(totalInteractions ?? 0),
    newCustomersThisMonth: Number(newCustomersThisMonth ?? 0),
  };
}

export async function getServiceDistribution() {
  const now = new Date();
  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const firstStr = firstDayOfMonth.toISOString().split("T")[0];

  const rows = await db
    .select({
      serviceItemId: wellnessRecord.serviceItemId,
      count: sql<number>`count(*)::int`,
    })
    .from(wellnessRecord)
    .where(gte(wellnessRecord.serviceDate, firstStr))
    .groupBy(wellnessRecord.serviceItemId)
    .orderBy(sql`count desc`)
    .limit(5);

  return rows.map((r) => ({
    serviceItemId: r.serviceItemId.toString(),
    count: Number(r.count),
  }));
}