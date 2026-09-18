import { db } from "@/lib/db";
import { customer, wellnessRecord, followUpTask, interaction } from "@/lib/db/schema";
import { isNull, sql, eq, and, gte, lt } from "drizzle-orm";
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
// 「我的数据」 (Flutter 「我的」页)
// ============================================
// 与 getDashboardStats 的区别 (不是同一个口径, 别混用):
//   - getDashboardStats: **全库**汇总 (web admin 仪表盘用, 无 RBAC)
//   - getMyStats: **当前登录者看得到的**数据 (同客户列表的 RBAC 口径)
//     —— 「我的」页写的是「我的数据」, 给销售员看全库数字 = 误导
//
// 过滤口径: 一律 join customer + customerRbacFilter(ctx)
//   (养生记录 / 互动 / 跟进任务都没有自己的 store_id, 只能从客户侧过滤)
//   admin → filter undefined → 全量 (同旧行为); manager → 本店; sales → 自己创建 + 同店
// 边界: 软删客户 (deleted_at) 一律不计入

export interface MyStats extends DashboardStats {
  /** 本月新建档的客户数 */
  newCustomersThisMonth: number;
}

export async function getMyStats(ctx: RbacContext): Promise<MyStats> {
  const now = new Date();
  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const firstStr = firstDayOfMonth.toISOString().split("T")[0];
  const nextStr = nextMonth.toISOString().split("T")[0];

  const filter = customerRbacFilter(ctx);
  const customerScope = and(isNull(customer.deletedAt), filter);

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