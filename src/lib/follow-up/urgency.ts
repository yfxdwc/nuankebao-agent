// ============================================
// 跟进紧急度 / 推荐标签 (客户列表用) — 纯函数, 可单测
// ============================================
// 主人 2026-09-20 拍板 (方案 docs/follow-up-list-plan.md):
//   - 客户排序以**跟进紧急度为第一排序规则**; **紧急度排序只给会员** (Q1)
//   - 客户名右侧显示**推荐标签**, 最多 2 个 (Q2); 标签走「动作」文案 (Q3)
//   - 加盟商**轻微加权** (Q7)
//
// 设计原则:
//   1) 只在这里算分 (单一真相) —— 客户端不许自己算, 否则口径漂移
//   2) **可解释**: 每个信号带分值与文案, 服务端拼出一句人话理由
//   3) 会员信号 (生日/复购) 由调用方按判权决定要不要传 —— 非会员传 null = 天然不参与
//   4) 时间一律用 `now` 参数注入, 别在内部读系统时钟 (否则没法测)

import { FEATURES } from "@/lib/billing/features";

export type UrgencyLevel = "p0" | "p1" | "p2" | "p3" | "p4";

export type UrgencySignalKey =
  | "task_overdue"
  | "task_due_today"
  | "no_contact_long"
  | "never_contacted"
  | "visit_break"
  | "no_visit_long"
  | "birthday_window"
  | "repurchase_window"
  | "type_weight";

export interface UrgencySignal {
  key: UrgencySignalKey;
  /** 该信号贡献的分数 (已封顶前) */
  points: number;
  /** 人话理由片段 (会拼进 reason) */
  text: string;
  /** 会员信号 (仅会员才可能出现) */
  memberOnly: boolean;
}

export interface UrgencyInput {
  customerType: "franchisee" | "seed" | "normal";
  /** 建档时间 (从没联系过时用它当基准) */
  createdAt: Date;
  lastInteractionAt: Date | null;
  lastVisitAt: Date | null;
  /** 未完成跟进任务 (dueAt 列表; 空数组 = 没有) */
  openTaskDueAts: Date[];
  /** 生日信息 (会员才有; 非会员传 null) */
  birthday?: { daysUntil: number; remindDays: number } | null;
  /** 复购窗口 (会员才有; windowOpenedAt = 预测复购日的开始; null = 未到窗口) */
  repurchase?: { windowOpenedAt: Date | null } | null;
  now: Date;
}

export interface UrgencyResult {
  score: number;
  level: UrgencyLevel;
  levelLabel: string;
  signals: UrgencySignal[];
  reason: string;
  /** 距上次联系天数 (从没联系 = null) */
  daysSinceContact: number | null;
  /** 距上次到店天数 */
  daysSinceVisit: number | null;
}

/** 分档阈值 (方案 §3.2) */
export const URGENCY_LEVELS: ReadonlyArray<{
  level: UrgencyLevel;
  min: number;
  label: string;
}> = [
  { level: "p0", min: 80, label: "今天必须联系" },
  { level: "p1", min: 60, label: "本周联系" },
  { level: "p2", min: 40, label: "两周内联系" },
  { level: "p3", min: 20, label: "正常节奏" },
  { level: "p4", min: 0, label: "休眠池" },
];

/** 距上次联系天数分档 (方案 §3.1 S3) */
const CONTACT_GAPS: ReadonlyArray<{ minDays: number; points: number; text: (d: number) => string }> = [
  { minDays: 60, points: 55, text: (d) => `已 ${d} 天没联系` },
  { minDays: 30, points: 42, text: (d) => `已 ${d} 天没联系` },
  { minDays: 15, points: 30, text: (d) => `已 ${d} 天没联系` },
  { minDays: 8, points: 18, text: (d) => `已 ${d} 天没联系` },
  { minDays: 4, points: 8, text: (d) => `已 ${d} 天没联系` },
];

/** 超长期未到店 (方案 §3.1 S6) */
const NO_VISIT_LONG_DAYS = 90;
/** 新客首访窗口: 建档超过这个天数还没联系过 → 算"没首访" (方案 §3.1 S4) */
const NEW_LEAD_DAYS = 3;

/**
 * 按**日历天**取差 (UTC 日界):
 *   - 今天到期 18:00 的任务, 在早上 9 点看 = 0 天 (不是 -1)
 *   - 昨天 23:00 联系过 → 1 天前 (不是 0)
 * 跟进语义要的是"日历天", 不是"满 24 小时", 中老年用户也这么数日子。
 */
export function startOfDayUTC(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

export function daysBetween(from: Date, to: Date): number {
  return Math.round(
    (startOfDayUTC(to).getTime() - startOfDayUTC(from).getTime()) / 86_400_000
  );
}

/** 算紧急度 (纯函数; 见文件头设计原则) */
export function computeUrgency(input: UrgencyInput): UrgencyResult {
  const { now } = input;
  const signals: UrgencySignal[] = [];

  const daysSinceContact =
    input.lastInteractionAt != null
      ? Math.max(0, daysBetween(input.lastInteractionAt, now))
      : null;
  const daysSinceVisit =
    input.lastVisitAt != null ? Math.max(0, daysBetween(input.lastVisitAt, now)) : null;

  // S1/S2 跟进任务 (免费) —— 只取最急的一条
  let overdueDays = -1;
  let dueToday = false;
  for (const dueAt of input.openTaskDueAts) {
    const d = daysBetween(dueAt, now); // > 0 = 已逾期
    if (d > 0) {
      overdueDays = Math.max(overdueDays, d);
    } else if (d === 0) {
      dueToday = true;
    }
  }
  if (overdueDays > 0) {
    const points = 40 + Math.min(20, overdueDays * 2);
    signals.push({
      key: "task_overdue",
      points,
      text: `跟进任务逾期 ${overdueDays} 天`,
      memberOnly: false,
    });
  } else if (dueToday) {
    signals.push({
      key: "task_due_today",
      points: 30,
      text: "今天有跟进任务到期",
      memberOnly: false,
    });
  }

  // S3 距上次联系分档 (免费)
  if (daysSinceContact != null) {
    const hit = CONTACT_GAPS.find((g) => daysSinceContact >= g.minDays);
    if (hit) {
      signals.push({
        key: "no_contact_long",
        points: hit.points,
        text: hit.text(daysSinceContact),
        memberOnly: false,
      });
    }
  } else {
    // S4 从没联系过 (免费): 建档超过 3 天
    const daysSinceCreated = Math.max(0, daysBetween(input.createdAt, now));
    if (daysSinceCreated > NEW_LEAD_DAYS) {
      signals.push({
        key: "never_contacted",
        points: 35,
        text: `新客户还没联系过 (建档 ${daysSinceCreated} 天)`,
        memberOnly: false,
      });
    }
  }

  // S6 超长期未到店 (免费, 加性; 与 S5 断档在 P1 一起做)
  if (daysSinceVisit != null && daysSinceVisit > NO_VISIT_LONG_DAYS) {
    signals.push({
      key: "no_visit_long",
      points: 10,
      text: `${daysSinceVisit} 天没到店`,
      memberOnly: false,
    });
  }

  // S7 生日窗口 (会员)
  if (input.birthday != null) {
    const { daysUntil, remindDays } = input.birthday;
    if (daysUntil === 0) {
      signals.push({
        key: "birthday_window",
        points: 60,
        text: "今天生日",
        memberOnly: true,
      });
    } else if (daysUntil <= remindDays) {
      signals.push({
        key: "birthday_window",
        points: 45,
        text: `生日 ${daysUntil} 天后`,
        memberOnly: true,
      });
    }
  }

  // S8 复购窗口 (会员)
  if (input.repurchase?.windowOpenedAt != null) {
    const openedDays = Math.max(0, daysBetween(input.repurchase.windowOpenedAt, now));
    signals.push({
      key: "repurchase_window",
      points: 50,
      text: openedDays > 0 ? `复购窗口已开 ${openedDays} 天` : "复购窗口到了",
      memberOnly: true,
    });
  }

  // S9 类型轻微加权 (免费; 主人 2026-09-20 拍: 加盟商轻微加权)
  if (input.customerType === "franchisee") {
    signals.push({
      key: "type_weight",
      points: 5,
      text: "加盟商",
      memberOnly: false,
    });
  } else if (input.customerType === "seed") {
    signals.push({
      key: "type_weight",
      points: 5,
      text: "种子客户",
      memberOnly: false,
    });
  }

  const raw = signals.reduce((sum, s) => sum + s.points, 0);
  const score = Math.max(0, Math.min(100, raw));
  const level = URGENCY_LEVELS.find((l) => score >= l.min)?.level ?? "p4";
  const levelLabel = URGENCY_LEVELS.find((l) => l.level === level)?.label ?? "";

  // reason: 取分值最高的 2 个信号 (动作性更强的排前面)
  const ordered = [...signals].sort((a, b) => b.points - a.points);
  const reason = ordered
    .slice(0, 2)
    .filter((s) => s.key !== "type_weight") // 「加盟商」不当理由 (是身份不是动作)
    .map((s) => s.text)
    .join(" · ");

  return {
    score,
    level,
    levelLabel,
    signals: ordered,
    reason: reason || "跟进节奏正常",
    daysSinceContact,
    daysSinceVisit,
  };
}

// ============================================
// 推荐标签 (主人 2026-09-20 拍: 最多 2 个, 走「动作」文案)
// ============================================

export interface FollowUpTag {
  key:
    | "overdue"
    | "birthday"
    | "repurchase"
    | "new_lead"
    | "cold"
    | "stale";
  emoji: string;
  /** ≤ 4 个汉字, 动作导向 */
  label: string;
  color: "danger" | "accent" | "franchisee" | "primary";
  /** tooltip / 无障碍用的完整说明 */
  hint: string;
  memberOnly: boolean;
}

/**
 * 挑标签: **1 个动作标签 + 最多 1 个日历标签** (生日/复购)
 *   - 动作标签: 有任务逾期 → 该回访了; 从没联系 → 新客首访; 很久没联系 → 掉线/沉睡
 *   - 日历标签: 生日窗口 / 复购窗口 (会员)
 *   - 正常节奏 → 空数组 (安静, 不给标签)
 */
export function pickFollowUpTags(
  result: UrgencyResult,
  input: Pick<UrgencyInput, "birthday" | "repurchase">
): FollowUpTag[] {
  const tags: FollowUpTag[] = [];
  const has = (k: UrgencySignalKey) => result.signals.some((s) => s.key === k);
  const sig = (k: UrgencySignalKey) => result.signals.find((s) => s.key === k);

  // 动作标签 (只取一个, 按优先级)
  if (has("task_overdue") || has("task_due_today")) {
    const s = sig("task_overdue") ?? sig("task_due_today");
    tags.push({
      key: "overdue",
      emoji: "🔥",
      label: "该回访了",
      color: "danger",
      hint: s?.text ?? "有到期的跟进任务",
      memberOnly: false,
    });
  } else if (has("never_contacted")) {
    tags.push({
      key: "new_lead",
      emoji: "🌟",
      label: "新客首访",
      color: "accent",
      hint: sig("never_contacted")?.text ?? "还没联系过",
      memberOnly: false,
    });
  } else {
    const d = result.daysSinceContact;
    if (d != null && d > 60) {
      tags.push({
        key: "stale",
        emoji: "💤",
        label: "久未联系",
        color: "primary",
        hint: `已 ${d} 天没联系`,
        memberOnly: false,
      });
    } else if (d != null && d > 30) {
      tags.push({
        key: "cold",
        emoji: "⚠️",
        label: "掉线了",
        color: "primary",
        hint: `已 ${d} 天没联系`,
        memberOnly: false,
      });
    }
  }

  // 日历标签 (最多一个; 生日优先于复购)
  if (input.birthday != null && input.birthday.daysUntil <= input.birthday.remindDays) {
    tags.push({
      key: "birthday",
      emoji: "🎂",
      label: input.birthday.daysUntil === 0 ? "今天生日" : "生日临近",
      color: "accent",
      hint: input.birthday.daysUntil === 0
        ? "今天生日 (会员功能)"
        : `生日 ${input.birthday.daysUntil} 天后 (会员功能)`,
      memberOnly: true,
    });
  } else if (input.repurchase?.windowOpenedAt != null) {
    tags.push({
      key: "repurchase",
      emoji: "🔁",
      label: "复购窗口",
      color: "franchisee",
      hint: "按历史节奏, 该回访复购了 (会员功能)",
      memberOnly: true,
    });
  }

  return tags.slice(0, 2);
}

/** 会员功能 key (供 route 判权参考; 紧急度排序 = ai.repurchase) */
export const URGENCY_FEATURE_KEY = FEATURES.AI_REPURCHASE;
