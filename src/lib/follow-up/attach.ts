// ============================================
// 客户列表: 跟进信息挂载 + 紧急度排序 (主人 2026-09-20 拍)
// ============================================
// 口径 (Q1-Q8 拍板):
//   - 紧急度**排序** = 会员功能 (非会员: 排序降级为「最近添加」, 但基本信息/标签照给)
//   - 标签最多 2 个 (动作 + 日历), 走「动作」文案
//   - 分数/级别/标签一律服务端算 (单一真相: lib/follow-up/urgency.ts)
//
// ⚠ 规模说明 (方案 §13 风险表):
//   紧急度排序需要在"全部命中客户"上排序, 再切片分页 —— 当前实现是**内存排序**
//   (上限 SAFETY_LIMIT 条)。客户量到万级时改为 SQL CASE 表达式 + 索引排序 (常量已抽在 urgency.ts)。

import { and, eq, inArray, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { followUpTask } from "@/lib/db/schema";
import { solarBirthdayWindow } from "@/lib/follow-up/birthday";
import type { RepurchaseWindow } from "@/lib/follow-up/repurchase";
import {
  computeUrgency,
  pickFollowUpTags,
  type FollowUpTag,
  type UrgencyResult,
} from "@/lib/follow-up/urgency";

/** 内存排序的安全上限 (超过就只在这些里排; 见文件头规模说明) */
export const URGENCY_SAFETY_LIMIT = 2000;

export interface FollowUpUpdatable {
  id: string;
  createdAt: Date;
  customerType: "franchisee" | "seed" | "normal";
  lastInteractionAt?: Date | null;
  lastVisitAt?: Date | null;
  birthMonth?: number | null;
  birthDay?: number | null;
  birthCalendar?: string;
  birthdayRemindDays?: number | null;
}

export interface FollowUpBlock {
  /** 距上次联系 (天); null = 从没联系过 */
  daysSinceContact: number | null;
  lastContactAt: string | null;
  lastContactType: string | null;
  daysSinceVisit: number | null;
  lastVisitAt: string | null;
  openTaskCount: number;
  nextDueAt: string | null;
  /** 标签 (免费档只有非会员标签) */
  tags: FollowUpTag[];
  /** 复购窗口 (仅会员; 免费档为 null) */
  repurchase: RepurchaseInfo | null;
  /** 以下仅会员 (非会员为 null → 不下发分数, 避免"半开"体验) */
  urgency: number | null;
  level: UrgencyResult["level"] | null;
  levelLabel: string | null;
  reason: string | null;
}

export interface RepurchaseInfo {
  /** 预计复购日 (窗口已开才非 null) */
  windowOpenedAt: string | null;
  /** 预计复购日 (不管到没到) */
  expectedAt: string | null;
  /** 历史平均到店间隔 (天) */
  avgIntervalDays: number | null;
  confidence: "high" | "medium" | "low";
}

export interface AttachOptions {
  isMember: boolean;
  now?: Date;
  /** 上一次互动类型 (电话/微信…), 由调用方按需补; 缺省 null */
  lastInteractionTypes?: Map<string, string>;
  /** 复购窗口 (仅会员; 由 route 层 batchRepurchaseWindows 算好传进来) */
  repurchaseWindows?: Map<string, RepurchaseWindow>;
}

/** 批量取「待办跟进任务」→ Map<customerId, dueAt[]> */
async function loadOpenTasks(customerIds: bigint[]): Promise<Map<string, Date[]>> {
  const out = new Map<string, Date[]>();
  if (customerIds.length === 0) return out;
  const rows = await db
    .select({ customerId: followUpTask.customerId, dueAt: followUpTask.dueAt })
    .from(followUpTask)
    .where(
      and(
        eq(followUpTask.status, "pending"),
        inArray(followUpTask.customerId, customerIds)
      )
    );
  for (const r of rows) {
    const key = r.customerId.toString();
    const arr = out.get(key) ?? [];
    arr.push(r.dueAt);
    out.set(key, arr);
  }
  return out;
}

/** 批量取「最近一次互动类型」→ Map<customerId, type> (第二行文案「· 上次电话」用) */
async function loadLastInteractionTypes(
  customerIds: bigint[]
): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (customerIds.length === 0) return out;
  const rows = await db.execute<{ customer_id: string; type: string }>(sql`
    SELECT customer_id, type
    FROM (
      SELECT customer_id, type,
             ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at DESC) AS rn
      FROM interaction
      WHERE customer_id IN ${sql.raw(
        `(${customerIds.map((id) => id.toString()).join(",")})`
      )}
    ) t
    WHERE rn = 1
  `);
  for (const r of rows) out.set(String(r.customer_id), String(r.type));
  return out;
}

/**
 * 给客户列表挂上 `followUp` 块 (原地返回新数组, 不 mutate 入参)
 * 入参 items 需要带 id / createdAt / customerType / lastInteraction* / lastVisit* / 生日字段
 */
export async function attachFollowUp<T extends FollowUpUpdatable>(
  items: T[],
  opts: AttachOptions
): Promise<Array<T & { followUp: FollowUpBlock }>> {
  const now = opts.now ?? new Date();
  const ids = items.map((i) => BigInt(i.id));
  const tasks = await loadOpenTasks(ids);
  // 调用方没传就自己查 (第二行「· 上次电话」需要; 不传则这个字段永远是 null)
  const types =
    opts.lastInteractionTypes ?? (await loadLastInteractionTypes(ids));

  return items.map((item) => {
    const dueAts = tasks.get(item.id) ?? [];
    const birthday = solarBirthdayWindow(
      item.birthMonth ?? null,
      item.birthDay ?? null,
      item.birthCalendar ?? "solar",
      item.birthdayRemindDays ?? null,
      now
    );
    // 生日提醒是会员功能 (ADR-0012): 非会员不参与紧急度/标签
    const birthdayForCalc = opts.isMember ? birthday : null;
    // 复购窗口同理: 非会员不传 Map → 这里恒 null (天然不参与)
    const rp = opts.isMember ? opts.repurchaseWindows?.get(item.id) ?? null : null;

    const result = computeUrgency({
      customerType: item.customerType,
      createdAt: item.createdAt,
      lastInteractionAt: item.lastInteractionAt ?? null,
      lastVisitAt: item.lastVisitAt ?? null,
      openTaskDueAts: dueAts,
      birthday: birthdayForCalc,
      repurchase: rp,
      now,
    });

    const allTags = pickFollowUpTags(result, {
      birthday: birthdayForCalc,
      repurchase: rp,
    });
    const tags = opts.isMember ? allTags : allTags.filter((t) => !t.memberOnly);

    const sortedDue = [...dueAts].sort((a, b) => a.getTime() - b.getTime());
    const block: FollowUpBlock = {
      daysSinceContact: result.daysSinceContact,
      lastContactAt: item.lastInteractionAt
        ? item.lastInteractionAt.toISOString()
        : null,
      lastContactType: types.get(item.id) ?? null,
      daysSinceVisit: result.daysSinceVisit,
      lastVisitAt: item.lastVisitAt ? item.lastVisitAt.toISOString() : null,
      openTaskCount: dueAts.length,
      nextDueAt: sortedDue[0]?.toISOString() ?? null,
      tags,
      repurchase:
        rp == null
          ? null
          : {
              windowOpenedAt: rp.windowOpenedAt?.toISOString() ?? null,
              expectedAt: rp.expectedAt?.toISOString() ?? null,
              avgIntervalDays: rp.avgIntervalDays,
              confidence: rp.confidence,
            },
      // 会员才下发分数/级别/理由 (非会员前端不显示紧急度, 但没有"半开"数据)
      urgency: opts.isMember ? result.score : null,
      level: opts.isMember ? result.level : null,
      levelLabel: opts.isMember ? result.levelLabel : null,
      reason: opts.isMember ? result.reason : null,
    };
    return { ...item, followUp: block };
  });
}

export interface FollowUpSummary {
  /** 今天必须联系 (P0) */
  dueToday: number;
  /** 有逾期跟进任务 */
  overdue: number;
  /** 本周联系 (P1) */
  thisWeek: number;
  /** 休眠池 (P4) */
  hibernating: number;
  /** 全部命中客户数 */
  total: number;
}

/**
 * 列表顶部提醒条 / 分组计数 (主人 2026-09-20 拍 P1)
 *   口径: P0 → 「今天要联系」; 逾期 = 有逾期任务; P1 → 本周; P4 → 休眠
 */
export function summarizeFollowUp(
  items: Array<{ followUp: FollowUpBlock }>
): FollowUpSummary {
  let dueToday = 0;
  let overdue = 0;
  let thisWeek = 0;
  let hibernating = 0;
  for (const it of items) {
    const f = it.followUp;
    if (f.level === "p0") dueToday++;
    if (f.level === "p1") thisWeek++;
    if (f.level === "p4") hibernating++;
    if (f.nextDueAt != null && new Date(f.nextDueAt) < new Date()) overdue++;
  }
  return { dueToday, overdue, thisWeek, hibernating, total: items.length };
}

/** 紧急度排序 (会员专用): 分档 → 分数 → 距上次联系 → 建档时间 */
export function sortByUrgency<
  T extends { followUp: FollowUpBlock; createdAt: Date },
>(items: T[]): T[] {
  const rank = (l: FollowUpBlock["level"]) =>
    l === "p0" ? 0 : l === "p1" ? 1 : l === "p2" ? 2 : l === "p3" ? 3 : 4;
  return [...items].sort((a, b) => {
    const ra = rank(a.followUp.level);
    const rb = rank(b.followUp.level);
    if (ra !== rb) return ra - rb;
    const sa = a.followUp.urgency ?? 0;
    const sb = b.followUp.urgency ?? 0;
    if (sa !== sb) return sb - sa;
    const da = a.followUp.daysSinceContact ?? 9999; // 从没联系 = 最久
    const db_ = b.followUp.daysSinceContact ?? 9999;
    if (da !== db_) return db_ - da;
    return a.createdAt.getTime() - b.createdAt.getTime();
  });
}
