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
import {
  DEFAULT_RESOLVED_CONFIG,
  resolveInsightConfig,
  type EffectConfig,
  type EngagementConfig,
  type InsightConfig,
  type PunctualityConfig,
  type ScoreBandConfig,
  type ValueConfig,
} from "@/lib/customer/insight-config";

/**
 * 算法版本 —— 改**算法逻辑**必须 +1 (改参数不用, 参数有 config.version)。
 * 分数上带 `scoringVersion` + `configVersion`, 两者一起才能说明"这个分数是怎么来的"。
 */
export const SCORING_VERSION = "v1";

// ============================================
// 类型
// ============================================

export type ScoreBand = "excellent" | "good" | "fair" | "poor";

/**
 * 默认分档表 (等价于 DEFAULT_INSIGHT_CONFIG.scoring.bands)。
 * @deprecated 新代码请用 `bandOf(score, config.scoring.bands)` —— 分档是可调的。
 *   保留此导出只为向后兼容 + 测试可读性。
 */
export const SCORE_BANDS: ReadonlyArray<ScoreBandConfig> =
  DEFAULT_RESOLVED_CONFIG.scoring.bands;

/** 分档: 传 bands 才用配置 (默认用默认配置) */
export function bandOf(
  score: number,
  bands: ReadonlyArray<ScoreBandConfig> = SCORE_BANDS,
): ScoreBand {
  return bands.find((b) => score >= b.min)?.band ?? "poor";
}

export function bandLabel(
  score: number | null,
  bands: ReadonlyArray<ScoreBandConfig> = SCORE_BANDS,
): string {
  if (score === null) return "待评估";
  return bands.find((b) => score >= b.min)?.label ?? "需关注";
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
  /** 算法版本 (改逻辑时 +1) */
  scoringVersion: string;
  /** 参数版本 (改阈值/权重时 +1) —— 与 scoringVersion 分工不同 */
  configVersion: string;
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
 *   pain_level     0-10   → (pre - post) / 10                    权重 0.5
 *   sleep_quality  1-10   → (post - pre) / (量程 - 1)            权重 0.3
 *   mood           1-10   → (post - pre) / (量程 - 1)            权重 0.2
 *
 * ⚠ 量程声明 (2026-09-24 主人拍: 「睡眠质量和情绪也都用 10 分制, 默认都是 5」):
 *   表单在 `preCondition.scale` / `postCondition.scale` 里写 10。
 *   **历史记录没有这个键** → 仍按 1-5 解释 (跨度 4) —— 老记录的分数不会被
 *   静默改写 (否则同一条老数据的分会凭空掉一截)。
 *
 * 缺哪项就把哪项的权重剔掉再归一化 —— 所以"只记了疼痛"也能算, 不会被当成 0。
 * 一项都没有 → null (这条记录对健康分无贡献, 不拉低也不拉高)。
 */
export function singleImprovement(
  r: WellnessSnapshot,
  cfg: EffectConfig = DEFAULT_RESOLVED_CONFIG.scoring.effect,
): number | null {
  const parts: Array<{ v: number; w: number }> = [];
  const W = cfg.metricWeights;

  const prePain = num(r.pre.pain_level);
  const postPain = num(r.post.pain_level);
  if (prePain !== null && postPain !== null) {
    // 疼痛量程 0-10 → 除以 10 归一化到 [-1,1]
    parts.push({ v: (prePain - postPain) / 10, w: W.pain });
  }

  // 睡眠 / 情绪量程: 记录声明了 scale (新记录 = 10) → 跨度 = scale - 1;
  //   没声明 (2026-09-24 之前的历史记录) → 1-5, 跨度 4。
  const declaredScale = num(r.pre.scale) ?? num(r.post.scale);
  const sleepMoodSpan =
    declaredScale !== null && declaredScale >= 2 ? declaredScale - 1 : 4;

  const preSleep = num(r.pre.sleep_quality);
  const postSleep = num(r.post.sleep_quality);
  if (preSleep !== null && postSleep !== null) {
    parts.push({ v: (postSleep - preSleep) / sleepMoodSpan, w: W.sleep });
  }

  const preMood = num(r.pre.mood);
  const postMood = num(r.post.mood);
  if (preMood !== null && postMood !== null) {
    parts.push({ v: (postMood - preMood) / sleepMoodSpan, w: W.mood });
  }

  if (parts.length === 0) return null;
  const totalW = parts.reduce((s, p) => s + p.w, 0);
  return clamp(parts.reduce((s, p) => s + p.v * p.w, 0) / totalW, -1, 1);
}

/**
 * 改善值 (-1..1) → 0-100 分。
 * 默认: 0 变化 = 50 分 (中性), +1 = 100, -1 = 0
 * (neutral / span 都可配 —— 若某业务希望"没变化"就是不及格, 把 neutral 调低即可)
 */
function improvementToScore(
  v: number,
  scale: EffectConfig["scale"] = DEFAULT_RESOLVED_CONFIG.scoring.effect.scale,
): number {
  return clamp(scale.neutral + v * scale.span, 0, 100);
}

// ============================================
// 维度 1 · 健康改善分
// ============================================

function scoreEffect(
  records: WellnessSnapshot[],
  cfg: EffectConfig = DEFAULT_RESOLVED_CONFIG.scoring.effect,
  bands: ReadonlyArray<ScoreBandConfig> = SCORE_BANDS,
): DimensionScore {
  const label = "健康改善";
  const withImprovement = [...records]
    .sort((a, b) => b.serviceDate.getTime() - a.serviceDate.getTime()) // 新→旧
    .map((r) => ({ r, v: singleImprovement(r, cfg) }))
    .filter((x): x is { r: WellnessSnapshot; v: number } => x.v !== null);

  if (withImprovement.length === 0) {
    return {
      key: "effect",
      label,
      score: null,
      band: null,
      bandLabel: bandLabel(null, bands),
      factors: [],
      missingReason: "还没有带评分 (疼痛/睡眠/情绪) 的养生记录",
    };
  }

  const factors: ScoreFactor[] = [];

  // 因子 1: 最近一次改善
  const latest = withImprovement[0];
  const latestScore = improvementToScore(latest.v, cfg.scale);
  factors.push({
    key: "latest",
    label: "最近一次改善",
    score: round1((latestScore / 100) * cfg.factorMax.latest),
    max: cfg.factorMax.latest,
    detail:
      latest.v > 0.02
        ? `上次做完有改善 (+${Math.round(latest.v * 100)}%)`
        : latest.v < -0.02
          ? `上次做完反而变差 (${Math.round(latest.v * 100)}%)`
          : "上次做完几乎没变化",
  });

  // 因子 2: 近 N 次平均改善
  const recent = withImprovement.slice(0, cfg.recentN);
  const avg = recent.reduce((s, x) => s + x.v, 0) / recent.length;
  const avgScore = improvementToScore(avg, cfg.scale);
  factors.push({
    key: "recent_avg",
    label: `近 ${recent.length} 次平均`,
    score: round1((avgScore / 100) * cfg.factorMax.recentAvg),
    max: cfg.factorMax.recentAvg,
    detail:
      avg > 0.02
        ? `平均改善 +${Math.round(avg * 100)}%`
        : avg < -0.02
          ? `平均下滑 ${Math.round(avg * 100)}%`
          : "平均基本持平",
  });

  // 因子 3: 改善趋势 —— 最近 headN 次 vs 更早 tailN 次
  //   ⚠ 门槛 = headN + 1 (尾部至少要有 1 条), 不是 headN + tailN ——
  //     否则只有 3 条记录时永远出不了趋势因子 (与变量化之前的行为不一致)。
  //     tailN 是**上限** (最多看几条), 不是**必需条数**。
  const needForTrend = cfg.trend.headN + 1;
  const tailEnd = cfg.trend.headN + cfg.trend.tailN;
  let trendFactor: ScoreFactor | null = null;
  if (withImprovement.length >= needForTrend) {
    const head =
      withImprovement.slice(0, cfg.trend.headN).reduce((s, x) => s + x.v, 0) /
      cfg.trend.headN;
    const tailArr = withImprovement.slice(cfg.trend.headN, tailEnd);
    const tail = tailArr.reduce((s, x) => s + x.v, 0) / tailArr.length;
    const delta = head - tail; // 正 = 在变好
    // delta 达 fullDelta → 满分; 反向同幅 → 0
    const tScore = clamp(
      cfg.scale.neutral + (delta / cfg.trend.fullDelta) * cfg.scale.span,
      0,
      100,
    );
    trendFactor = {
      key: "trend",
      label: "改善趋势",
      score: round1((tScore / 100) * cfg.factorMax.trend),
      max: cfg.factorMax.trend,
      detail:
        delta > 0.05
          ? "效果在变好"
          : delta < -0.05
            ? "效果在变差 (需排查)"
            : "效果平稳",
    };
    factors.push(trendFactor);
  }
  // 出现趋势因子时按实际 factorMax 总和归一化 → 样本少不硬扣分
  const factorMax = factors.reduce((s, f) => s + f.max, 0);
  const raw = factors.reduce((s, f) => s + f.score, 0);
  const score = clamp((raw / factorMax) * 100, 0, 100);

  return {
    key: "effect",
    label,
    score: round1(score),
    band: bandOf(score, bands),
    bandLabel: bandLabel(score, bands),
    factors,
    missingReason: null,
  };
}

// ============================================
// 维度 2 · 关系温度分
// ============================================

/**
 * 时间比 → 得分; 中间线性。
 * ratio ≤ fullRatio 满分; ratio ≥ zeroRatio 零分 (都来自 config)
 */
function punctualityScore(
  ratio: number,
  max: number,
  cfg: PunctualityConfig = DEFAULT_RESOLVED_CONFIG.scoring.engagement.punctuality,
): number {
  const span = cfg.zeroRatio - cfg.fullRatio;
  if (span <= 0) return ratio <= cfg.fullRatio ? max : 0;
  return clamp(((cfg.zeroRatio - ratio) / span) * max, 0, max);
}

/**
 * 「还没有固定节奏」时的替身算法。
 *
 * 冒烟发现的真 BUG: demo 数据 6 次互动**全在同一天造** → 中位间隔 = 0
 *   → 走"没节奏"分支 → 原先给**固定 15/25 分**, "91 天没联系"听起来却像还行。
 * 修法: 没节奏时按 `cadenceDays` (行业合理复访/回访周期) 当分母套**同一个公式**,
 *   但结果**封顶 capRatio** —— 没有真实节奏就拿不到高分, 同时"多久没联系"仍然惩罚。
 */
function punctualityScoreNoRhythm(
  daysSince: number,
  max: number,
  cfg: EngagementConfig = DEFAULT_RESOLVED_CONFIG.scoring.engagement,
): number {
  const ratio = daysSince / cfg.noRhythm.cadenceDays;
  return Math.min(
    punctualityScore(ratio, max, cfg.punctuality),
    max * cfg.noRhythm.capRatio,
  );
}

function scoreEngagement(
  input: ScoringInput,
  cfg: EngagementConfig = DEFAULT_RESOLVED_CONFIG.scoring.engagement,
  bands: ReadonlyArray<ScoreBandConfig> = SCORE_BANDS,
): DimensionScore {
  const label = "关系温度";
  const max = cfg.factorMax;
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
      const s = punctualityScoreNoRhythm(d, max, cfg);
      factors.push({
        key: "contact_punctual",
        label: "联系准时度",
        score: round1(s),
        max,
        detail: `${d} 天前联系过 (还没有固定节奏, 暂按 ${cfg.noRhythm.cadenceDays} 天节律评估)`,
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
      const s = punctualityScoreNoRhythm(d, max, cfg);
      factors.push({
        key: "visit_punctual",
        label: "到店规律",
        score: round1(s),
        max,
        detail: `${d} 天前到过店 (还没有复购节奏, 暂按 ${cfg.noRhythm.cadenceDays} 天节律评估)`,
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
    band: bandOf(score, bands),
    bandLabel: bandLabel(score, bands),
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
/** @deprecated 用 `config.scoring.value.minTenureDays` */
export const VALUE_MIN_TENURE_DAYS =
  DEFAULT_RESOLVED_CONFIG.scoring.value.minTenureDays;

function scoreValue(
  input: ScoringInput,
  cfg: ValueConfig = DEFAULT_RESOLVED_CONFIG.scoring.value,
  bands: ReadonlyArray<ScoreBandConfig> = SCORE_BANDS,
): DimensionScore {
  const label = "价值潜力";
  const factors: ScoreFactor[] = [];
  const a = input.analysis;

  // 关系太短 → 数据不足, 不判 (返回 null 而不是低分)
  const tenureDays = daysBetween(input.relationshipStartAt, input.now);
  if (tenureDays < cfg.minTenureDays) {
    return {
      key: "value",
      label,
      score: null,
      band: null,
      bandLabel: bandLabel(null, bands),
      factors: [],
      missingReason: `认识才 ${tenureDays} 天, 还看不出价值潜力 (需 ≥ ${cfg.minTenureDays} 天)`,
    };
  }

  // 因子 1: 到店密度 —— 近 windowDays 天月均次数, 达 fullMonthly 满分
  {
    const vd = cfg.visitDensity;
    const since = new Date(input.now.getTime() - vd.windowDays * 86_400_000);
    const n = input.records.filter((r) => r.serviceDate >= since).length;
    const monthly = n / vd.monthsInWindow;
    const s = clamp((monthly / vd.fullMonthly) * vd.max, 0, vd.max);
    factors.push({
      key: "visit_density",
      label: "到店密度",
      score: round1(s),
      max: vd.max,
      detail: `近 ${vd.monthsInWindow} 个月到店 ${n} 次 (月均 ${round1(monthly)} 次)`,
    });
  }

  // 因子 2: 关系时长 —— 达 fullMonths 满分
  {
    const months = Math.max(0, daysBetween(input.relationshipStartAt, input.now) / 30);
    const s = clamp((months / cfg.tenure.fullMonths) * cfg.tenure.max, 0, cfg.tenure.max);
    factors.push({
      key: "tenure",
      label: "关系时长",
      score: round1(s),
      max: cfg.tenure.max,
      detail:
        months < 1
          ? "刚认识不久"
          : `已认识 ${Math.round(months)} 个月`,
    });
  }

  // 因子 3: 互动广度 —— 渠道**种类**数 (电话 / 微信 / 到店), 每种 perChannel 分
  {
    const channels = new Set(
      input.interactions
        .map((i) => (i.type === "holiday_greeting" ? "wechat" : i.type))
        .filter((t) => t === "phone" || t === "wechat" || t === "visit")
    );
    const s = clamp(channels.size * cfg.breadth.perChannel, 0, cfg.breadth.max);
    factors.push({
      key: "breadth",
      label: "互动广度",
      score: round1(s),
      max: cfg.breadth.max,
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
    band: bandOf(score, bands),
    bandLabel: bandLabel(score, bands),
    factors,
    missingReason: null,
  };
}

// ============================================
// 综合
// ============================================

/**
 * 默认综合权重: 关系温度最重 (它最直接决定"该不该投入")。
 * @deprecated 用 `config.scoring.weights` —— 权重可调。
 */
export const WEIGHTS: Record<"effect" | "engagement" | "value", number> =
  DEFAULT_RESOLVED_CONFIG.scoring.weights;

/**
 * 默认短板阈值: 维度分 < 此值 → 进 weakDimensions。
 * @deprecated 用 `config.scoring.weakDimensionThreshold`
 */
export const WEAK_DIMENSION_THRESHOLD =
  DEFAULT_RESOLVED_CONFIG.scoring.weakDimensionThreshold;

/**
 * 组装三维评分。
 *
 * @param config 可调参数 (阈值/权重/分档…)。默认 = DEFAULT_INSIGHT_CONFIG。
 *   将来 admin 页面的覆盖值也从这个口子进 (loadCustomerInsight 会传)。
 *   传进来的东西**会被 resolveInsightConfig 夹区间** (不受信输入)。
 */
export function buildCustomerScore(
  input: ScoringInput,
  config?: unknown,
): CustomerScore {
  const cfg = resolveInsightConfig(config);
  const sc = cfg.scoring;
  const WEIGHTS = sc.weights;

  const effect = scoreEffect(input.records, sc.effect, sc.bands);
  const engagement = scoreEngagement(input, sc.engagement, sc.bands);
  const value = scoreValue(input, sc.value, sc.bands);

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
        d.score !== null && d.score < sc.weakDimensionThreshold
    )
    .sort((a, b) => a.score - b.score)
    .map((d) => d.key);

  return {
    overall,
    overallBand: overall === null ? null : bandOf(overall, sc.bands),
    overallBandLabel: bandLabel(overall, sc.bands),
    effect,
    engagement,
    value,
    weakDimensions,
    scoringVersion: SCORING_VERSION,
    /** 参数配置版本 —— 分数 + 配置 + 算法三者一起才说明"这分怎么来的" */
    configVersion: sc.version,
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
  now: Date = new Date(),
  config?: unknown
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
  }, config);

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
  now: Date = new Date(),
  config?: unknown
): Promise<CustomerScore | null> {
  const snap = await loadCustomerScoringSnapshot(customerId, now, config);
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
