// ============================================
// 客户分析图谱 —— 数据层 (纯函数 + loader)
// ============================================
//
// 主人 2026-09-23 拍板 P4。给「分析」Tab 供三张图的数据:
//   ① 三维雷达图   —— 不在这里算: 直接用 scoring.ts 的 effect/engagement/value
//   ② 效果趋势线   —— trend: 每次记录的 pain/sleep 前→后, 按时间正序
//   ③ 部位热力条   —— bodyParts: 哪些部位反复出问题 + 该部位的止痛效果
//
// 为什么单独一个端点而不是塞进 /insight:
//   L0 的评分环 + 待办区要**快** (详情页一打开就要显示)。
//   趋势/部位是「点开分析 Tab 才看」的, 拆开可以让 L0 只查少数字段,
//   也避免详情页首屏被无关的聚合查询拖慢。
//
// 分层同 analysis.ts / scoring.ts: buildXxx 是纯函数 (可单测), loadXxx 只负责捞数据。
//
// ⚠ 免责边界 (CHARTER §1.3 不做医疗诊断): 这里只做**描述性统计**
//   (出现次数 / 疼痛下降幅度中位数)。不给"这个部位该用什么方案"之类结论 ——
//   那是技师/店长的判断, 不是系统的。
// ============================================

import { and, asc, eq, inArray, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { bodyPart, customer, wellnessRecord, wellnessRecordBodyPart } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";
import { median } from "@/lib/follow-up/analysis";

// ============================================
// 类型
// ============================================

/** 趋势图上的一个点 (一次记录) */
export interface TrendPoint {
  date: string; // YYYY-MM-DD
  prePain: number | null;
  postPain: number | null;
  preSleep: number | null;
  postSleep: number | null;
}

/** 一个身体部位的统计 */
export interface BodyPartStat {
  id: string;
  name: string;
  /** 出现在几条记录里 */
  count: number;
  /**
   * 这些记录里"疼痛下降"的中位数 (正 = 有改善)。
   * null = 该部位的记录都没同时填前后疼痛 → 无法判断。
   * 用中位数而不是均值: 防单次异常值 (同 analysis.ts 的 medianRepurchaseInterval 口径)
   */
  medianPainDrop: number | null;
}

export interface CustomerCharts {
  /** 时间正序 (老的在前), 最多 recentLimit 条 */
  trend: TrendPoint[];
  /** 按出现次数降序 */
  bodyParts: BodyPartStat[];
  /** 带评分的记录条数 (前端判断"样本够不够画图") */
  scoredRecordCount: number;
  /** 记录总数 */
  recordCount: number;
}

// ============================================
// 纯函数
// ============================================

export interface ChartsRecordInput {
  serviceDate: Date;
  pre: Record<string, unknown>;
  post: Record<string, unknown>;
  bodyPartIds: string[];
}

export interface ChartsInput {
  records: ChartsRecordInput[];
  /** bodyPartId → 名称 (来自字典; 查不到的用 "#id" 兜底) */
  bodyPartNames: Map<string, string>;
  /** 趋势图最多画几个点 (多了挤在一起看不清) */
  trendLimit?: number;
}

const DEFAULT_TREND_LIMIT = 10;

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

export function buildCustomerCharts(input: ChartsInput): CustomerCharts {
  const limit = input.trendLimit ?? DEFAULT_TREND_LIMIT;

  // 记录按日期正序 (老的在前 → 折线从左到右是时间流)
  const asc_ = [...input.records].sort(
    (a, b) => a.serviceDate.getTime() - b.serviceDate.getTime(),
  );

  // ── ① 趋势: 只保留"至少有一个评分"的记录, 再取最近 limit 条 ──
  const scored = asc_.filter((r) => {
    const hasPre = num(r.pre.pain_level) !== null || num(r.pre.sleep_quality) !== null;
    const hasPost = num(r.post.pain_level) !== null || num(r.post.sleep_quality) !== null;
    return hasPre || hasPost;
  });
  const trend: TrendPoint[] = scored.slice(-limit).map((r) => ({
    date: r.serviceDate.toISOString().slice(0, 10),
    prePain: num(r.pre.pain_level),
    postPain: num(r.post.pain_level),
    preSleep: num(r.pre.sleep_quality),
    postSleep: num(r.post.sleep_quality),
  }));

  // ── ② 部位统计: 次数 + 止痛中位数 ──
  const acc = new Map<string, { count: number; drops: number[] }>();
  for (const r of asc_) {
    const pre = num(r.pre.pain_level);
    const post = num(r.post.pain_level);
    const drop = pre !== null && post !== null ? pre - post : null;
    for (const id of r.bodyPartIds) {
      const cur = acc.get(id) ?? { count: 0, drops: [] };
      cur.count += 1;
      if (drop !== null) cur.drops.push(drop);
      acc.set(id, cur);
    }
  }
  const bodyParts: BodyPartStat[] = [...acc.entries()]
    .map(([id, v]) => ({
      id,
      name: input.bodyPartNames.get(id) ?? `#${id}`,
      count: v.count,
      medianPainDrop: v.drops.length > 0 ? median(v.drops) : null,
    }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));

  return {
    trend,
    bodyParts,
    scoredRecordCount: scored.length,
    recordCount: input.records.length,
  };
}

// ============================================
// Loader
// ============================================

export async function loadCustomerCharts(
  customerId: bigint,
  opts: { trendLimit?: number } = {},
): Promise<CustomerCharts | null> {
  const [cust] = await db
    .select({ id: customer.id })
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);
  if (!cust) return null;

  // 记录 (只取画图需要的字段; 按日期正序便于直接聚合)
  const rows = await db
    .select({
      id: wellnessRecord.id,
      serviceDate: wellnessRecord.serviceDate,
      pre: wellnessRecord.preConditionEncrypted,
      post: wellnessRecord.postConditionEncrypted,
    })
    .from(wellnessRecord)
    .where(eq(wellnessRecord.customerId, customerId))
    .orderBy(asc(wellnessRecord.serviceDate), asc(wellnessRecord.id))
    .limit(200);

  if (rows.length === 0) {
    return { trend: [], bodyParts: [], scoredRecordCount: 0, recordCount: 0 };
  }

  const ids = rows.map((r) => r.id);

  // 部位关联 + 部位字典 (一条 join 查完, 避免 N+1)
  const links = await db
    .select({
      recordId: wellnessRecordBodyPart.wellnessRecordId,
      bodyPartId: wellnessRecordBodyPart.bodyPartId,
      name: bodyPart.name,
    })
    .from(wellnessRecordBodyPart)
    .innerJoin(bodyPart, eq(bodyPart.id, wellnessRecordBodyPart.bodyPartId))
    .where(inArray(wellnessRecordBodyPart.wellnessRecordId, ids));

  const byRecord = new Map<string, string[]>();
  const names = new Map<string, string>();
  for (const l of links) {
    const rid = String(l.recordId);
    byRecord.set(rid, [...(byRecord.get(rid) ?? []), String(l.bodyPartId)]);
    names.set(String(l.bodyPartId), l.name);
  }

  return buildCustomerCharts({
    records: rows.map((r) => ({
      serviceDate: new Date(String(r.serviceDate)),
      pre: safeParse(r.pre),
      post: safeParse(r.post),
      bodyPartIds: byRecord.get(String(r.id)) ?? [],
    })),
    bodyPartNames: names,
    trendLimit: opts.trendLimit,
  });
}

function safeParse(cipher: string | null): Record<string, unknown> {
  if (!cipher) return {};
  try {
    return JSON.parse(decryptField(cipher)) as Record<string, unknown>;
  } catch {
    return {};
  }
}
