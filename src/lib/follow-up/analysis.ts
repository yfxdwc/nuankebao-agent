// ============================================
// 客户跟进分析 (客户详情页「跟进分析」卡; 方案 §7.1)
// ============================================
// 主人 2026-09-20 拍板: 客观指标**免费**, AI 解读**会员** (方案 §11 判权表)。
//   免费: 近 30/90 天联系次数 · 平均联系间隔 · 趋势 · 到店规律 · 复购间隔 · 未完成跟进任务
//   会员: 一句话建议 + 开场话术 (走既有 POST /api/ai/follow-up, 本模块不掺 AI)
//
// 设计: 指标计算是**纯函数** (buildFollowUpAnalysis) → 可单测;
//       SQL 只负责把原始日期捞出来 (loadFollowUpAnalysis)。

import { and, desc, eq, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { customer, followUpTask, interaction, wellnessRecord } from "@/lib/db/schema";
import { daysBetween } from "@/lib/follow-up/urgency";

export type FollowUpTrend = "warmer" | "colder" | "steady" | "unknown";

export interface FollowUpAnalysis {
  // --- 联系 (interaction) ---
  /** 近 30 天联系次数 (今天起往前 30 个日历天) */
  contactLast30: number;
  /** 近 90 天联系次数 (今天起往前 90 个日历天) */
  contactLast90: number;
  /** 历史联系总次数 */
  contactTotal: number;
  /** 平均联系间隔 (中位数, 天); null = 少于 2 次联系 */
  avgContactIntervalDays: number | null;
  /** 上次联系距今天数; null = 从没联系过 */
  daysSinceLastContact: number | null;
  // --- 趋势 ---
  trend: FollowUpTrend;
  trendText: string;
  // --- 到店 (wellness_record) ---
  visitCount: number;
  avgVisitIntervalDays: number | null;
  lastVisitAt: string | null;
  daysSinceLastVisit: number | null;
  /** 复购间隔中位数 (天) —— 与到店间隔同源, 但取中位数 (抗异常值) */
  medianRepurchaseIntervalDays: number | null;
  // --- 跟进任务 ---
  pendingTasks: number;
  overdueTasks: number;
  /** 最久的逾期天数 */
  oldestOverdueDays: number | null;
  // --- 免费的一句话总结 (纯规则, 不调 AI) ---
  headline: string;
}

export interface AnalysisInput {
  /** 互动时间 (任意顺序) */
  interactionDates: Date[];
  /** 到店日期 (任意顺序) */
  visitDates: Date[];
  /** 未完成跟进任务的到期时间 */
  openTaskDueAts: Date[];
  now: Date;
}

/** 中位数 (偶数个取中间两个的平均) */
export function median(nums: number[]): number | null {
  if (nums.length === 0) return null;
  const sorted = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[mid]
    : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

/** 相邻日期间隔 (天), 输入需升序 */
function intervals(datesAsc: Date[]): number[] {
  const out: number[] = [];
  for (let i = 1; i < datesAsc.length; i++) {
    out.push(daysBetween(datesAsc[i - 1], datesAsc[i]));
  }
  return out;
}

/** 趋势判定: 最近 3 个间隔的中位数 vs 全历史中位数 (方案 §7.1) */
const TREND_RATIO = 1.25;
const TREND_MIN_INTERVALS = 4; // 少于 4 个间隔看不出趋势 (最近 3 + 至少 1 个历史)

function computeTrend(allIntervals: number[]): { trend: FollowUpTrend; text: string } {
  if (allIntervals.length < TREND_MIN_INTERVALS) {
    return { trend: "unknown", text: "联系还不够多, 看不出趋势" };
  }
  const base = median(allIntervals);
  const recent = median(allIntervals.slice(-3));
  if (base == null || recent == null || base === 0) {
    return { trend: "unknown", text: "联系还不够多, 看不出趋势" };
  }
  if (recent >= Math.round(base * TREND_RATIO)) {
    return { trend: "colder", text: `在变冷 (${base} → ${recent} 天)` };
  }
  if (recent <= Math.round(base / TREND_RATIO)) {
    return { trend: "warmer", text: `在变热 (${base} → ${recent} 天)` };
  }
  return { trend: "steady", text: `节奏稳定 (约 ${base} 天一次)` };
}

/** 纯函数: 由原始日期算全部客观指标 (可单测) */
export function buildFollowUpAnalysis(input: AnalysisInput): FollowUpAnalysis {
  const { now } = input;

  const contactsAsc = [...input.interactionDates].sort((a, b) => a.getTime() - b.getTime());
  const visitsAsc = [...input.visitDates].sort((a, b) => a.getTime() - b.getTime());

  const contactIntervals = intervals(contactsAsc);
  const visitIntervals = intervals(visitsAsc);

  // 窗口口径: 「近 N 天」= 今天起往前 N 个日历天 (含今天) → 距今天数 < N
  //   (第 N 天前的那次不算, 否则 30 天窗口实际覆盖 31 天, 边界容易看不懂)
  const contactLast30 = contactsAsc.filter((d) => daysBetween(d, now) < 30).length;
  const contactLast90 = contactsAsc.filter((d) => daysBetween(d, now) < 90).length;

  const lastContact = contactsAsc[contactsAsc.length - 1] ?? null;
  const lastVisit = visitsAsc[visitsAsc.length - 1] ?? null;

  const open = input.openTaskDueAts
    .map((d) => daysBetween(d, now))
    .filter((d) => d > 0);

  const { trend, text: trendText } = computeTrend(contactIntervals);

  const daysSinceLastContact = lastContact ? Math.max(0, daysBetween(lastContact, now)) : null;
  const daysSinceLastVisit = lastVisit ? Math.max(0, daysBetween(lastVisit, now)) : null;
  const avgContactIntervalDays = median(contactIntervals);
  const avgVisitIntervalDays = median(visitIntervals);
  const medianRepurchaseIntervalDays = median(visitIntervals);

  const result: FollowUpAnalysis = {
    contactLast30,
    contactLast90,
    contactTotal: contactsAsc.length,
    avgContactIntervalDays,
    daysSinceLastContact,
    trend,
    trendText,
    visitCount: visitsAsc.length,
    avgVisitIntervalDays,
    lastVisitAt: lastVisit ? lastVisit.toISOString() : null,
    daysSinceLastVisit,
    medianRepurchaseIntervalDays,
    pendingTasks: input.openTaskDueAts.length,
    overdueTasks: open.length,
    oldestOverdueDays: open.length > 0 ? Math.max(...open) : null,
    headline: "",
  };
  result.headline = buildHeadline(result);
  return result;
}

/** 一句话总结 (免费层; 会员的 AI 解读另外接 POST /api/ai/follow-up) */
function buildHeadline(a: FollowUpAnalysis): string {
  if (a.contactTotal === 0) {
    return a.visitCount > 0
      ? `到店过 ${a.visitCount} 次, 但还没有联系记录`
      : "还没有联系和到店记录, 建议先认识一下";
  }

  const parts: string[] = [];
  parts.push(
    a.daysSinceLastContact === 0
      ? "今天联系过"
      : `已 ${a.daysSinceLastContact} 天没联系`
  );
  if (a.avgContactIntervalDays != null) {
    parts.push(`平均 ${a.avgContactIntervalDays} 天联系一次`);
  }
  if (a.trend === "colder" || a.trend === "warmer") {
    parts.push(a.trendText);
  }
  if (a.overdueTasks > 0) {
    parts.push(`${a.overdueTasks} 条跟进任务逾期 ${a.oldestOverdueDays} 天`);
  } else if (a.pendingTasks > 0) {
    parts.push(`${a.pendingTasks} 条待办跟进`);
  }
  return parts.join(" · ");
}

/**
 * 查一个客户的跟进分析 (DB 版)
 * @returns null = 客户不存在 / 已删除
 */
export async function loadFollowUpAnalysis(
  customerId: bigint,
  now: Date = new Date()
): Promise<FollowUpAnalysis | null> {
  const [cust] = await db
    .select({ id: customer.id })
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);
  if (!cust) return null;

  const [contactRows, visitRows, taskRows] = await Promise.all([
    db
      .select({ createdAt: interaction.createdAt })
      .from(interaction)
      .where(eq(interaction.customerId, customerId))
      .orderBy(desc(interaction.createdAt))
      .limit(200),
    db
      .select({ serviceDate: wellnessRecord.serviceDate })
      .from(wellnessRecord)
      .where(eq(wellnessRecord.customerId, customerId))
      .orderBy(desc(wellnessRecord.serviceDate))
      .limit(200),
    db
      .select({ dueAt: followUpTask.dueAt })
      .from(followUpTask)
      .where(
        and(eq(followUpTask.customerId, customerId), eq(followUpTask.status, "pending"))
      ),
  ]);

  return buildFollowUpAnalysis({
    interactionDates: contactRows.map((r) => r.createdAt),
    visitDates: visitRows.map((r) => new Date(String(r.serviceDate))),
    openTaskDueAts: taskRows.map((r) => r.dueAt),
    now,
  });
}
