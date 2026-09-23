import { db } from "@/lib/db";
import { customer, wellnessRecord } from "@/lib/db/schema";
import { eq, and, isNull, desc, sql } from "drizzle-orm";

// ============================================
// 复购预测: 基于历史间隔, 算下次预计到店
// 不调 LLM, 纯 SQL 计算
// ============================================

export interface RepurchasePrediction {
  customerId: string;
  customerName: string;
  lastVisit: string | null;
  daysSinceLastVisit: number | null;
  avgIntervalDays: number | null;
  predictedNextVisit: string | null;  // YYYY-MM-DD
  daysUntilPredicted: number | null;
  confidence: "high" | "medium" | "low";
  reason: string;
}

/**
 * 计算复购预测
 * 算法:
 *   - 取最近 5 次到店间隔 (LAG)
 *   - 算平均间隔
 *   - 预测下次 = 上次到店 + 平均间隔
 *   - 置信度: ≥3 条历史 → high, 2 条 → medium, 1/0 → low
 */
export async function predictRepurchase(
  customerId: bigint
): Promise<RepurchasePrediction | null> {
  const [cust] = await db
    .select()
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);

  if (!cust) return null;

  // 取最近 10 次到店
  const records = await db
    .select({ serviceDate: wellnessRecord.serviceDate })
    .from(wellnessRecord)
    .where(eq(wellnessRecord.customerId, customerId))
    .orderBy(desc(wellnessRecord.serviceDate))
    .limit(10);

  if (records.length === 0) {
    return {
      customerId: customerId.toString(),
      customerName: cust.name,
      lastVisit: null,
      daysSinceLastVisit: null,
      avgIntervalDays: null,
      predictedNextVisit: null,
      daysUntilPredicted: null,
      confidence: "low",
      reason: "暂无到店记录,无法预测",
    };
  }

  const lastDate = new Date(String(records[0].serviceDate));
  const daysSince = Math.floor(
    (Date.now() - lastDate.getTime()) / (1000 * 60 * 60 * 24)
  );

  // 算平均间隔
  let avgInterval: number | null = null;
  if (records.length >= 2) {
    const result = await db.execute<{ avg_days: number }>(sql`
      WITH ordered AS (
        SELECT
          service_date,
          LAG(service_date) OVER (ORDER BY service_date) AS prev_date
        FROM wellness_record
        WHERE customer_id = ${customerId.toString()}
      )
      SELECT AVG(service_date - prev_date)::float AS avg_days
      FROM ordered
      WHERE prev_date IS NOT NULL
    `);
    const r = result as unknown as Array<{ avg_days: number | null }>;
    if (r[0]?.avg_days != null) {
      avgInterval = Math.round(Number(r[0].avg_days));
    }
  }

  // 预测下次
  let predictedNextVisit: string | null = null;
  let daysUntilPredicted: number | null = null;
  if (avgInterval !== null) {
    const predicted = new Date(lastDate);
    predicted.setDate(predicted.getDate() + avgInterval);
    predictedNextVisit = predicted.toISOString().split("T")[0];
    daysUntilPredicted = Math.floor(
      (predicted.getTime() - Date.now()) / (1000 * 60 * 60 * 24)
    );
  }

  // 置信度
  const confidence: "high" | "medium" | "low" =
    records.length >= 3 ? "high" : records.length === 2 ? "medium" : "low";

  // 建议
  let reason: string;
  if (avgInterval === null) {
    reason = "只有 1 次到店,无法预测复购周期";
  } else if (daysUntilPredicted === null) {
    reason = `平均 ${avgInterval} 天复购,建议联系`;
  } else if (daysUntilPredicted < 0) {
    reason = `已超过平均复购周期 ${Math.abs(daysUntilPredicted)} 天,建议尽快跟进`;
  } else if (daysUntilPredicted < 7) {
    reason = `预计 ${daysUntilPredicted} 天内会复购,可主动联系`;
  } else {
    reason = `距离下次复购还有 ${daysUntilPredicted} 天`;
  }

  return {
    customerId: customerId.toString(),
    customerName: cust.name,
    lastVisit: String(records[0].serviceDate),
    daysSinceLastVisit: daysSince,
    avgIntervalDays: avgInterval,
    predictedNextVisit,
    daysUntilPredicted,
    confidence,
    reason,
  };
}
