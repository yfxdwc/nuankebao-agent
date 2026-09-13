import { db } from "@/lib/db";
import { wellnessRecord, customer } from "@/lib/db/schema";
import { sql, gte, lt, isNull, ne, and } from "drizzle-orm";

// ============================================
// 报表查询
// ============================================

/**
 * 最近 6 个月到店趋势
 * 返回: [{ month: "2026-04", count: 23 }, ...]
 */
export async function getMonthlyVisits() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - 5, 1);

  const rows = await db
    .select({
      month: sql<string>`to_char(${wellnessRecord.serviceDate}, 'YYYY-MM')`,
      count: sql<number>`count(*)::int`,
    })
    .from(wellnessRecord)
    .where(gte(wellnessRecord.serviceDate, sql`${start.toISOString().split("T")[0]}`))
    .groupBy(sql`to_char(${wellnessRecord.serviceDate}, 'YYYY-MM')`)
    .orderBy(sql`to_char(${wellnessRecord.serviceDate}, 'YYYY-MM')`);

  // 补齐缺失月份(返回连续 6 个月)
  const result: Array<{ month: string; count: number }> = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const monthStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
    const existing = rows.find((r) => r.month === monthStr);
    result.push({
      month: monthStr,
      count: Number(existing?.count ?? 0),
    });
  }
  return result;
}

/**
 * 客户复购周期分布
 * 计算每个客户相邻两次到店间隔(天)
 * 返回: [{ range: "0-30天", count: 5 }, ...]
 */
export async function getRepurchaseIntervals() {
  // 用 SQL 查每个客户的相邻间隔
  const result = await db.execute<{ interval_days: number }>(sql`
    WITH ordered AS (
      SELECT
        customer_id,
        service_date,
        LAG(service_date) OVER (PARTITION BY customer_id ORDER BY service_date) AS prev_date
      FROM wellness_record
    )
    SELECT
      (service_date - prev_date)::int AS interval_days
    FROM ordered
    WHERE prev_date IS NOT NULL
  `);

  const intervals = (result as unknown as Array<{ interval_days: number }>).map(
    (r) => Number(r.interval_days)
  );

  // 分桶
  const buckets = [
    { range: "0-30天", min: 0, max: 30, count: 0 },
    { range: "30-60天", min: 30, max: 60, count: 0 },
    { range: "60-90天", min: 60, max: 90, count: 0 },
    { range: "90-180天", min: 90, max: 180, count: 0 },
    { range: "180天以上", min: 180, max: Infinity, count: 0 },
  ];

  for (const interval of intervals) {
    const bucket = buckets.find((b) => interval >= b.min && interval < b.max);
    if (bucket) bucket.count++;
  }

  return buckets;
}

/**
 * 客户活跃度:新增 vs 回访 (本月)
 */
export async function getCustomerActivity() {
  const now = new Date();
  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const firstStr = firstDayOfMonth.toISOString().split("T")[0];

  // 本月到店的不同客户数
  const [{ activeCount }] = await db
    .select({ activeCount: sql<number>`COUNT(DISTINCT customer_id)::int` })
    .from(wellnessRecord)
    .where(gte(wellnessRecord.serviceDate, firstStr));

  // 本月新增客户数
  const [{ newCount }] = await db
    .select({ newCount: sql<number>`count(*)::int` })
    .from(customer)
    .where(
      and(
        gte(customer.createdAt, sql`${firstDayOfMonth.toISOString()}`),
        isNull(customer.deletedAt)
      )
    );

  // 历史客户总数(非本月新增)
  const [{ totalActive }] = await db
    .select({ totalActive: sql<number>`count(*)::int` })
    .from(customer)
    .where(isNull(customer.deletedAt));

  return {
    newCustomersThis: Number(newCount ?? 0),
    returningCustomers: Number(activeCount ?? 0),
    totalActiveCustomers: Number(totalActive ?? 0),
  };
}

/**
 * 综合报表数据
 */
export async function getOverviewReport() {
  const [monthlyVisits, intervals, activity] = await Promise.all([
    getMonthlyVisits(),
    getRepurchaseIntervals(),
    getCustomerActivity(),
  ]);

  return {
    monthlyVisits,
    repurchaseIntervals: intervals,
    customerActivity: activity,
  };
}