// ============================================
// 客户画像评分 —— 三维模型 (纯函数, 可单测, 0 额度)
// ============================================
//
// 主人 2026-09-23 拍板 (客户详情页优化 P1)。设计三原则:
//
//   1) **评分必须确定性** —— 同一份数据算两次必须一样。
//      销售一定会问「为什么是 78 分」, AI 给不了这个答案。
//      所以: 纯函数 + 可解释 breakdown + 版本号; AI 只负责把分数翻译成人话。
//
//   2) **绝不含金额** (CHARTER §3.6 红线 + ADR-0006 全库无金额字段)。
//      「价值潜力」只能用**行为代理**: 到店密度 / 关系时长 / 互动广度。
//
//   3) **时间用 `now` 注入**, 不在内部读系统时钟 (否则没法测) —— 同 urgency.ts。
//
// ⚠⚠ 与 `lib/follow-up/urgency.ts` 的分工 (别混, 后人极易搞错):
//
//     urgency 「跟进紧急度」 = 该不该**现在**联系她
//         · 输入 = 时间窗信号 (任务逾期 / 多久没联系 / 生日窗口 / 复购窗口)
//         · 语义: **分数越高越急** (反的!)
//         · 变化频率: 每天变
//         · 用途: 客户列表排序 + 今日待办
//
//     scoring 「客户画像分」 = 她这个客户**整体怎么样**
//         · 输入 = 结构性质量 (健康改善 / 关系温度 / 价值潜力)
//         · 语义: **分数越高越好** (正的)
//         · 变化频率: 慢 (以周/月计)
//         · 用途: 投入优先级 + 分析图谱 + 支撑行动指引
//
//   两者**互补不重叠**: urgency 管"什么时候", scoring 管"怎么样"。
//   详情页两者都要显示 (评分环 = scoring, 今日待办 = 来自 urgency + actions)。
//
// 分层 (同 analysis.ts 的范式):
//   buildCustomerScore(input)  ← 纯函数, 可单测
//   loadCustomerScore(id, now) ← SQL 只负责把原始数据捞出来
// ============================================

import { and, desc, eq, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { customer, followUpTask, interaction, wellnessRecord } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";
import { daysBetween } from "@/lib/follow-up/urgency";
import {
  buildFollowUpAnalysis,
  type FollowUpAnalysis,
} from "@/lib/follow-up/analysis";

/** 算法版本 —— 改算法必须 +1, 让老分数可对比 (档案化的意义) */
export const SCORING_VERSION = "v1";

// ============================================
// 类型
// ============================================

export type ScoreBand = "excellent" | "good" | "fair" | "poor";

/** 分档表 (区间下界, 高→低; 同 URGENCY_LEVELS 的写法) */
export const SCORE_BANDS: ReadonlyArray<{
  band: ScoreBand;
  min: number;
  label: string;
}> = [
  { band: "excellent", min: 80, label: "优秀" },
  { band: "good", min: 60, label: "良好" },
  { band: "fair", min: 40, label: "一般" },
  { band: "poor", min: 0, label: "需关注" },
];

export function bandOf(score: number): ScoreBand {
  return SCORE_BANDS.find((b) => score >= b.min)?.band ?? "poor";
}

export function bandLabel(score: number | null): string {
  if (score === null) return "待评估";
  return SCORE_BANDS.find((b) => score >= b.min)?.label ?? "需关注";
}

/** 一个可解释因子: 销售点开能看到"这项为什么是这个分" */
export interface ScoreFactor {
  key: string;
  label: string;
  /** 实际得分 (0 .. max) */
  score: number;
  max: number;
  /** 人话说明, 如 "月均 1.8 次到店" */
  detail: string;
}

export interface DimensionScore {
  key: "effect" | "engagement" | "value";
  label: string;
  /** 0-100; null = 数据不足 (不假装 0 分) */
  score: number | null;
  band: ScoreBand | null;
  bandLabel: string;
  factors: ScoreFactor[];
  /** score = null 时说明缺什么 */
  missingReason: string | null;
}

export interface CustomerScore {
  overall: number | null;
  overallBand: ScoreBand | null;
  overallBandLabel: string;
  effect: DimensionScore;
  engagement: DimensionScore;
  value: DimensionScore;
  /** 短板维度 key (score < 60 的, 升序) —— 行动指引用它选"先补哪个" */
  weakDimensions: string[];
  scoringVersion: string;
  computedAt: string;
}

// ============================================
// 输入
// ============================================

export interface WellnessSnapshot {
  serviceDate: Date;
  pre: Record<string, unknown>;
  post: Record<string, unknown>;
}

export interface InteractionSnapshot {
  type: "phone" | "wechat" | "visit" | "holiday_greeting" | "other";
  createdAt: Date;
}

export interface ScoringInput {
  now: Date;
  /**
   * **关系起点** = 我们和她"认识"的时间。
   *
   * ⚠ 不等于 `customer.createdAt` (那是**库里建档时间**)!
   *   冒烟发现: 导入的历史客户 createdAt = 导入那天 → 全被判"刚认识" → 价值分全员 null。
   *   正确口径 = min(建档时间, 最早养生记录日期, 最早互动日期) —— 历史记录可能是导入的,
   *   比建档时间还早。批量导入 5 年的老客户, 关系起点应该是 5 年前那次到店。
   */
  relationshipStartAt: Date;
  /**
   * 建档时间 (仅用于「建档 N 天还没联系过」的宽限期判定) —— 与关系起点分开, 语义不同。
   */
  customerCreatedAt: Date;
  /** 复用既有确定性分析 (联系/到店/任务 的时间指标) */
  analysis: FollowUpAnalysis;
  /** 养生记录 (顺序不限; 内部会排序) */
  records: WellnessSnapshot[];
  /** 互动流水 (顺序不限) */
  interactions: InteractionSnapshot[];
  /** 已完成跟进任务数 (任务健康因子) */
  completedTaskCount: number;
}

// ============================================
// 工具
// ============================================

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function round1(v: number): number {
  return Math.round(v * 10) / 10;
}

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/**
 * 单次记录的"改善程度" ∈ [-1, 1] (正 = 变好)
 *
 * 三个指标加权 (疼痛权重最高 —— 它是养生行业最核心的诉求):
 *   pain_level     0-10   → (pre - post) / 10      权重 0.5
 *   sleep_quality  1-5    → (post - pre) / 4       权重 0.3
 *   mood           1-5    → (post - pre) / 4       权重 0.2
 *
 * 缺哪项就把哪项的权重剔掉再归一化 —— 所以"只记了疼痛"也能算, 不会被当成 0。
 * 一项都没有 → null (这条记录对健康分无贡献, 不拉低也不拉高)。
 */
export function singleImprovement(r: WellnessSnapshot): number | null {
  const parts: Array<{ v: number; w: number }> = [];

  const prePain = num(r.pre.pain_level);
  const postPain = num(r.post.pain_level);
  if (prePain !== null && postPain !== null) {
    parts.push({ v: (prePain - postPain) / 10, w: 0.5 });
  }

  const preSleep = num(r.pre.sleep_quality);
  const postSleep = num(r.post.sleep_quality);
  if (preSleep !== null && postSleep !== null) {
    parts.push({ v: (postSleep - preSleep) / 4, w: 0.3 });
  }

  const preMood = num(r.pre.mood);
  const postMood = num(r.post.mood);
  if (preMood !== null && postMood !== null) {
    parts.push({ v: (postMood - preMood) / 4, w: 0.2 });
  }

  if (parts.length === 0) return null;
  const totalW = parts.reduce((s, p) => s + p.w, 0);
  return clamp(parts.reduce((s, p) => s + p.v * p.w, 0) / totalW, -1, 1);
}

/** 改善值 (-1..1) → 0-100 分。0 变化 = 50 分 (中性), +1 = 100, -1 = 0 */
function improvementToScore(v: number): number {
  return clamp(50 + v * 50, 0, 100);
}

// ============================================
// 维度 1 · 健康改善分
// ============================================

const EFFECT_RECENT_N = 5;

function scoreEffect(records: WellnessSnapshot[]): DimensionScore {
  const label = "健康改善";
  const withImprovement = [...records]
    .sort((a, b) => b.serviceDate.getTime() - a.serviceDate.getTime()) // 新→旧
    .map((r) => ({ r, v: singleImprovement(r) }))
    .filter((x): x is { r: WellnessSnapshot; v: number } => x.v !== null);

  if (withImprovement.length === 0) {
    return {
      key: "effect",
      label,
      score: null,
      band: null,
      bandLabel: bandLabel(null),
      factors: [],
      missingReason: "还没有带评分 (疼痛/睡眠/情绪) 的养生记录",
    };
  }

  const factors: ScoreFactor[] = [];

  // 因子 1: 最近一次改善 (满分 40)
  const latest = withImprovement[0];
  const latestScore = improvementToScore(latest.v);
  factors.push({
    key: "latest",
    label: "最近一次改善",
    score: round1((latestScore / 100) * 40),
    max: 40,
    detail:
      latest.v > 0.02
        ? `上次做完有改善 (+${Math.round(latest.v * 100)}%)`
        : latest.v < -0.02
          ? `上次做完反而变差 (${Math.round(latest.v * 100)}%)`
          : "上次做完几乎没变化",
  });

  // 因子 2: 近 N 次平均改善 (满分 40)
  const recent = withImprovement.slice(0, EFFECT_RECENT_N);
  const avg = recent.reduce((s, x) => s + x.v, 0) / recent.length;
  const avgScore = improvementToScore(avg);
  factors.push({
    key: "recent_avg",
    label: `近 ${recent.length} 次平均`,
    score: round1((avgScore / 100) * 40),
    max: 40,
    detail:
      avg > 0.02
        ? `平均改善 +${Math.round(avg * 100)}%`
        : avg < -0.02
          ? `平均下滑 ${Math.round(avg * 100)}%`
          : "平均基本持平",
  });

  // 因子 3: 改善趋势 (满分 20) —— 最近 2 次 vs 更早 (需 ≥3 条才有"更早")
  let trendFactor: ScoreFactor | null = null;
  if (withImprovement.length >= 3) {
    const head = withImprovement.slice(0, 2).reduce((s, x) => s + x.v, 0) / 2;
    const tailArr = withImprovement.slice(2, EFFECT_RECENT_N);
    const tail = tailArr.reduce((s, x) => s + x.v, 0) / tailArr.length;
    const delta = head - tail; // 正 = 在变好
    // delta +0.3 → 满分; -0.3 → 0
    const tScore = clamp(50 + (delta / 0.3) * 50, 0, 100);
    trendFactor = {
      key: "trend",
      label: "改善趋势",
      score: round1((tScore / 100) * 20),
      max: 20,
      detail:
        delta > 0.05
          ? "效果在变好"
          : delta < -0.05
            ? "效果在变差 (需排查)"
            : "效果平稳",
    };
    factors.push(trendFactor);
  }
  // 不足 3 条时把趋势的 20 分让给前两项 (按比例放大), 避免"样本少就低分"
  const factorMax = factors.reduce((s, f) => s + f.max, 0);
  const raw = factors.reduce((s, f) => s + f.score, 0);
  const score = clamp((raw / factorMax) * 100, 0, 100);

  return {
    key: "effect",
    label,
    score: round1(score),
    band: bandOf(score),
    bandLabel: bandLabel(score),
    factors,
    missingReason: null,
  };
}

// ============================================
// 维度 2 · 关系温度分 (4 因子 × 25)
// ============================================

/** 时间比 → 得分: ratio ≤ 1.0 满分; ≥ 2.5 零分; 中间线性 */
function punctualityScore(ratio: number, max: number): number {
  return clamp(((2.5 - ratio) / 1.5) * max, 0, max);
}

/**
 * 「还没有固定节奏」时的默认节律 (天)。
 *
 * 冒烟发现: demo 数据 6 次互动**全在同一天造** → 中位间隔 = 0 → 走"没节奏"分支
 *   → 无论过多久都是固定的 15/25 分 ("91 天没联系" 听起来却像还行)。
 * 修法: 没节奏时按 30 天(行业合理复访/回访周期)当分母套**同一个公式**,
 *   但结果**封顶 60%** —— 没有真实节奏就拿不到高分, 同时"多久没联系"仍然惩罚。
 */
const DEFAULT_CADENCE_DAYS = 30;
const NO_RHYTHM_CAP_RATIO = 0.6;

function punctualityScoreNoRhythm(daysSince: number, max: number): number {
  const ratio = daysSince / DEFAULT_CADENCE_DAYS;
  return Math.min(punctualityScore(ratio, max), max * NO_RHYTHM_CAP_RATIO);
}

function scoreEngagement(input: ScoringInput, max: number): DimensionScore {
  const label = "关系温度";
  const a = input.analysis;
  const factors: ScoreFactor[] = [];

  // 因子 1: 联系准时度 (≤25)
  {
    const d = a.daysSinceLastContact;
    const interval = a.avgContactIntervalDays;
    if (d === null) {
      factors.push({
        key: "contact_punctual",
        label: "联系准时度",
        score: 0,
        max,
        detail: "从没联系过",
      });
    } else if (interval === null || interval <= 0) {
      // 还没形成节奏 (只联系过 1 次, 或多条互动挤在同一天) → 按默认节律算但封顶 60%
      const s = punctualityScoreNoRhythm(d, max);
      factors.push({
        key: "contact_punctual",
        label: "联系准时度",
        score: round1(s),
        max,
        detail: `${d} 天前联系过 (还没有固定节奏, 暂按 ${DEFAULT_CADENCE_DAYS} 天节律评估)`,
      });
    } else {
      const ratio = d / interval;
      const s = punctualityScore(ratio, max);
      factors.push({
        key: "contact_punctual",
        label: "联系准时度",
        score: round1(s),
        max,
        detail: `${d} 天没联系 (她的节奏约 ${Math.round(interval)} 天)`,
      });
    }
  }

  // 因子 2: 到店规律 (≤25)
  {
    const d = a.daysSinceLastVisit;
    const interval = a.medianRepurchaseIntervalDays;
    if (d === null) {
      factors.push({
        key: "visit_punctual",
        label: "到店规律",
        score: 0,
        max,
        detail: "从没到店记录",
      });
    } else if (interval === null || interval <= 0) {
      const s = punctualityScoreNoRhythm(d, max);
      factors.push({
        key: "visit_punctual",
        label: "到店规律",
        score: round1(s),
        max,
        detail: `${d} 天前到过店 (还没有复购节奏, 暂按 ${DEFAULT_CADENCE_DAYS} 天节律评估)`,
      });
    } else {
      const ratio = d / interval;
      const s = punctualityScore(ratio, max);
      factors.push({
        key: "visit_punctual",
        label: "到店规律",
        score: round1(s),
        max,
        detail: `${d} 天没到店 (她的复购间隔约 ${Math.round(interval)} 天)`,
      });
    }
  }

  // 因子 3: 互动深度 (≤25) —— 近 90 天加权次数
  {
    const since = new Date(input.now.getTime() - 90 * 86_400_000);
    const inWindow = input.interactions.filter((i) => i.createdAt >= since);
    const weightOf = (t: InteractionSnapshot["type"]): number =>
      t === "visit" ? 3 : t === "phone" ? 2 : 1; // wechat / greeting / other = 1
    const weighted = inWindow.reduce((s, i) => s + weightOf(i.type), 0);
    // 0 → 0 分; ≥ 12 → 满分
    const s = clamp((weighted / 12) * max, 0, max);
    factors.push({
      key: "depth",
      label: "互动深度",
      score: round1(s),
      max,
      detail:
        inWindow.length === 0
          ? "近 90 天没有互动"
          : `近 90 天互动 ${inWindow.length} 次 (加权 ${weighted})`,
    });
  }

  // 因子 4: 任务健康 (≤25) —— 不漏单
  {
    const overdue = a.overdueTasks;
    const done = input.completedTaskCount;
    const total = done + overdue;
    if (total === 0) {
      // 从没建过跟进任务 → 不能给满分 (没在管理), 给中性偏下
      const s = max * 0.6;
      factors.push({
        key: "task_health",
        label: "跟进任务",
        score: round1(s),
        max,
        detail: "还没有建过跟进任务",
      });
    } else {
      const s = (done / total) * max;
      factors.push({
        key: "task_health",
        label: "跟进任务",
        score: round1(s),
        max,
        detail:
          overdue > 0
            ? `完成 ${done} 个, 逾期 ${overdue} 个`
            : `完成 ${done} 个, 没有逾期`,
      });
    }
  }

  const raw = factors.reduce((s, f) => s + f.score, 0);
  const score = clamp((raw / (max * 4)) * 100, 0, 100);

  return {
    key: "engagement",
    label,
    score: round1(score),
    band: bandOf(score),
    bandLabel: bandLabel(score),
    factors,
    missingReason: null,
  };
}

// ============================================
// 维度 3 · 价值潜力分 (行为代理, 无金额)
// ============================================

/**
 * 建档多久以内不判「价值潜力」。
 *
 * 冒烟发现: 建档 1 天的客户价值分 = 0.1 分 → 综合分 8.6「需关注」。
 * 这不是"价值低", 是**还没法判断** —— 关系时长因子在 12 个月才满分,
 * 1 个月的客户天生拿 2.5/30。把"时间不够"当成"价值低"会误导销售。
 */
export const VALUE_MIN_TENURE_DAYS = 30;

function scoreValue(input: ScoringInput): DimensionScore {
  const label = "价值潜力";
  const factors: ScoreFactor[] = [];
  const a = input.analysis;

  // 关系太短 → 数据不足, 不判 (返回 null 而不是低分)
  const tenureDays = daysBetween(input.relationshipStartAt, input.now);
  if (tenureDays < VALUE_MIN_TENURE_DAYS) {
    return {
      key: "value",
      label,
      score: null,
      band: null,
      bandLabel: bandLabel(null),
      factors: [],
      missingReason: `认识才 ${tenureDays} 天, 还看不出价值潜力 (需 ≥ ${VALUE_MIN_TENURE_DAYS} 天)`,
    };
  }

  // 因子 1: 到店密度 (40) —— 近 180 天月均次数, 月均 ≥2 满分
  {
    const since = new Date(input.now.getTime() - 180 * 86_400_000);
    const n = input.records.filter((r) => r.serviceDate >= since).length;
    const monthly = n / 6;
    const s = clamp((monthly / 2) * 40, 0, 40);
    factors.push({
      key: "visit_density",
      label: "到店密度",
      score: round1(s),
      max: 40,
      detail: `近半年到店 ${n} 次 (月均 ${round1(monthly)} 次)`,
    });
  }

  // 因子 2: 关系时长 (30) —— 建档至今, ≥12 个月满分
  {
    const months = Math.max(0, daysBetween(input.relationshipStartAt, input.now) / 30);
    const s = clamp((months / 12) * 30, 0, 30);
    factors.push({
      key: "tenure",
      label: "关系时长",
      score: round1(s),
      max: 30,
      detail:
        months < 1
          ? "刚认识不久"
          : `已认识 ${Math.round(months)} 个月`,
    });
  }

  // 因子 3: 互动广度 (30) —— 渠道种类数 (电话 / 微信 / 到店), 每种 10
  {
    const channels = new Set(
      input.interactions
        .map((i) => (i.type === "holiday_greeting" ? "wechat" : i.type))
        .filter((t) => t === "phone" || t === "wechat" || t === "visit")
    );
    const s = clamp(channels.size * 10, 0, 30);
    factors.push({
      key: "breadth",
      label: "互动广度",
      score: round1(s),
      max: 30,
      detail:
        channels.size === 0
          ? "还没有任何互动"
          : `用过 ${channels.size} 种联系方式 (${[...channels]
              .map((c) => (c === "phone" ? "电话" : c === "wechat" ? "微信" : "到店"))
              .join(" / ")})`,
    });
  }

  // 无数据保护: 建档很久但零互动零到店 → 给 0 分是对的 (有意义的低分)
  void a;
  const raw = factors.reduce((s, f) => s + f.score, 0);
  const score = clamp(raw, 0, 100);

  return {
    key: "value",
    label,
    score: round1(score),
    band: bandOf(score),
    bandLabel: bandLabel(score),
    factors,
    missingReason: null,
  };
}

// ============================================
// 综合
// ============================================

/** 权重: 关系温度最重 (它最直接决定"该不该投入") */
const WEIGHTS: Record<"effect" | "engagement" | "value", number> = {
  effect: 0.3,
  engagement: 0.4,
  value: 0.3,
};

/** 短板阈值: < 60 视为拖后腿 */
export const WEAK_DIMENSION_THRESHOLD = 60;

export function buildCustomerScore(input: ScoringInput): CustomerScore {
  const effect = scoreEffect(input.records);
  const engagement = scoreEngagement(input, 25);
  const value = scoreValue(input);

  const dims = [effect, engagement, value];

  // 综合分: 只用有分的维度, 权重重归一化
  //   (例: 没养生记录 → effect = null → 用 engagement 0.4 + value 0.3 重算)
  const available = dims.filter((d) => d.score !== null);
  let overall: number | null = null;
  if (available.length > 0) {
    const totalW = available.reduce((s, d) => s + WEIGHTS[d.key], 0);
    overall = round1(
      available.reduce((s, d) => s + (d.score as number) * WEIGHTS[d.key], 0) / totalW
    );
  }

  const weakDimensions = dims
    .filter(
      (d): d is DimensionScore & { score: number } =>
        d.score !== null && d.score < WEAK_DIMENSION_THRESHOLD
    )
    .sort((a, b) => a.score - b.score)
    .map((d) => d.key);

  return {
    overall,
    overallBand: overall === null ? null : bandOf(overall),
    overallBandLabel: bandLabel(overall),
    effect,
    engagement,
    value,
    weakDimensions,
    scoringVersion: SCORING_VERSION,
    computedAt: input.now.toISOString(),
  };
}

// ============================================
// Loader (SQL 只负责把原始数据捞出来)
// ============================================

/**
 * 加载结果 = 分数 + 算分数用的**原始快照**。
 *
 * 为什么把快照一起返回: 行动指引 (actions.ts) 需要同一份 analysis,
 *   如果让调用方自己再查一遍, 就会出现两次 DB 读 + 两套口径。
 */
export interface CustomerScoringSnapshot {
  score: CustomerScore;
  analysis: FollowUpAnalysis;
  /** 关系起点 (价值分的"关系时长"基准) */
  relationshipStartAt: Date;
  /** 建档时间 */
  customerCreatedAt: Date;
  /** 是否有归属人 (行动规则 profile_incomplete 用) */
  hasOwner: boolean;
}

export async function loadCustomerScoringSnapshot(
  customerId: bigint,
  now: Date = new Date()
): Promise<CustomerScoringSnapshot | null> {
  const [cust] = await db
    .select({
      id: customer.id,
      createdAt: customer.createdAt,
      ownerId: customer.ownerId,
    })
    .from(customer)
    .where(and(eq(customer.id, customerId), isNull(customer.deletedAt)))
    .limit(1);
  if (!cust) return null;

  const [recordRows, interactionRows, taskRows] = await Promise.all([
    db
      .select({
        serviceDate: wellnessRecord.serviceDate,
        pre: wellnessRecord.preConditionEncrypted,
        post: wellnessRecord.postConditionEncrypted,
      })
      .from(wellnessRecord)
      .where(eq(wellnessRecord.customerId, customerId))
      .orderBy(desc(wellnessRecord.serviceDate))
      .limit(200),
    db
      .select({ type: interaction.type, createdAt: interaction.createdAt })
      .from(interaction)
      .where(eq(interaction.customerId, customerId))
      .orderBy(desc(interaction.createdAt))
      .limit(200),
    db
      .select({ status: followUpTask.status, dueAt: followUpTask.dueAt })
      .from(followUpTask)
      .where(eq(followUpTask.customerId, customerId)),
  ]);

  // 任务: pending 的 dueAt 交给 buildFollowUpAnalysis 算逾期 (单一真相源);
  //      done 的计数用于「任务健康」因子。cancelled 不参与 (取消不算失败)。
  const openTaskDueAts = taskRows
    .filter((t) => t.status === "pending")
    .map((t) => t.dueAt);
  const completedTaskCount = taskRows.filter((t) => t.status === "done").length;

  const analysis = buildFollowUpAnalysis({
    interactionDates: interactionRows.map((r) => r.createdAt),
    visitDates: recordRows.map((r) => new Date(String(r.serviceDate))),
    openTaskDueAts,
    now,
  });

  // 关系起点 = min(建档, 最早到店, 最早互动)
  const candidates: number[] = [cust.createdAt.getTime()];
  for (const r of recordRows) candidates.push(new Date(String(r.serviceDate)).getTime());
  for (const i of interactionRows) candidates.push(i.createdAt.getTime());
  const relationshipStartAt = new Date(Math.min(...candidates));

  const score = buildCustomerScore({
    now,
    relationshipStartAt,
    customerCreatedAt: cust.createdAt,
    analysis,
    records: recordRows.map((r) => ({
      serviceDate: new Date(String(r.serviceDate)),
      pre: safeParse(r.pre),
      post: safeParse(r.post),
    })),
    interactions: interactionRows.map((r) => ({
      type: r.type,
      createdAt: r.createdAt,
    })),
    completedTaskCount,
  });

  return {
    score,
    analysis,
    customerCreatedAt: cust.createdAt,
    relationshipStartAt,
    hasOwner: cust.ownerId !== null,
  };
}

/** 只要分数的便捷入口 */
export async function loadCustomerScore(
  customerId: bigint,
  now: Date = new Date()
): Promise<CustomerScore | null> {
  const snap = await loadCustomerScoringSnapshot(customerId, now);
  return snap?.score ?? null;
}

function safeParse(cipher: string | null): Record<string, unknown> {
  if (!cipher) return {};
  try {
    return JSON.parse(decryptField(cipher)) as Record<string, unknown>;
  } catch {
    return {};
  }
}
