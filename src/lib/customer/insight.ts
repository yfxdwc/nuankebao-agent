// ============================================
// 客户洞察 —— 把「评分」+「行动指引」组装成一个入口
// ============================================
//
// 详情页 L0 只需要一次请求就拿到 [评分环] + [今日待办] 的全部数据。
//
// 分层:
//   scoring.ts            纯函数打分 (可单测)
//   actions.ts            纯函数规则引擎 (可单测)
//   insight.ts (本文件)   把两个纯函数 + SQL 数据接起来
//   /api/customers/[id]/insight   路由 (只做鉴权 + RBAC + 序列化)
//
// ⚠ 行动指引是**免费层** —— 不调 AI, 不判会员。
//   AI 只补每条行动的 `script` (话术), 那是另行调用 (POST /api/ai/follow-up)。
//   理由: 不能因为没额度/断网就没行动 (CHARTER §1.4「产出可执行的跟进指引」是核心承诺)。
// ============================================

import { and, desc, eq, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { customer, followUpTask, wellnessRecord } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";
import { solarBirthdayWindow } from "@/lib/follow-up/birthday";
import { loadCustomerScoringSnapshot, singleImprovement, type CustomerScore } from "@/lib/customer/scoring";
import {
  buildActionItems,
  topActions,
  type ActionItem,
} from "@/lib/customer/actions";

export interface CustomerInsight {
  score: CustomerScore;
  /** 全部行动 (按优先级排序) */
  actions: ActionItem[];
  /** L0 只显示前 N 条 (不给销售压力) */
  topActions: ActionItem[];
  /** 是否有 AI 话术可用 (会员判定在路由里做, 这里只报"有/没有") */
  scriptAvailable: boolean;
}

/** L0 显示几条 */
export const TOP_ACTION_LIMIT = 3;

export async function loadCustomerInsight(
  customerId: bigint,
  now: Date = new Date()
): Promise<CustomerInsight | null> {
  // 1) 评分 + 原始快照 (一次 DB 读; 行动指引复用同一份 analysis, 不重查)
  const snap = await loadCustomerScoringSnapshot(customerId, now);
  if (!snap) return null;

  // 2) 行动上下文的补充字段: 生日 + 最近记录 + 未完成任务
  const [ctxRows, lastRecordRows, pendingRows] = await Promise.all([
    db
      .select({
        birthMonth: customer.birthMonth,
        birthDay: customer.birthDay,
        birthCalendar: customer.birthCalendar,
        birthdayRemindDays: customer.birthdayRemindDays,
      })
      .from(customer)
      .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
      .limit(1),
    db
      .select({
        pre: wellnessRecord.preConditionEncrypted,
        post: wellnessRecord.postConditionEncrypted,
        nextAdviceDate: wellnessRecord.nextAdviceDate,
      })
      .from(wellnessRecord)
      .where(eq(wellnessRecord.customerId, customerId))
      .orderBy(desc(wellnessRecord.serviceDate))
      .limit(1),
    db
      .select({ id: followUpTask.id })
      .from(followUpTask)
      .where(
        and(eq(followUpTask.customerId, customerId), eq(followUpTask.status, "pending"))
      )
      .limit(1),
  ]);

  const ctx = ctxRows[0];
  const last = lastRecordRows[0];
  let lastRecordNoImprovement: boolean | null = null;
  if (last) {
    const v = singleImprovement({
      serviceDate: now,
      pre: safeParse(last.pre),
      post: safeParse(last.post),
    });
    if (v !== null) lastRecordNoImprovement = v <= 0;
  }

  const bw = solarBirthdayWindow(
    ctx.birthMonth,
    ctx.birthDay,
    ctx.birthCalendar,
    ctx.birthdayRemindDays,
    now
  );

  // 3) 规则引擎 (免费, 不调 AI)
  const actions = buildActionItems({
    now,
    analysis: snap.analysis,
    score: snap.score,
    customerCreatedAt: snap.customerCreatedAt,
    relationshipStartAt: snap.relationshipStartAt,
    daysUntilBirthday: bw?.daysUntil ?? null,
    birthdayRemindDays: bw?.remindDays ?? null,
    nextAdviceDate: last?.nextAdviceDate ? new Date(String(last.nextAdviceDate)) : null,
    hasOwner: snap.hasOwner,
    lastRecordNoImprovement,
    hasPendingTask: pendingRows.length > 0,
  });

  return {
    score: snap.score,
    actions,
    topActions: topActions(actions, TOP_ACTION_LIMIT),
    // 路由层按会员判定覆盖
    scriptAvailable: false,
  };
}

function safeParse(cipher: string | null): Record<string, unknown> {
  if (!cipher) return {};
  try {
    return JSON.parse(decryptField(cipher)) as Record<string, unknown>;
  } catch {
    return {};
  }
}
