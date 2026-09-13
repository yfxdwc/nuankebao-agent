import { db } from "@/lib/db";
import { customer, wellnessRecord, followUpTask, interaction } from "@/lib/db/schema";
import { isNull, sql, eq, and, gte, lt } from "drizzle-orm";

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