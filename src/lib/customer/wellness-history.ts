// ============================================
// 客户养生记录 —— 共享 loader
// ============================================
//
// 单一真相源: 取一个客户的**最近 N 条**养生记录 (serviceDate DESC), 并把加密字段
// 解密 + JSON.parse 后的结构化快照一并返回。
//
// 共用方:
//   - src/lib/customer/charts.ts::loadCustomerCharts
//   - src/lib/customer/scoring.ts::loadCustomerScoringSnapshot
//
// 历史: 两处原本各自复制「查最近 200 条 + decryptField + safeParse」, 排序口径还
//   漂移过 —— charts 取**最早** 200 条 (bug, 趋势图看的是最老的样本), scoring 取最近 200 条。
//   本 loader 统一为「**最近 limit 条**」(serviceDate DESC), charts / scoring 都按
//   这条口径取, 调用方内部再按各自需要 sort。charts 那一处此前实为 bug, 见 charts.ts 注释。
//
// ⚠ 解析失败宽容语义: 解密 / JSON.parse 任一失败 → 返回 {}, 与原两处复制版一致。
//   趋势图 / 评分都不该因为一条坏记录整体炸掉。
// ============================================

import { desc, eq } from "drizzle-orm";

import { db } from "@/lib/db";
import { wellnessRecord } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";

export interface RecentWellnessRow {
  id: bigint;
  serviceDate: Date;
  pre: Record<string, unknown>;
  post: Record<string, unknown>;
}

/**
 * 加载一个客户的**最近 limit 条**养生记录 (默认 200), 已解密 + JSON.parse。
 *
 * 排序: serviceDate DESC, id DESC (id 作 tiebreaker 保证分页/取样确定性)。
 * 返回的 pre / post 永远是 Record<string, unknown> (解析失败时退化为 {})。
 */
export async function loadRecentWellnessParsed(
  customerId: bigint,
  limit = 200,
): Promise<RecentWellnessRow[]> {
  const rows = await db
    .select({
      id: wellnessRecord.id,
      serviceDate: wellnessRecord.serviceDate,
      pre: wellnessRecord.preConditionEncrypted,
      post: wellnessRecord.postConditionEncrypted,
    })
    .from(wellnessRecord)
    .where(eq(wellnessRecord.customerId, customerId))
    .orderBy(desc(wellnessRecord.serviceDate), desc(wellnessRecord.id))
    .limit(limit);

  return rows.map((r) => ({
    id: r.id,
    serviceDate: new Date(String(r.serviceDate)),
    pre: safeParse(r.pre),
    post: safeParse(r.post),
  }));
}

function safeParse(cipher: string | null): Record<string, unknown> {
  if (!cipher) return {};
  try {
    return JSON.parse(decryptField(cipher)) as Record<string, unknown>;
  } catch {
    return {};
  }
}