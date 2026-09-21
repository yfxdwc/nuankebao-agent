// ============================================
// 复购窗口 (列表用; 会员功能 — ADR-0012 ai.repurchase)
// ============================================
// 算法与 lib/ai/predictions.ts 一致 (最近 10 次到店的间隔平均 → 上次到店 + 平均间隔 = 预计复购日),
// 但**批量**: 一次 SQL 算完一整页客户 (列表 50 行不能打 50 次查询)。
//
// 产出: Map<customerId, 复购窗口>
//   windowOpenedAt = 预计复购日 (已到 = 窗口开; 未到 = null → 引擎里天然不参与)
// 只给会员算 (route 层判权), 非会员不传 Map → 引擎里 repurchase = null
//
// 设计 (同 urgency.ts): 打分逻辑是**纯函数** (computeRepurchaseWindow), SQL 只负责取数据

import { sql } from "drizzle-orm";

import { db } from "@/lib/db";

/** 采样到店次数 (与 predictions.ts 的 `limit(10)` 对齐) */
export const REPURCHASE_SAMPLE = 10;

export interface RepurchaseWindow {
  /** 预计复购日**已到** → 窗口开启; 未到 → null (不参与紧急度) */
  windowOpenedAt: Date | null;
  /** 预计复购日 (不管到没到; 详情页展示用) */
  expectedAt: Date | null;
  /** 历史平均到店间隔 (天) */
  avgIntervalDays: number | null;
  /** 上次到店 */
  lastVisitAt: Date;
  /** 到店次数 ≥3 高 / 2 中 / 1 低 (与 predictions.ts 口径一致) */
  confidence: "high" | "medium" | "low";
  /** 参与计算的到店次数 */
  visitCount: number;
}

/**
 * 纯函数: 由到店日期列表算复购窗口 (可单测)
 *   - 只取最近 REPURCHASE_SAMPLE 次
 *   - 间隔 = 相邻到店日差额 (天), 平均后四舍五入 (与 predictions.ts 的 Math.round 一致)
 *   - 预计复购日 = 上次到店 + 平均间隔
 */
export function computeRepurchaseWindow(
  visitDates: Date[],
  now: Date
): RepurchaseWindow | null {
  if (visitDates.length === 0) return null;

  const asc = [...visitDates].sort((a, b) => a.getTime() - b.getTime());
  const sample = asc.slice(-REPURCHASE_SAMPLE);
  const lastVisitAt = sample[sample.length - 1];
  const visitCount = sample.length;

  let avgIntervalDays: number | null = null;
  if (visitCount >= 2) {
    let sum = 0;
    for (let i = 1; i < visitCount; i++) {
      sum += Math.round(
        (sample[i].getTime() - sample[i - 1].getTime()) / 86_400_000
      );
    }
    avgIntervalDays = Math.round(sum / (visitCount - 1));
  }

  let expectedAt: Date | null = null;
  let windowOpenedAt: Date | null = null;
  if (avgIntervalDays != null && avgIntervalDays > 0) {
    expectedAt = new Date(lastVisitAt.getTime() + avgIntervalDays * 86_400_000);
    if (expectedAt.getTime() <= now.getTime()) windowOpenedAt = expectedAt;
  }

  return {
    windowOpenedAt,
    expectedAt,
    avgIntervalDays,
    lastVisitAt,
    confidence: visitCount >= 3 ? "high" : visitCount === 2 ? "medium" : "low",
    visitCount,
  };
}

/**
 * 批量算复购窗口 (一次 SQL 取所有客户的到店日期, 再各自跑纯函数)
 * @param customerIds 本页/本批客户 id (空数组 = 直接返回空 Map)
 * @param now 参考时间 (默认当前; 单测可注入)
 */
export async function batchRepurchaseWindows(
  customerIds: bigint[],
  now: Date = new Date()
): Promise<Map<string, RepurchaseWindow>> {
  const out = new Map<string, RepurchaseWindow>();
  if (customerIds.length === 0) return out;

  // 一次 SQL: 取每个客户最近 REPURCHASE_SAMPLE 次到店日期
  const rows = await db.execute<{ customer_id: string; service_date: string }>(sql`
    SELECT customer_id, service_date
    FROM (
      SELECT customer_id, service_date,
             ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY service_date DESC) AS rn
      FROM wellness_record
      WHERE customer_id IN ${sql.raw(
        `(${customerIds.map((id) => id.toString()).join(",")})`
      )}
    ) t
    WHERE rn <= ${REPURCHASE_SAMPLE}
    ORDER BY customer_id, service_date
  `);

  const byCustomer = new Map<string, Date[]>();
  for (const r of rows) {
    const key = String(r.customer_id);
    const arr = byCustomer.get(key) ?? [];
    arr.push(new Date(r.service_date));
    byCustomer.set(key, arr);
  }

  for (const [key, dates] of byCustomer) {
    const w = computeRepurchaseWindow(dates, now);
    if (w != null) out.set(key, w);
  }
  return out;
}
