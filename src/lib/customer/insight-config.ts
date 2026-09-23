// ============================================
// 客户洞察 —— 全部可调参数 (单一真相源)
// ============================================
//
// 主人 2026-09-23 拍板「所有评分规则都变量化」。
//
// 为什么单独一个文件 + 为什么必须 **纯 JSON 可序列化**:
//   → 将来 admin 要开「评分规则调节页」(见 docs/backlog.md ⓪),
//     那一页的读写对象就是这份结构 (存 DB 一个 jsonb 字段, 覆盖这里的默认值)。
//   所以本文件里**不准出现函数 / Date / class** —— 只能是 number / string / 数组 / 对象。
//
// 三层优先级 (未来):
//   ① DEFAULT_INSIGHT_CONFIG (本文件, 兜底, 必须有)
//   ② DB app_config 覆盖 (admin 页写的, 逐字段 merge)
//   ③ 单次调用传入的 config (测试 / 特殊场景)
//
// 改配置要 +version —— 分数上带 configVersion, 让"改规则前后"的分数可区分
//   (不然销售会问"她昨天 78 今天 62, 是我看错了还是规则变了?")。
//
// ⚠ 校验: `resolveInsightConfig()` 会把外部传入的覆盖**逐字段夹回合法区间**。
//   配置来自 DB/UI 时不受信, 不校验的话一个手滑的 999 就能把全站分数打乱。
// ============================================

import type { ActionPriority, ActionRuleId } from "@/lib/customer/actions";

// ============================================
// 类型
// ============================================

export interface ScoreBandConfig {
  band: "excellent" | "good" | "fair" | "poor";
  /** 区间下界 (含) */
  min: number;
  label: string;
}

export interface EffectConfig {
  /** 健康分取最近 N 条 */
  recentN: number;
  /** 单次改善的三个指标权重 (缺项时自动重归一化) */
  metricWeights: { pain: number; sleep: number; mood: number };
  /** 三个因子满分 */
  factorMax: { latest: number; recentAvg: number; trend: number };
  /** 趋势: 最近 headN 次 vs 更早 tailN 次; delta 达 fullDelta 即满分 */
  trend: { headN: number; tailN: number; fullDelta: number };
  /** 改善值 → 分数 的映射: score = neutral + value * scale (value ∈ [-1,1]) */
  scale: { neutral: number; span: number };
}

export interface PunctualityConfig {
  /** ratio ≤ fullRatio → 满分 */
  fullRatio: number;
  /** ratio ≥ zeroRatio → 0 分; 中间线性 */
  zeroRatio: number;
}

export interface EngagementConfig {
  /** 四个因子的满分 (均分) */
  factorMax: number;
  punctuality: PunctualityConfig;
  /** 「还没有固定节奏」时的替身参数 */
  noRhythm: { cadenceDays: number; capRatio: number };
  depth: {
    windowDays: number;
    /** 加权次数达此值 → 满分 */
    fullWeighted: number;
    /** 各互动类型的权重 */
    weights: { visit: number; phone: number; wechat: number; holidayGreeting: number; other: number };
  };
  /** 从没建过任务时的中性比例 (不给满分: 没在管理 ≠ 健康) */
  taskHealth: { noTaskRatio: number };
}

export interface ValueConfig {
  visitDensity: {
    windowDays: number;
    /** 窗口相当于几个月 —— 用于把"窗口内次数"折成月均 (例: 180 天 = 6 个月) */
    monthsInWindow: number;
    /** 月均达此值 → 满分 */
    fullMonthly: number;
    max: number;
  };
  tenure: { fullMonths: number; max: number };
  breadth: { perChannel: number; max: number };
  /** 关系短于这个天数 → 不判价值 (返回 null「待评估」而不是低分) */
  minTenureDays: number;
}

export interface ScoringConfig {
  version: string;
  bands: ScoreBandConfig[];
  weights: { effect: number; engagement: number; value: number };
  /** 短板阈值: 维度分 < 此值 → 进 weakDimensions */
  weakDimensionThreshold: number;
  effect: EffectConfig;
  engagement: EngagementConfig;
  value: ValueConfig;
}

export interface ActionConfig {
  version: string;
  /** 复购窗口: 距上次到店 > 她的复购间隔 × 此倍数 → 约下次到店 */
  repurchaseOverdueFactor: number;
  /** 复购绝对兜底 (无节奏时): 距上次到店 ≥ 此天数 */
  repurchaseAbsoluteOverdueDays: number;
  /** 联系脱节: 距上次联系 > 她的联系间隔 × 此倍数 */
  contactGapFactor: number;
  /** 联系绝对兜底 (无节奏时): 距上次联系 ≥ 此天数 */
  contactAbsoluteGapDays: number;
  /** 建档多少天后「从没联系过」才催破冰 */
  neverContactedGraceDays: number;
  /** 生日提前窗口 (天); 与用户自设的提醒天数取小 */
  birthdayWindowDays: number;
  /** 首访后多少天做效果回访 */
  firstVisitFollowupDays: number;
  /** nextAdviceDate 提前多少天提醒 */
  adviceLeadDays: number;
  /** 各规则的优先级 (admin 可调: 把"生日关怀"提到 high 也合理) */
  priorities: Record<ActionRuleId, ActionPriority>;
}

/** 客户洞察的全部可调参数 = 评分 + 行动 (admin 一页编辑) */
export interface InsightConfig {
  scoring: ScoringConfig;
  actions: ActionConfig;
}

// ============================================
// 默认值 —— 与变量化之前的行为**逐项等价**
// ============================================
// ⚠ 改这里 = 改全站行为。要给某次调用特殊值, 传第二个参数, 别改默认值。

export const DEFAULT_INSIGHT_CONFIG: InsightConfig = {
  scoring: {
    version: "v1",
    bands: [
      { band: "excellent", min: 80, label: "优秀" },
      { band: "good", min: 60, label: "良好" },
      { band: "fair", min: 40, label: "一般" },
      { band: "poor", min: 0, label: "需关注" },
    ],
    weights: { effect: 0.3, engagement: 0.4, value: 0.3 },
    weakDimensionThreshold: 60,
    effect: {
      recentN: 5,
      metricWeights: { pain: 0.5, sleep: 0.3, mood: 0.2 },
      factorMax: { latest: 40, recentAvg: 40, trend: 20 },
      trend: { headN: 2, tailN: 3, fullDelta: 0.3 },
      scale: { neutral: 50, span: 50 },
    },
    engagement: {
      factorMax: 25,
      punctuality: { fullRatio: 1.0, zeroRatio: 2.5 },
      noRhythm: { cadenceDays: 30, capRatio: 0.6 },
      depth: {
        windowDays: 90,
        fullWeighted: 12,
        weights: { visit: 3, phone: 2, wechat: 1, holidayGreeting: 1, other: 1 },
      },
      taskHealth: { noTaskRatio: 0.6 },
    },
    value: {
      visitDensity: { windowDays: 180, monthsInWindow: 6, fullMonthly: 2, max: 40 },
      tenure: { fullMonths: 12, max: 30 },
      breadth: { perChannel: 10, max: 30 },
      minTenureDays: 30,
    },
  },
  actions: {
    version: "v1",
    repurchaseOverdueFactor: 1.2,
    repurchaseAbsoluteOverdueDays: 60,
    contactGapFactor: 1.5,
    contactAbsoluteGapDays: 45,
    neverContactedGraceDays: 1,
    birthdayWindowDays: 7,
    firstVisitFollowupDays: 7,
    adviceLeadDays: 0,
    priorities: {
      never_contacted: "high",
      repurchase_window: "high",
      task_overdue: "high",
      no_improvement: "high",
      contact_gap: "medium",
      birthday_window: "medium",
      first_visit_followup: "medium",
      advice_due: "medium",
      profile_incomplete: "low",
    },
  },
};

// ============================================
// 校验 / 合并 (配置来自 DB/UI 时不受信, 必须夹区间)
// ============================================

/** 取有限数字, 否则回落; 并夹到 [lo, hi] */
function pickNum(v: unknown, fallback: number, lo: number, hi: number): number {
  const n = typeof v === "number" && Number.isFinite(v) ? v : fallback;
  return Math.max(lo, Math.min(hi, n));
}

function pickStr(v: unknown, fallback: string, maxLen = 64): string {
  if (typeof v !== "string") return fallback;
  const t = v.trim().slice(0, maxLen);
  return t.length > 0 ? t : fallback;
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

const PRIORITIES: readonly ActionPriority[] = ["high", "medium", "low"];

/**
 * 把「外部覆盖」逐字段合并进默认配置, 并**夹回合法区间**。
 *
 * 设计要点:
 *   - 任何不认识 / 非法的字段 → 静默回落默认 (不抛错: 一个坏配置不该让详情页打不开)
 *   - 数值一律带上下界 (见各处 pickNum 的 lo/hi)
 *   - 权重类不强制归一化 (和不为 1 时由 buildCustomerScore 重归一化, 见那里的注释)
 */
export function resolveInsightConfig(override?: unknown): InsightConfig {
  const d = DEFAULT_INSIGHT_CONFIG;
  const o = isPlainObject(override) ? override : {};
  const os = isPlainObject(o.scoring) ? o.scoring : {};
  const oa = isPlainObject(o.actions) ? o.actions : {};

  const oBands = Array.isArray(os.bands) ? os.bands : null;
  const bands: ScoreBandConfig[] = oBands
    ? oBands
        .filter(
          (b): b is Record<string, unknown> =>
            isPlainObject(b) && typeof b.min === "number" && Number.isFinite(b.min),
        )
        .map((b) => {
          const band = d.scoring.bands.find((x) => x.band === b.band)?.band ?? "poor";
          return {
            band,
            min: pickNum(b.min, 0, 0, 100),
            label: pickStr(b.label, d.scoring.bands.find((x) => x.band === band)!.label, 16),
          };
        })
        .sort((a, b) => b.min - a.min)
    : d.scoring.bands;
  // 必须覆盖到 0, 否则 bandOf 会找不到档
  const safeBands =
    bands.length > 0 && bands[bands.length - 1].min === 0
      ? bands
      : [...bands, { band: "poor" as const, min: 0, label: "需关注" }];

  const oe = isPlainObject(os.effect) ? os.effect : {};
  const oem = isPlainObject(oe.metricWeights) ? oe.metricWeights : {};
  const oefm = isPlainObject(oe.factorMax) ? oe.factorMax : {};
  const oet = isPlainObject(oe.trend) ? oe.trend : {};
  const oes = isPlainObject(oe.scale) ? oe.scale : {};

  const og = isPlainObject(os.engagement) ? os.engagement : {};
  const ogp = isPlainObject(og.punctuality) ? og.punctuality : {};
  const ogn = isPlainObject(og.noRhythm) ? og.noRhythm : {};
  const ogd = isPlainObject(og.depth) ? og.depth : {};
  const ogdw = isPlainObject(ogd.weights) ? ogd.weights : {};
  const ogt = isPlainObject(og.taskHealth) ? og.taskHealth : {};

  const ov = isPlainObject(os.value) ? os.value : {};
  const ovd = isPlainObject(ov.visitDensity) ? ov.visitDensity : {};
  const ovt = isPlainObject(ov.tenure) ? ov.tenure : {};
  const ovb = isPlainObject(ov.breadth) ? ov.breadth : {};

  const op = isPlainObject(oa.priorities) ? oa.priorities : {};
  const priorities = { ...d.actions.priorities };
  for (const k of Object.keys(d.actions.priorities) as ActionRuleId[]) {
    const v = op[k];
    if (typeof v === "string" && (PRIORITIES as readonly string[]).includes(v)) {
      priorities[k] = v as ActionPriority;
    }
  }

  return {
    scoring: {
      version: pickStr(os.version, d.scoring.version),
      bands: safeBands,
      weights: {
        effect: pickNum(isPlainObject(os.weights) ? os.weights.effect : undefined, d.scoring.weights.effect, 0, 1),
        engagement: pickNum(isPlainObject(os.weights) ? os.weights.engagement : undefined, d.scoring.weights.engagement, 0, 1),
        value: pickNum(isPlainObject(os.weights) ? os.weights.value : undefined, d.scoring.weights.value, 0, 1),
      },
      weakDimensionThreshold: pickNum(os.weakDimensionThreshold, d.scoring.weakDimensionThreshold, 0, 100),
      effect: {
        recentN: Math.round(pickNum(oe.recentN, d.scoring.effect.recentN, 1, 50)),
        metricWeights: {
          pain: pickNum(oem.pain, d.scoring.effect.metricWeights.pain, 0, 1),
          sleep: pickNum(oem.sleep, d.scoring.effect.metricWeights.sleep, 0, 1),
          mood: pickNum(oem.mood, d.scoring.effect.metricWeights.mood, 0, 1),
        },
        factorMax: {
          latest: pickNum(oefm.latest, d.scoring.effect.factorMax.latest, 0, 100),
          recentAvg: pickNum(oefm.recentAvg, d.scoring.effect.factorMax.recentAvg, 0, 100),
          trend: pickNum(oefm.trend, d.scoring.effect.factorMax.trend, 0, 100),
        },
        trend: {
          headN: Math.round(pickNum(oet.headN, d.scoring.effect.trend.headN, 1, 20)),
          tailN: Math.round(pickNum(oet.tailN, d.scoring.effect.trend.tailN, 1, 20)),
          fullDelta: pickNum(oet.fullDelta, d.scoring.effect.trend.fullDelta, 0.01, 2),
        },
        scale: {
          neutral: pickNum(oes.neutral, d.scoring.effect.scale.neutral, 0, 100),
          span: pickNum(oes.span, d.scoring.effect.scale.span, 1, 100),
        },
      },
      engagement: {
        factorMax: pickNum(og.factorMax, d.scoring.engagement.factorMax, 1, 100),
        punctuality: {
          fullRatio: pickNum(ogp.fullRatio, d.scoring.engagement.punctuality.fullRatio, 0, 10),
          zeroRatio: pickNum(ogp.zeroRatio, d.scoring.engagement.punctuality.zeroRatio, 0.1, 20),
        },
        noRhythm: {
          cadenceDays: pickNum(ogn.cadenceDays, d.scoring.engagement.noRhythm.cadenceDays, 1, 365),
          capRatio: pickNum(ogn.capRatio, d.scoring.engagement.noRhythm.capRatio, 0, 1),
        },
        depth: {
          windowDays: pickNum(ogd.windowDays, d.scoring.engagement.depth.windowDays, 1, 3650),
          fullWeighted: pickNum(ogd.fullWeighted, d.scoring.engagement.depth.fullWeighted, 1, 1000),
          weights: {
            visit: pickNum(ogdw.visit, d.scoring.engagement.depth.weights.visit, 0, 100),
            phone: pickNum(ogdw.phone, d.scoring.engagement.depth.weights.phone, 0, 100),
            wechat: pickNum(ogdw.wechat, d.scoring.engagement.depth.weights.wechat, 0, 100),
            holidayGreeting: pickNum(ogdw.holidayGreeting, d.scoring.engagement.depth.weights.holidayGreeting, 0, 100),
            other: pickNum(ogdw.other, d.scoring.engagement.depth.weights.other, 0, 100),
          },
        },
        taskHealth: {
          noTaskRatio: pickNum(ogt.noTaskRatio, d.scoring.engagement.taskHealth.noTaskRatio, 0, 1),
        },
      },
      value: {
        visitDensity: {
          windowDays: pickNum(ovd.windowDays, d.scoring.value.visitDensity.windowDays, 1, 3650),
          monthsInWindow: pickNum(ovd.monthsInWindow, d.scoring.value.visitDensity.monthsInWindow, 1, 365),
          fullMonthly: pickNum(ovd.fullMonthly, d.scoring.value.visitDensity.fullMonthly, 0.1, 100),
          max: pickNum(ovd.max, d.scoring.value.visitDensity.max, 0, 100),
        },
        tenure: {
          fullMonths: pickNum(ovt.fullMonths, d.scoring.value.tenure.fullMonths, 1, 600),
          max: pickNum(ovt.max, d.scoring.value.tenure.max, 0, 100),
        },
        breadth: {
          perChannel: pickNum(ovb.perChannel, d.scoring.value.breadth.perChannel, 0, 100),
          max: pickNum(ovb.max, d.scoring.value.breadth.max, 0, 100),
        },
        minTenureDays: pickNum(ov.minTenureDays, d.scoring.value.minTenureDays, 0, 3650),
      },
    },
    actions: {
      version: pickStr(oa.version, d.actions.version),
      repurchaseOverdueFactor: pickNum(oa.repurchaseOverdueFactor, d.actions.repurchaseOverdueFactor, 0.1, 10),
      repurchaseAbsoluteOverdueDays: pickNum(oa.repurchaseAbsoluteOverdueDays, d.actions.repurchaseAbsoluteOverdueDays, 1, 3650),
      contactGapFactor: pickNum(oa.contactGapFactor, d.actions.contactGapFactor, 0.1, 10),
      contactAbsoluteGapDays: pickNum(oa.contactAbsoluteGapDays, d.actions.contactAbsoluteGapDays, 1, 3650),
      neverContactedGraceDays: pickNum(oa.neverContactedGraceDays, d.actions.neverContactedGraceDays, 0, 365),
      birthdayWindowDays: pickNum(oa.birthdayWindowDays, d.actions.birthdayWindowDays, 0, 365),
      firstVisitFollowupDays: pickNum(oa.firstVisitFollowupDays, d.actions.firstVisitFollowupDays, 0, 365),
      adviceLeadDays: pickNum(oa.adviceLeadDays, d.actions.adviceLeadDays, 0, 365),
      priorities,
    },
  };
}

/** 默认配置 (resolve 一次, 走同一套校验路径 —— 保证默认值本身也合法) */
export const DEFAULT_RESOLVED_CONFIG: InsightConfig = resolveInsightConfig();
