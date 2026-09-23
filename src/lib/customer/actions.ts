// ============================================
// 客户行动指引 —— 规则引擎 (纯函数, 可单测, 0 额度)
// ============================================
//
// 主人 2026-09-23 拍板 (客户详情页优化 P1)。
//
// CHARTER §1.4 四要素最后一条 = 「行动输出: **明确的**跟进指引」。
// 本模块就是那个"明确" —— 不是 AI 生成的一段话, 而是**结构化、可勾选、可建任务**的行动项。
//
// 为什么行动必须是规则引擎而不是 AI:
//   1) 「什么时候做什么」是**可判定**的 (距上次到店天数 vs 她的复购间隔) —— 不需要 AI
//   2) 必须**可解释**: 每条行动带 `evidence`, 销售能核对 ("已超 4 天" 而不是"我觉得")
//   3) 必须**可闭环**: 一键建跟进任务 → 回写 follow_up_task → 完成后反哺评分 (任务健康因子)
//   4) 不能因为 AI 挂了/没额度就没行动 —— 行动指引是**免费层**, AI 只补 `script` (话术)
//
// 与 scoring.ts 的分工:
//   scoring 回答「她怎么样」(分数)  → 本模块回答「那我该做什么」(行动)
//   buildActionItems 消费 CustomerScore + FollowUpAnalysis, 产出 ActionItem[]
//
// ⚠ 免责边界: 涉及健康判断的行动 (如"效果没改善 → 复诊") 只提示**该找专业人员复核**,
//   不给医疗建议 (CHARTER §1.3 Anti-Vision: 不做医疗诊断系统)。
// ============================================

import type { FollowUpAnalysis } from "@/lib/follow-up/analysis";
import { daysBetween } from "@/lib/follow-up/urgency";
import type { CustomerScore } from "@/lib/customer/scoring";
import {
  DEFAULT_RESOLVED_CONFIG,
  resolveInsightConfig,
  type ActionConfig,
} from "@/lib/customer/insight-config";

// ============================================
// 类型
// ============================================

export type ActionPriority = "high" | "medium" | "low";

export type ActionChannel = "phone" | "wechat" | "visit" | "profile" | "internal";

export type ActionRuleId =
  | "never_contacted"
  | "repurchase_window"
  | "task_overdue"
  | "contact_gap"
  | "no_improvement"
  | "birthday_window"
  | "first_visit_followup"
  | "advice_due"
  | "profile_incomplete";

export interface ActionItem {
  /** 稳定 id (规则 id; 同规则只出一条) —— 前端可据此去重/追踪 */
  id: ActionRuleId;
  priority: ActionPriority;
  /** 动词短语, 10 字内, 直接当按钮文案 */
  title: string;
  /** 一句人话 "为什么现在做" */
  why: string;
  /** 可核对的数字 (销售能自己验) */
  evidence: Record<string, number | string | null>;
  /** "今天" / "本周" / "3 天后" */
  when: string;
  channel: ActionChannel;
  /** 做完能得到什么 */
  expected: string;
  /** 建议任务标题 (一键建任务时预填) */
  taskTitle: string;
  /** 建议任务截止 (ISO; 一键建任务时预填) */
  taskDueAt: string;
}

export interface ActionInput {
  now: Date;
  analysis: FollowUpAnalysis;
  score: CustomerScore;
  /** 建档时间 (「建档 N 天从没联系过」规则用) */
  customerCreatedAt: Date;
  /** 关系起点 (预留给"关系很久却断了"类规则) */
  relationshipStartAt: Date;
  /** 生日: 距今几天 (null = 没填 / 非会员不可见) */
  daysUntilBirthday: number | null;
  /** 生日提醒强度 (天); null = 用户关掉了提醒 */
  birthdayRemindDays: number | null;
  /** 最近一次 record 的 nextAdviceDate (null = 没填) */
  nextAdviceDate: Date | null;
  /** 是否已建档归属 */
  hasOwner: boolean;
  /** 最近一次带评分的记录是否"没改善" (post >= pre) */
  lastRecordNoImprovement: boolean | null;
  /** 是否已有该客户的 pending 任务 (有就不重复建议"首访回访") */
  hasPendingTask: boolean;
}

// ============================================
// 阈值
// ============================================
// ⚠ 全部可调 —— 真源在 `insight-config.ts::DEFAULT_INSIGHT_CONFIG.actions`,
//   这里只是给「不传 config 的调用方」+ 测试可读性留的别名。
//   admin 调节页将来编辑的是 insight-config 那份 (存 DB)。

/** @deprecated 用 `config.actions.*` (见 insight-config.ts) */
export const ACTION_THRESHOLDS = {
  /** 到店超期倍数: daysSinceLastVisit > median * N → 建议约下次到店 */
  REPURCHASE_OVERDUE_FACTOR: DEFAULT_RESOLVED_CONFIG.actions.repurchaseOverdueFactor,
  /** 联系超期倍数: daysSinceLastContact > avgInterval * N → 建议主动联系 */
  CONTACT_GAP_FACTOR: DEFAULT_RESOLVED_CONFIG.actions.contactGapFactor,
  /**
   * **没有节奏时的绝对兜底阈值** (天)。
   *
   * 冒烟发现的真 BUG: 规则原先要求 `avgContactIntervalDays > 0`。
   *   但同一批集中互动过 (多条互动挤在同一天) 的客户 → 中位间隔 = 0
   *   → 规则**永远不触发**, 哪怕 91 天没联系, 也不给任何行动。显然错。
   * 修法: 没节奏时不看比例, 改用绝对天数 (超过这个数就该主动联系了)。
   */
  CONTACT_ABSOLUTE_GAP_DAYS: DEFAULT_RESOLVED_CONFIG.actions.contactAbsoluteGapDays,
  /** 无复购节奏时的绝对兜底阈值 (天) */
  REPURCHASE_ABSOLUTE_OVERDUE_DAYS: DEFAULT_RESOLVED_CONFIG.actions.repurchaseAbsoluteOverdueDays,
  /** 生日提前提醒窗口 (天); 与 birthdayRemindDays 取小 */
  BIRTHDAY_WINDOW_DAYS: DEFAULT_RESOLVED_CONFIG.actions.birthdayWindowDays,
  /** 首访后回访窗口 (天) */
  FIRST_VISIT_FOLLOWUP_DAYS: DEFAULT_RESOLVED_CONFIG.actions.firstVisitFollowupDays,
  /** 建档多少天后「从没联系过」才算需要破冰 (当天建的别催) */
  NEVER_CONTACTED_GRACE_DAYS: DEFAULT_RESOLVED_CONFIG.actions.neverContactedGraceDays,
  /** nextAdviceDate 提前提醒窗口 (天) */
  ADVICE_LEAD_DAYS: DEFAULT_RESOLVED_CONFIG.actions.adviceLeadDays,
} as const;

const PRIORITY_ORDER: Record<ActionPriority, number> = {
  high: 0,
  medium: 1,
  low: 2,
};

/** 优先级阶梯 (低 → 高), 用于"严重时升一档" */
const LADDER: readonly ActionPriority[] = ["low", "medium", "high"];

/**
 * 升一档 (低→中, 中→高, 高→高)。
 *
 * 为什么需要: 规则优先级是可配的 (基线), 但**同一规则内部的严重度差异**也该体现 ——
 *   例: 「生日关怀」平时 medium, 但**生日当天**该升到 high;
 *      「按建议回访」平时 medium, 但**已过期**该升到 high。
 *   config 管基线, escalate 管严重度, 两者叠加。
 */
function escalate(p: ActionPriority): ActionPriority {
  return LADDER[Math.min(LADDER.length - 1, LADDER.indexOf(p) + 1)];
}

// ============================================
// 工具
// ============================================

function addDays(d: Date, n: number): Date {
  return new Date(d.getTime() + n * 86_400_000);
}

function whenLabel(daysFromNow: number): string {
  if (daysFromNow <= 0) return "今天";
  if (daysFromNow === 1) return "明天";
  if (daysFromNow <= 7) return `${daysFromNow} 天后`;
  return "本周内";
}

// ============================================
// 规则
// ============================================

/**
 * 规则引擎入口。
 *
 * @param config 可调阈值 + 各规则优先级 (默认 = DEFAULT_INSIGHT_CONFIG.actions)。
 *   传进来的东西会被 `resolveInsightConfig` 夹区间 (配置可能来自 DB/UI, 不受信)。
 */
export function buildActionItems(
  input: ActionInput,
  config?: unknown,
): ActionItem[] {
  const cfg = resolveInsightConfig(config).actions;
  const T = cfg; // 阈值别名 (短一点, 下面规则好读)
  const P = cfg.priorities; // 优先级别名
  const { now, analysis: a, score } = input;
  const out: ActionItem[] = [];

  // ── 规则 0: 全新客户从没联系过 → 破冰 (冒烟发现: 之前这种情况**零行动**, 是漏的) ──
  //   放在最前面: 她刚建档还没进过任何节奏, 其他规则的条件全是 null, 一条都不触发。
  if (
    a.contactTotal === 0 &&
    daysBetween(input.customerCreatedAt, now) >= T.neverContactedGraceDays &&
    !input.hasPendingTask
  ) {
    out.push({
      id: "never_contacted",
      priority: P.never_contacted,
      title: "首次联系破冰",
      why: `建档 ${daysBetween(input.customerCreatedAt, now)} 天了, 一次都还没联系过`,
      evidence: {
        contactTotal: 0,
        daysSinceCreated: daysBetween(input.customerCreatedAt, now),
      },
      when: "今天",
      channel: "wechat",
      expected: "加上微信 / 打个招呼, 建立第一次联系",
      taskTitle: "首次联系",
      taskDueAt: now.toISOString(),
    });
  }

  // ── 规则 1: 复购窗口已到 (最高优先级 —— 直接关系营收) ──
  {
    const d = a.daysSinceLastVisit;
    const interval = a.medianRepurchaseIntervalDays;
    const hasRhythm = interval !== null && interval > 0;
    const byRhythm =
      hasRhythm &&
      d !== null &&
      d > (interval as number) * T.repurchaseOverdueFactor;
    const byAbsolute =
      !hasRhythm && d !== null && d >= T.repurchaseAbsoluteOverdueDays;
    if (byRhythm || byAbsolute) {
      const overdue = hasRhythm
        ? (d as number) -
          Math.round((interval as number) * T.repurchaseOverdueFactor)
        : (d as number) - T.repurchaseAbsoluteOverdueDays;
      out.push({
        id: "repurchase_window",
        priority: P.repurchase_window,
        title: "约下次到店",
        why: hasRhythm
          ? `她的复购间隔通常 ${Math.round(interval as number)} 天, 已经 ${d} 天没到店`
          : `已经 ${d} 天没到店了 (还没形成固定复购节奏)`,
        evidence: {
          daysSinceLastVisit: d,
          medianRepurchaseIntervalDays: hasRhythm ? Math.round(interval as number) : null,
          overdueDays: overdue,
        },
        when: "今天",
        channel: "phone",
        expected: "约到具体日期",
        taskTitle: "约下次到店",
        taskDueAt: now.toISOString(),
      });
    }
  }

  // ── 规则 2: 有逾期任务 (最紧急 —— 已经欠着了) ──
  if (a.overdueTasks > 0) {
    out.push({
      id: "task_overdue",
      priority: P.task_overdue,
      title: "补上逾期跟进",
      why: `有 ${a.overdueTasks} 个跟进任务逾期${
        a.oldestOverdueDays !== null ? `, 最久 ${a.oldestOverdueDays} 天` : ""
      }`,
      evidence: {
        overdueTasks: a.overdueTasks,
        oldestOverdueDays: a.oldestOverdueDays,
      },
      when: "今天",
      channel: "phone",
      expected: "把逾期任务清掉",
      taskTitle: "补上逾期跟进",
      taskDueAt: now.toISOString(),
    });
  }

  // ── 规则 3: 联系脱节 ──
  {
    const d = a.daysSinceLastContact;
    const interval = a.avgContactIntervalDays;
    const hasRhythm = interval !== null && interval > 0;
    const byRhythm =
      hasRhythm &&
      d !== null &&
      d > (interval as number) * T.contactGapFactor;
    const byAbsolute =
      !hasRhythm &&
      a.contactTotal > 0 &&
      d !== null &&
      d >= T.contactAbsoluteGapDays;
    if (byRhythm || byAbsolute) {
      out.push({
        id: "contact_gap",
        priority: byAbsolute ? escalate(P.contact_gap) : P.contact_gap,
        title: "主动联系一下",
        why: hasRhythm
          ? `平时约 ${Math.round(interval as number)} 天联系一次, 这次已经 ${d} 天`
          : `已经 ${d} 天没联系了`,
        evidence: {
          daysSinceLastContact: d,
          avgContactIntervalDays: hasRhythm ? Math.round(interval as number) : null,
        },
        when: "本周",
        channel: "wechat",
        expected: "恢复联系节奏",
        taskTitle: "主动联系",
        taskDueAt: addDays(now, 3).toISOString(),
      });
    }
  }

  // ── 规则 4: 效果没改善 (健康侧预警; 只提示复核, 不给医疗建议) ──
  if (input.lastRecordNoImprovement === true) {
    out.push({
      id: "no_improvement",
      priority: P.no_improvement,
      title: "复核服务方案",
      why: "上次做完后疼痛/睡眠没有改善, 建议找店长或资深技师复核方案",
      evidence: {
        lastRecordNoImprovement: "是",
        effectScore: score.effect.score,
      },
      when: "今天",
      channel: "internal",
      expected: "确认方案是否需要调整",
      taskTitle: "复核服务方案 (效果未改善)",
      taskDueAt: now.toISOString(),
    });
  }

  // ── 规则 5: 生日关怀 (窗口 = min(7, 用户设的提醒天数)) ──
  if (input.daysUntilBirthday !== null && input.birthdayRemindDays !== null) {
    const window = Math.max(
      0,
      Math.min(T.birthdayWindowDays, input.birthdayRemindDays)
    );
    if (input.daysUntilBirthday >= 0 && input.daysUntilBirthday <= window) {
      out.push({
        id: "birthday_window",
        priority: input.daysUntilBirthday <= 1 ? escalate(P.birthday_window) : P.birthday_window,
        title: input.daysUntilBirthday === 0 ? "今天生日, 发祝福" : "准备生日关怀",
        why:
          input.daysUntilBirthday === 0
            ? "今天是她生日"
            : `${input.daysUntilBirthday} 天后生日`,
        evidence: { daysUntilBirthday: input.daysUntilBirthday },
        when: whenLabel(input.daysUntilBirthday),
        channel: "wechat",
        expected: "关系升温",
        taskTitle: "生日关怀",
        taskDueAt: addDays(now, input.daysUntilBirthday).toISOString(),
      });
    }
  }

  // ── 规则 6: 首访后回访 (仅首次到店 + 无待办时, 避免和老客户规则打架) ──
  if (
    a.visitCount === 1 &&
    a.daysSinceLastVisit !== null &&
    a.daysSinceLastVisit >= T.firstVisitFollowupDays &&
    !input.hasPendingTask
  ) {
    out.push({
      id: "first_visit_followup",
      priority: P.first_visit_followup,
      title: "首次效果回访",
      why: `首次到店已 ${a.daysSinceLastVisit} 天, 还没回访过效果`,
      evidence: {
        visitCount: a.visitCount,
        daysSinceLastVisit: a.daysSinceLastVisit,
      },
      when: "本周",
      channel: "phone",
      expected: "了解效果 + 铺垫第二次到店",
      taskTitle: "首次效果回访",
      taskDueAt: addDays(now, 1).toISOString(),
    });
  }

  // ── 规则 7: 技师建议的回访日期已到 ──
  if (input.nextAdviceDate !== null) {
    const dueIn = daysBetween(now, input.nextAdviceDate);
    if (dueIn <= T.adviceLeadDays) {
      out.push({
        id: "advice_due",
        priority: dueIn < 0 ? escalate(P.advice_due) : P.advice_due,
        title: "按上次建议回访",
        why:
          dueIn < 0
            ? `上次建议的回访日已过 ${-dueIn} 天`
            : "上次记录里定的回访日到了",
        evidence: { dueInDays: dueIn },
        when: whenLabel(Math.max(0, dueIn)),
        channel: "phone",
        expected: "按技师建议的时间点回访",
        taskTitle: "按建议日期回访",
        taskDueAt: input.nextAdviceDate.toISOString(),
      });
    }
  }

  // ── 规则 8: 档案不完整 (归属缺失会让客户在别人列表里"消失") ──
  if (!input.hasOwner) {
    out.push({
      id: "profile_incomplete",
      priority: P.profile_incomplete,
      title: "认领为我的客户",
      why: "这个客户还没有归属人, 不认领的话不在任何人的客户列表里",
      evidence: { hasOwner: "否" },
      when: "本周",
      channel: "profile",
      expected: "进入我的客户列表",
      taskTitle: "认领客户",
      taskDueAt: addDays(now, 3).toISOString(),
    });
  }

  // 排序: 优先级 → 保持规则定义顺序 (稳定)
  return out
    .map((item, idx) => ({ item, idx }))
    .sort(
      (x, y) =>
        PRIORITY_ORDER[x.item.priority] - PRIORITY_ORDER[y.item.priority] ||
        x.idx - y.idx
    )
    .map((x) => x.item);
}

/** 取最靠前的 N 条 (详情页 L0 只显示 1-3 条, 不给销售压力) */
export function topActions(items: ActionItem[], n = 3): ActionItem[] {
  return items.slice(0, n);
}
