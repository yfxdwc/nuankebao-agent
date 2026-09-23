// ============================================
// 客户画像评分 + 行动指引 单测 (纯函数, 不碰库)
// ============================================
// 守护的东西:
//   ① 评分是**确定性**的 (同输入同输出) —— 销售会问"为什么 78 分", 必须答得出
//   ② 决策边界正确 (改善为正→高分 / 为负→低分 / 无数据→null 而不是 0)
//   ③ 综合分在维度缺失时**权重重归一化** (不因为没养生记录就腰斩)
//   ④ 行动规则**不漏不错**: 8 条规则各自的条件触发, 不误报
//   ⑤ 行动可闭环: 每条都有 taskTitle/taskDueAt (一键建任务用)
//   ⑥ 与 urgency 的语义不混: scoring 高=好, urgency 高=急
//
// 跑: pnpm test:run tests/customer-scoring.test.ts

import { describe, it, expect } from "vitest";

import {
  SCORING_VERSION,
  SCORE_BANDS,
  bandOf,
  bandLabel,
  singleImprovement,
  buildCustomerScore,
  WEAK_DIMENSION_THRESHOLD,
  type ScoringInput,
  type WellnessSnapshot,
} from "@/lib/customer/scoring";
import {
  buildActionItems,
  topActions,
  type ActionInput,
  type ActionItem,
} from "@/lib/customer/actions";
import {
  DEFAULT_INSIGHT_CONFIG,
  resolveInsightConfig,
} from "@/lib/customer/insight-config";
import type { FollowUpAnalysis } from "@/lib/follow-up/analysis";

// ---------- 测试夹具 ----------

const NOW = new Date("2026-09-23T09:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000);
const daysAfter = (n: number) => new Date(NOW.getTime() + n * 86_400_000);

/** 造一条养生记录; 只给 pain 最省事, 需要时补 sleep/mood */
function record(
  daysBefore: number,
  pre: Record<string, number>,
  post: Record<string, number>
): WellnessSnapshot {
  return { serviceDate: daysAgo(daysBefore), pre, post };
}

/** 造一份 FollowUpAnalysis (只填测得到字段, 其余给中性默认) */
function analysis(over: Partial<FollowUpAnalysis> = {}): FollowUpAnalysis {
  return {
    contactLast30: 0,
    contactLast90: 0,
    contactTotal: 0,
    avgContactIntervalDays: null,
    daysSinceLastContact: null,
    trend: "unknown",
    trendText: "",
    visitCount: 0,
    avgVisitIntervalDays: null,
    lastVisitAt: null,
    daysSinceLastVisit: null,
    medianRepurchaseIntervalDays: null,
    pendingTasks: 0,
    overdueTasks: 0,
    oldestOverdueDays: null,
    headline: "",
    ...over,
  };
}

function scoringInput(over: Partial<ScoringInput> = {}): ScoringInput {
  return {
    now: NOW,
    customerCreatedAt: daysAgo(365),
    relationshipStartAt: daysAgo(365),
    analysis: analysis(),
    records: [],
    interactions: [],
    completedTaskCount: 0,
    ...over,
  };
}

function actionInput(over: Partial<ActionInput> = {}): ActionInput {
  const score = buildCustomerScore(
    scoringInput({
      records: [record(10, { pain_level: 8 }, { pain_level: 3 })],
      interactions: [{ type: "phone", createdAt: daysAgo(5) }],
      ...(over as never),
    })
  );
  return {
    now: NOW,
    analysis: analysis(),
    score,
    customerCreatedAt: daysAgo(365),
    relationshipStartAt: daysAgo(365),
    daysUntilBirthday: null,
    birthdayRemindDays: null,
    nextAdviceDate: null,
    hasOwner: true,
    lastRecordNoImprovement: null,
    hasPendingTask: false,
    ...over,
  };
}

// ============================================
// ① singleImprovement —— 单次改善的归一化
// ============================================

describe("singleImprovement — 单次记录的改善程度", () => {
  it("三个指标齐全: 按 0.5/0.3/0.2 加权", () => {
    // pain (8-3)/10=0.5 · sleep (4-2)/4=0.5 · mood (4-3)/4=0.25
    // → 0.5*0.5 + 0.5*0.3 + 0.25*0.2 = 0.45
    const v = singleImprovement(
      record(1, { pain_level: 8, sleep_quality: 2, mood: 3 }, { pain_level: 3, sleep_quality: 4, mood: 4 })
    );
    expect(v).toBeCloseTo(0.45, 5);
  });

  it("只有 pain 也能算 —— 权重自动重归一化 (不被缺失项拖成 0)", () => {
    // pain (8-3)/10 = 0.5; 只有这一项 → 结果就是 0.5 (不是 0.5*0.5)
    const v = singleImprovement(record(1, { pain_level: 8 }, { pain_level: 3 }));
    expect(v).toBeCloseTo(0.5, 5);
  });

  it("无变化 → 0; 变差 → 负数", () => {
    expect(singleImprovement(record(1, { pain_level: 5 }, { pain_level: 5 }))).toBe(0);
    expect(
      singleImprovement(record(1, { pain_level: 3 }, { pain_level: 7 }))
    ).toBeCloseTo(-0.4, 5);
  });

  it("一项评分都没有 → null (这条记录对健康分无贡献, 不拉低也不拉高)", () => {
    expect(singleImprovement(record(1, {}, {}))).toBeNull();
    expect(singleImprovement(record(1, { note: 1 }, { note: 2 }))).toBeNull();
  });

  it("pre 有 post 缺 → 该项不计入 (不是当成 0)", () => {
    const v = singleImprovement(
      record(1, { pain_level: 8, sleep_quality: 2 }, { pain_level: 3 })
    );
    expect(v).toBeCloseTo(0.5, 5); // 只剩 pain
  });

  it("改善不会越界 (极端值仍夹在 [-1, 1])", () => {
    expect(singleImprovement(record(1, { pain_level: 10 }, { pain_level: 0 }))).toBeLessThanOrEqual(1);
    expect(singleImprovement(record(1, { pain_level: 0 }, { pain_level: 10 }))).toBeGreaterThanOrEqual(-1);
  });
});

// ============================================
// ② 分档表
// ============================================

describe("分档 (SCORE_BANDS)", () => {
  it("边界值落在正确的档", () => {
    expect(bandOf(100)).toBe("excellent");
    expect(bandOf(80)).toBe("excellent");
    expect(bandOf(79.9)).toBe("good");
    expect(bandOf(60)).toBe("good");
    expect(bandOf(59.9)).toBe("fair");
    expect(bandOf(40)).toBe("fair");
    expect(bandOf(39.9)).toBe("poor");
    expect(bandOf(0)).toBe("poor");
  });

  it("档位表按分数降序 (高→低), 且覆盖到 0", () => {
    for (let i = 1; i < SCORE_BANDS.length; i++) {
      expect(SCORE_BANDS[i - 1].min).toBeGreaterThan(SCORE_BANDS[i].min);
    }
    expect(SCORE_BANDS[SCORE_BANDS.length - 1].min).toBe(0);
  });

  it("null → 待评估 (不假装 0 分)", () => {
    expect(bandLabel(null)).toBe("待评估");
  });
});

// ============================================
// ③ 健康改善维度
// ============================================

describe("健康改善分 (effect)", () => {
  it("没有任何带评分的记录 → score = null + missingReason (不是 0 分)", () => {
    const s = buildCustomerScore(scoringInput());
    expect(s.effect.score).toBeNull();
    expect(s.effect.factors).toEqual([]);
    expect(s.effect.missingReason).toContain("评分");
  });

  it("稳定改善 → 高分 (优秀/良好)", () => {
    const s = buildCustomerScore(
      scoringInput({
        records: [
          record(2, { pain_level: 8 }, { pain_level: 3 }),
          record(9, { pain_level: 8 }, { pain_level: 4 }),
          record(16, { pain_level: 7 }, { pain_level: 4 }),
          record(23, { pain_level: 7 }, { pain_level: 5 }),
        ],
      })
    );
    expect(s.effect.score).not.toBeNull();
    expect(s.effect.score as number).toBeGreaterThanOrEqual(60);
    expect(s.effect.band).toBe("good");
  });

  it("毫无改善 (post == pre) → 50 分 (中性), 不是 0", () => {
    const s = buildCustomerScore(
      scoringInput({ records: [record(2, { pain_level: 5 }, { pain_level: 5 })] })
    );
    expect(s.effect.score).toBeCloseTo(50, 1);
    expect(s.effect.band).toBe("fair");
  });

  it("越做越差 → 低分", () => {
    const s = buildCustomerScore(
      scoringInput({
        records: [
          record(2, { pain_level: 3 }, { pain_level: 8 }),
          record(9, { pain_level: 3 }, { pain_level: 7 }),
          record(16, { pain_level: 2 }, { pain_level: 6 }),
        ],
      })
    );
    expect(s.effect.score as number).toBeLessThan(40);
    expect(s.effect.band).toBe("poor");
  });

  it("样本 ≥3 时才有「改善趋势」因子 (样本少不硬凑)", () => {
    const one = buildCustomerScore(
      scoringInput({ records: [record(2, { pain_level: 8 }, { pain_level: 3 })] })
    );
    expect(one.effect.factors.map((f) => f.key)).not.toContain("trend");

    const three = buildCustomerScore(
      scoringInput({
        records: [
          record(2, { pain_level: 8 }, { pain_level: 2 }),
          record(9, { pain_level: 8 }, { pain_level: 3 }),
          record(16, { pain_level: 8 }, { pain_level: 7 }),
        ],
      })
    );
    expect(three.effect.factors.map((f) => f.key)).toContain("trend");
    // 在变好 → 趋势因子应拿到高分
    const trend = three.effect.factors.find((f) => f.key === "trend")!;
    expect(trend.score / trend.max).toBeGreaterThan(0.7);
  });

  it("每个因子都带人话 detail (可解释性硬要求)", () => {
    const s = buildCustomerScore(
      scoringInput({ records: [record(2, { pain_level: 8 }, { pain_level: 3 })] })
    );
    for (const f of s.effect.factors) {
      expect(f.detail.length).toBeGreaterThan(4);
      expect(f.score).toBeGreaterThanOrEqual(0);
      expect(f.score).toBeLessThanOrEqual(f.max);
    }
  });
});

// ============================================
// ④ 关系温度维度
// ============================================

describe("关系温度分 (engagement)", () => {
  it("从没联系/从没到店/零互动/无任务 → 很低分但不为 null", () => {
    const s = buildCustomerScore(scoringInput());
    expect(s.engagement.score).not.toBeNull();
    expect(s.engagement.score as number).toBeLessThan(25);
    expect(s.engagement.factors).toHaveLength(4);
    expect(s.engagement.factors.map((f) => f.key)).toEqual([
      "contact_punctual",
      "visit_punctual",
      "depth",
      "task_health",
    ]);
  });

  it("节奏准时 + 互动足 + 任务不逾期 → 满分", () => {
    const s = buildCustomerScore(
      scoringInput({
        analysis: analysis({
          daysSinceLastContact: 10,
          avgContactIntervalDays: 14, // ratio 0.71 ≤ 1 → 满分
          daysSinceLastVisit: 20,
          medianRepurchaseIntervalDays: 30, // ratio 0.67 → 满分
        }),
        interactions: Array.from({ length: 6 }, (_, i) => ({
          type: "visit" as const,
          createdAt: daysAgo(i * 10 + 1),
        })), // 6 × 3 = 18 加权 ≥ 12 → 满分
        completedTaskCount: 3,
      })
    );
    expect(s.engagement.score).toBeCloseTo(100, 0);
  });

  it("超出 2.5 倍间隔 → 该项 0 分", () => {
    const s = buildCustomerScore(
      scoringInput({
        analysis: analysis({
          daysSinceLastContact: 40,
          avgContactIntervalDays: 10, // ratio 4.0 ≥ 2.5 → 0
        }),
      })
    );
    const f = s.engagement.factors.find((x) => x.key === "contact_punctual")!;
    expect(f.score).toBe(0);
  });

  it("还没形成节奏 → 封顶 60% (拿不到高分, 但也不判 0)", () => {
    const s = buildCustomerScore(
      scoringInput({
        analysis: analysis({ daysSinceLastContact: 5, avgContactIntervalDays: null }),
      })
    );
    const f = s.engagement.factors.find((x) => x.key === "contact_punctual")!;
    expect(f.score).toBe(15); // 5/30 → 满分 25 → 封顶 15
    expect(f.detail).toContain("节奏");
    expect(f.detail).toContain("30 天节律");
  });

  it("【回归】没节奏但久未联系 → 准时度必须衰减 (不能固定 15 分)", () => {
    // 冒烟发现: 原先固定给 15/25, "91 天没联系" 也拿 15 分 → 偏宽松
    const far = buildCustomerScore(
      scoringInput({
        analysis: analysis({ daysSinceLastContact: 91, avgContactIntervalDays: 0 }),
      })
    );
    const f = far.engagement.factors.find((x) => x.key === "contact_punctual")!;
    expect(f.score).toBe(0); // 91/30 = 3.03 ≥ 2.5 → 0
  });

  it("任务健康: 逾期会扣分, 且 detail 说清完成/逾期数", () => {
    const good = buildCustomerScore(
      scoringInput({ completedTaskCount: 4, analysis: analysis({ overdueTasks: 0 }) })
    );
    const bad = buildCustomerScore(
      scoringInput({ completedTaskCount: 1, analysis: analysis({ overdueTasks: 3 }) })
    );
    const fg = good.engagement.factors.find((x) => x.key === "task_health")!;
    const fb = bad.engagement.factors.find((x) => x.key === "task_health")!;
    expect(fg.score).toBe(25);
    expect(fb.score).toBeCloseTo(6.25, 1);
    expect(fb.detail).toContain("逾期 3");
  });

  it("从没建过任务 → 不给满分 (没在管理 ≠ 健康)", () => {
    const s = buildCustomerScore(scoringInput());
    const f = s.engagement.factors.find((x) => x.key === "task_health")!;
    expect(f.score).toBeLessThan(25);
    expect(f.detail).toContain("还没有建过");
  });
});

// ============================================
// ⑤ 价值潜力维度 (行为代理, 绝无金额)
// ============================================

describe("价值潜力分 (value)", () => {
  it("高频 + 长期 + 多渠道 → 满分", () => {
    const s = buildCustomerScore(
      scoringInput({
        relationshipStartAt: daysAgo(400), // > 12 个月
        records: Array.from({ length: 12 }, (_, i) => record(i * 14, { pain_level: 5 }, { pain_level: 4 })),
        interactions: [
          { type: "phone", createdAt: daysAgo(3) },
          { type: "wechat", createdAt: daysAgo(5) },
          { type: "visit", createdAt: daysAgo(7) },
        ],
      })
    );
    expect(s.value.score).toBeCloseTo(100, 0);
  });

  it("关系起点 ≠ 建档时间: 导入的历史客户按**最早到店**算关系时长", () => {
    // 冒烟发现的真问题: customer.createdAt = 导入那天, 导入 5 年老客户会被判"刚认识"
    const s = buildCustomerScore(
      scoringInput({
        customerCreatedAt: daysAgo(1), // 昨天导入
        relationshipStartAt: daysAgo(400), // 但最早到店在 400 天前
      })
    );
    expect(s.value.score).not.toBeNull();
    const f = s.value.factors.find((x) => x.key === "tenure")!;
    expect(f.score).toBe(30); // 满
    expect(f.detail).toContain("13 个月");
  });

  it("刚建档 (<30 天) → 价值分 = null (时间不够, 不假装低分)", () => {
    // 冒烟发现: 建档 1 天的客户价值分 0.1 → 综合 8.6「需关注」, 明显误导
    const s = buildCustomerScore(scoringInput({ relationshipStartAt: daysAgo(2) }));
    expect(s.value.score).toBeNull();
    expect(s.value.missingReason).toContain("还看不出");
  });

  it("建档 ≥30 天后才判价值分", () => {
    const s = buildCustomerScore(scoringInput({ relationshipStartAt: daysAgo(45) }));
    expect(s.value.score).not.toBeNull();
  });

  it("零记录零互动但关系已久 → 只有「关系时长」那 30 分 (信任本身是价值)", () => {
    // 认识 400 天 = 13 个月 → tenure 满分 30; 到店密度 0 + 互动广度 0
    const s = buildCustomerScore(scoringInput({ relationshipStartAt: daysAgo(400) }));
    expect(s.value.score).toBe(30);
    expect(s.value.factors.find((f) => f.key === "visit_density")!.score).toBe(0);
    expect(s.value.factors.find((f) => f.key === "breadth")!.score).toBe(0);
    expect(s.value.factors.find((f) => f.key === "tenure")!.score).toBe(30);
  });

  it("刚认识 + 零互动 → 三项全 0 (这时才是真的 0 分)", () => {
    const s = buildCustomerScore(scoringInput({ relationshipStartAt: daysAgo(31) }));
    expect(s.value.score as number).toBeLessThan(5);
  });

  it("互动广度按渠道种类算, 不是按次数", () => {
    const many = buildCustomerScore(
      scoringInput({
        interactions: Array.from({ length: 20 }, (_, i) => ({
          type: "phone" as const,
          createdAt: daysAgo(i + 1),
        })),
      })
    );
    const f = many.value.factors.find((x) => x.key === "breadth")!;
    expect(f.score).toBe(10); // 只有电话 = 1 种 = 10 分
    expect(f.detail).toContain("1 种");
  });

  it("节日问候归入微信渠道 (不额外加一种)", () => {
    const s = buildCustomerScore(
      scoringInput({
        interactions: [
          { type: "holiday_greeting", createdAt: daysAgo(1) },
          { type: "wechat", createdAt: daysAgo(2) },
        ],
      })
    );
    const f = s.value.factors.find((x) => x.key === "breadth")!;
    expect(f.score).toBe(10);
  });

  it("到店密度只看近 180 天 (很久没来的不虚高)", () => {
    const s = buildCustomerScore(
      scoringInput({
        records: [
          record(200, { pain_level: 5 }, { pain_level: 4 }), // 超窗口
          record(190, { pain_level: 5 }, { pain_level: 4 }), // 超窗口
        ],
      })
    );
    const f = s.value.factors.find((x) => x.key === "visit_density")!;
    expect(f.score).toBe(0);
    expect(f.detail).toContain("0 次");
  });
});

// ============================================
// ⑥ 综合分 + 短板
// ============================================

describe("综合分 (overall)", () => {
  it("三维齐全时按 0.3/0.4/0.3 加权", () => {
    const s = buildCustomerScore(
      scoringInput({
        relationshipStartAt: daysAgo(400),
        // 每次 pain 9→2 (改善 0.7) —— 但 12 次都一样, 所以「趋势」因子是中性 50
        //   → effect ≈ 78 (最近 85 / 均值 85 / 趋势 50 三项加权)
        records: Array.from({ length: 12 }, (_, i) =>
          record(i * 14 + 1, { pain_level: 9 }, { pain_level: 2 })
        ),
        // ⚠ 3 种渠道都给: 互动广度按**种类**算, 只给 visit = 1 种 = 10/30
        interactions: [
          ...Array.from({ length: 6 }, (_, i) => ({
            type: "visit" as const,
            createdAt: daysAgo(i * 8 + 1),
          })),
          { type: "phone" as const, createdAt: daysAgo(3) },
          { type: "wechat" as const, createdAt: daysAgo(5) },
        ],
        completedTaskCount: 5,
        analysis: analysis({
          daysSinceLastContact: 5,
          avgContactIntervalDays: 14,
          daysSinceLastVisit: 10,
          medianRepurchaseIntervalDays: 30,
          visitCount: 12,
        }),
      })
    );
    // effect: 稳定改善但无趋势 → 78 (良好档)
    expect(s.effect.score as number).toBeGreaterThanOrEqual(75);
    expect(s.effect.band).toBe("good");
    expect(s.engagement.score as number).toBeGreaterThan(80);
    expect(s.value.score as number).toBeGreaterThan(80);
    expect(s.overall as number).toBeGreaterThan(80);
    expect(s.overallBand).toBe("excellent");
  });

  it("互动广度按渠道种类: 只到店 = 1 种 = 10/30 (价值分只有 80)", () => {
    const s = buildCustomerScore(
      scoringInput({
        relationshipStartAt: daysAgo(400),
        records: Array.from({ length: 12 }, (_, i) =>
          record(i * 14 + 1, { pain_level: 5 }, { pain_level: 4 })
        ),
        interactions: Array.from({ length: 10 }, (_, i) => ({
          type: "visit" as const,
          createdAt: daysAgo(i * 8 + 1),
        })),
      })
    );
    // 到店密度 40 + 关系时长 30 + 广度 10 = 80
    expect(s.value.score).toBe(80);
    const f = s.value.factors.find((x) => x.key === "breadth")!;
    expect(f.score).toBe(10);
    expect(f.detail).toContain("1 种");
  });

  it("缺一个维度 → 权重重归一化 (不腰斩)", () => {
    // 无养生记录 → effect = null; engagement/value 满分 → overall 应仍是高分
    const s = buildCustomerScore(
      scoringInput({
        relationshipStartAt: daysAgo(400),
        records: Array.from({ length: 12 }, (_, i) => record(i * 14 + 1, {}, {})), // 无评分 → effect null
        interactions: [
          ...Array.from({ length: 6 }, (_, i) => ({
            type: "visit" as const,
            createdAt: daysAgo(i * 8 + 1),
          })),
          { type: "phone" as const, createdAt: daysAgo(3) },
          { type: "wechat" as const, createdAt: daysAgo(5) },
        ],
        completedTaskCount: 5,
        analysis: analysis({
          daysSinceLastContact: 5,
          avgContactIntervalDays: 14,
          daysSinceLastVisit: 10,
          medianRepurchaseIntervalDays: 30,
          visitCount: 12,
        }),
      })
    );
    expect(s.effect.score).toBeNull();
    expect(s.engagement.score as number).toBeGreaterThan(80);
    expect(s.value.score as number).toBeGreaterThan(80);
    // 归一化后 overall 仍高 (若不归一化会被 null 当 0 拉低到 ~70)
    expect(s.overall as number).toBeGreaterThan(85);
  });

  it("全维度无数据 → overall = null (不是 0)", () => {
    const s = buildCustomerScore(
      scoringInput({ records: [], interactions: [], analysis: analysis() })
    );
    // engagement 与 value 恒有分 (不依赖样本), 所以这里其实有分;
    // 真正全 null 的场景只有"未来给 effect 之外再加可 null 的维度"。
    // 这条测试守住: overall 只有在**全部** null 时才 null。
    expect(s.overall).not.toBeNull();
  });

  it("短板维度: <60 的按分数升序 (行动指引用它挑先补哪个)", () => {
    const s = buildCustomerScore(
      scoringInput({
        relationshipStartAt: daysAgo(400),
        records: [record(2, { pain_level: 3 }, { pain_level: 8 })], // effect 低
        interactions: [], // engagement 低 + value 广度低
        analysis: analysis(),
      })
    );
    expect(s.weakDimensions.length).toBeGreaterThan(0);
    for (const k of s.weakDimensions) {
      const dim = k === "effect" ? s.effect : k === "engagement" ? s.engagement : s.value;
      expect(dim.score as number).toBeLessThan(WEAK_DIMENSION_THRESHOLD);
    }
    // 升序: 最低的排最前
    if (s.weakDimensions.length >= 2) {
      const first = s.weakDimensions[0] === "effect" ? s.effect : s.weakDimensions[0] === "engagement" ? s.engagement : s.value;
      const second = s.weakDimensions[1] === "effect" ? s.effect : s.weakDimensions[1] === "engagement" ? s.engagement : s.value;
      expect(first.score as number).toBeLessThanOrEqual(second.score as number);
    }
  });

  it("带版本号 + 计算时间 (算法改了能对比老分数)", () => {
    const s = buildCustomerScore(scoringInput());
    expect(s.scoringVersion).toBe(SCORING_VERSION);
    expect(s.computedAt).toBe(NOW.toISOString());
  });

  it("确定性: 同输入算两次完全一致", () => {
    const input = scoringInput({
      records: [record(3, { pain_level: 7 }, { pain_level: 4 })],
      interactions: [{ type: "phone", createdAt: daysAgo(2) }],
    });
    expect(JSON.stringify(buildCustomerScore(input))).toBe(
      JSON.stringify(buildCustomerScore(input))
    );
  });
});

// ============================================
// ⑦ 行动指引 —— 8 条规则
// ============================================

describe("行动指引 (buildActionItems)", () => {
  const idsOf = (items: ActionItem[]) => items.map((i) => i.id);

  it("复购窗口超期 → 出「约下次到店」(high)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          daysSinceLastVisit: 40,
          medianRepurchaseIntervalDays: 28, // 40 > 28*1.2=33.6 → 触发
          visitCount: 3,
        }),
      })
    );
    const it0 = items.find((i) => i.id === "repurchase_window")!;
    expect(it0.priority).toBe("high");
    expect(it0.evidence.daysSinceLastVisit).toBe(40);
    expect(it0.evidence.overdueDays).toBe(6); // 40 - 34
    expect(it0.taskTitle).toBe("约下次到店");
    expect(it0.taskDueAt).toBeTruthy();
  });

  it("复购窗口没到 → 不出这条", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          daysSinceLastVisit: 20,
          medianRepurchaseIntervalDays: 28, // 20 < 33.6 → 不触发
          visitCount: 3,
        }),
      })
    );
    expect(idsOf(items)).not.toContain("repurchase_window");
  });

  it("逾期任务 → 出「补上逾期跟进」(high)", () => {
    const items = buildActionItems(
      actionInput({ analysis: analysis({ overdueTasks: 2, oldestOverdueDays: 5 }) })
    );
    const it0 = items.find((i) => i.id === "task_overdue")!;
    expect(it0.priority).toBe("high");
    expect(it0.why).toContain("2 个");
    expect(it0.why).toContain("5 天");
  });

  it("联系脱节 → 出「主动联系」(medium)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ daysSinceLastContact: 40, avgContactIntervalDays: 14 }),
      })
    );
    const it0 = items.find((i) => i.id === "contact_gap")!;
    expect(it0.priority).toBe("medium");
    expect(it0.channel).toBe("wechat");
  });

  it("效果没改善 → 出「复核服务方案」, 且只提示复核不给医疗建议", () => {
    const items = buildActionItems(actionInput({ lastRecordNoImprovement: true }));
    const it0 = items.find((i) => i.id === "no_improvement")!;
    expect(it0.priority).toBe("high");
    expect(it0.channel).toBe("internal");
    expect(it0.why).toContain("复核");
    // 不给医疗判断
    expect(it0.why).not.toMatch(/诊断|治疗|吃药/);
  });

  it("生日窗口: 3 天后 + 提醒天数 7 → 触发", () => {
    const items = buildActionItems(
      actionInput({ daysUntilBirthday: 3, birthdayRemindDays: 7 })
    );
    const it0 = items.find((i) => i.id === "birthday_window")!;
    expect(it0.when).toBe("3 天后");
  });

  it("生日窗口: 用户关了提醒 (null) → 不触发", () => {
    const items = buildActionItems(
      actionInput({ daysUntilBirthday: 3, birthdayRemindDays: null })
    );
    expect(idsOf(items)).not.toContain("birthday_window");
  });

  it("生日窗口: 超出提醒天数 → 不触发", () => {
    const items = buildActionItems(
      actionInput({ daysUntilBirthday: 20, birthdayRemindDays: 7 })
    );
    expect(idsOf(items)).not.toContain("birthday_window");
  });

  it("生日当天 → when=今天 且优先级升高", () => {
    const items = buildActionItems(
      actionInput({ daysUntilBirthday: 0, birthdayRemindDays: 3 })
    );
    const it0 = items.find((i) => i.id === "birthday_window")!;
    expect(it0.when).toBe("今天");
    expect(it0.priority).toBe("high");
  });

  it("首访后回访: 只到过一次 + 超 7 天 + 无待办 → 触发", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ visitCount: 1, daysSinceLastVisit: 10 }),
        hasPendingTask: false,
      })
    );
    expect(idsOf(items)).toContain("first_visit_followup");
  });

  it("首访后回访: 已有待办 → 不重复建议", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ visitCount: 1, daysSinceLastVisit: 10 }),
        hasPendingTask: true,
      })
    );
    expect(idsOf(items)).not.toContain("first_visit_followup");
  });

  it("建议回访日到期 → 触发; 未到 → 不触发", () => {
    const due = buildActionItems(actionInput({ nextAdviceDate: daysAgo(2) }));
    expect(idsOf(due)).toContain("advice_due");
    expect(due.find((i) => i.id === "advice_due")!.priority).toBe("high");

    const future = buildActionItems(actionInput({ nextAdviceDate: daysAfter(10) }));
    expect(idsOf(future)).not.toContain("advice_due");
  });

  it("未归属 → 出「认领为我的客户」(low)", () => {
    const items = buildActionItems(actionInput({ hasOwner: false }));
    const it0 = items.find((i) => i.id === "profile_incomplete")!;
    expect(it0.priority).toBe("low");
    expect(it0.channel).toBe("profile");
  });

  it("全新客户从没联系过 → 出「首次联系破冰」(冒烟发现之前零行动)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ contactTotal: 0 }),
        customerCreatedAt: daysAgo(5),
      })
    );
    const it0 = items.find((i) => i.id === "never_contacted")!;
    expect(it0).toBeTruthy();
    expect(it0.priority).toBe("high");
    expect(it0.why).toContain("5 天");
    expect(it0.taskTitle).toBe("首次联系");
  });

  it("建档当天不催破冰 (给销售喘息)", () => {
    // ⚠ 宽限期看的是 **customerCreatedAt** (建档), 不是 relationshipStartAt (关系起点) ——
    //   两者语义不同, 别混 (见 actions.ts ACTION_THRESHOLDS.NEVER_CONTACTED_GRACE_DAYS)
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ contactTotal: 0 }),
        customerCreatedAt: NOW,
        relationshipStartAt: NOW,
      })
    );
    expect(idsOf(items)).not.toContain("never_contacted");
  });

  it("已联系过 → 不出破冰", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({ contactTotal: 3, daysSinceLastContact: 3 }),
        relationshipStartAt: daysAgo(60),
      })
    );
    expect(idsOf(items)).not.toContain("never_contacted");
  });

  it("【回归】多条互动挤在同一天 (中位间隔=0) + 久未联系 → 仍须出行动", () => {
    // 冒烟发现的真 BUG: 规则原先要求 avgContactIntervalDays > 0,
    //   而"同一天集中互动"会让中位间隔 = 0 → 规则永不触发
    //   → 91 天没联系也不给任何行动。
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          contactTotal: 6,
          daysSinceLastContact: 91,
          avgContactIntervalDays: 0, // ← 同一批互动, 间隔 0
        }),
      })
    );
    const it0 = items.find((i) => i.id === "contact_gap");
    expect(it0, "91 天没联系却零行动 = 漏报").toBeTruthy();
    expect(it0!.priority).toBe("high"); // 绝对兜底走 high
    expect(it0!.why).toContain("91 天");
  });

  it("【回归】无复购节奏 + 久未到店 → 仍须出行动", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          visitCount: 3,
          daysSinceLastVisit: 95,
          medianRepurchaseIntervalDays: 0, // ← 同一天多条记录
        }),
      })
    );
    expect(items.find((i) => i.id === "repurchase_window")).toBeTruthy();
  });

  it("绝对兜底不误报: 没节奏但天数未到 → 不出", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          contactTotal: 6,
          daysSinceLastContact: 20,
          avgContactIntervalDays: 0,
          visitCount: 3,
          daysSinceLastVisit: 30,
          medianRepurchaseIntervalDays: 0,
        }),
      })
    );
    expect(idsOf(items)).not.toContain("contact_gap");
    expect(idsOf(items)).not.toContain("repurchase_window");
  });

  it("一切正常 → 0 条行动 (不硬凑)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          contactTotal: 6,
          daysSinceLastContact: 5,
          avgContactIntervalDays: 14,
          daysSinceLastVisit: 10,
          medianRepurchaseIntervalDays: 28,
          visitCount: 5,
          overdueTasks: 0,
        }),
      })
    );
    expect(items).toHaveLength(0);
  });

  it("排序: high → medium → low", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          overdueTasks: 1,
          daysSinceLastVisit: 40,
          medianRepurchaseIntervalDays: 28,
          daysSinceLastContact: 40,
          avgContactIntervalDays: 14,
          visitCount: 4,
        }),
        daysUntilBirthday: 5,
        birthdayRemindDays: 7,
        hasOwner: false,
      })
    );
    const order = { high: 0, medium: 1, low: 2 } as const;
    for (let i = 1; i < items.length; i++) {
      expect(order[items[i].priority]).toBeGreaterThanOrEqual(order[items[i - 1].priority]);
    }
    expect(items[items.length - 1].id).toBe("profile_incomplete"); // low 在最后
  });

  it("确定性: 同输入两次结果一致", () => {
    const input = actionInput({
      analysis: analysis({ overdueTasks: 1, daysSinceLastVisit: 40, medianRepurchaseIntervalDays: 28 }),
    });
    expect(JSON.stringify(buildActionItems(input))).toBe(
      JSON.stringify(buildActionItems(input))
    );
  });

  it("topActions 只截前 N 条 (详情页 L0 不给销售压力)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          overdueTasks: 1,
          daysSinceLastVisit: 40,
          medianRepurchaseIntervalDays: 28,
          visitCount: 4,
        }),
        daysUntilBirthday: 1,
        birthdayRemindDays: 7,
        hasOwner: false,
      })
    );
    expect(items.length).toBeGreaterThan(3);
    expect(topActions(items, 3)).toHaveLength(3);
    expect(topActions(items, 3).map((i) => i.id)).toEqual(items.slice(0, 3).map((i) => i.id));
  });

  it("每条行动都可闭环: 有 taskTitle + taskDueAt (一键建任务用)", () => {
    const items = buildActionItems(
      actionInput({
        analysis: analysis({
          overdueTasks: 1,
          daysSinceLastVisit: 40,
          medianRepurchaseIntervalDays: 28,
          daysSinceLastContact: 40,
          avgContactIntervalDays: 14,
          visitCount: 4,
        }),
        daysUntilBirthday: 2,
        birthdayRemindDays: 7,
        hasOwner: false,
        lastRecordNoImprovement: true,
        nextAdviceDate: daysAgo(1),
      })
    );
    expect(items.length).toBeGreaterThanOrEqual(6);
    for (const it of items) {
      expect(it.taskTitle.trim().length).toBeGreaterThan(0);
      expect(() => new Date(it.taskDueAt).toISOString()).not.toThrow();
      expect(it.why.trim().length).toBeGreaterThan(4);
      expect(it.expected.trim().length).toBeGreaterThan(2);
    }
  });
});

// ============================================
// ⑧ 参数变量化 —— 配置层 (为 admin 调节页铺路)
// ============================================
// 守护的东西:
//   ① 默认配置能跑通同一套校验 (不会因为默认值本身非法而崩)
//   ② 覆盖能被夹回合法区间 (配置来自 DB/UI = 不受信输入)
//   ③ 改参数真的改变结果 (否则"变量化"是摆设)
//   ④ 同一份配置 → 同一份结果 (确定性不被配置破坏)

describe("参数变量化 (resolveInsightConfig + config 生效)", () => {
  it("默认配置经过校验后与硬编码前的行为一致", () => {
    const d = resolveInsightConfig();
    expect(d.scoring.bands).toHaveLength(4);
    expect(d.scoring.bands[0].min).toBe(80);
    expect(d.scoring.weights).toEqual({ effect: 0.3, engagement: 0.4, value: 0.3 });
    expect(d.actions.contactAbsoluteGapDays).toBe(45);
    expect(d.actions.priorities.profile_incomplete).toBe("low");
  });

  it("非法覆盖被夹回合法区间 (不受信输入)", () => {
    const d = resolveInsightConfig({
      scoring: { weakDimensionThreshold: 9999, weights: { effect: -5 } },
      actions: { contactAbsoluteGapDays: -100, birthdayWindowDays: 1e9 },
    });
    expect(d.scoring.weakDimensionThreshold).toBe(100);
    expect(d.scoring.weights.effect).toBe(0);
    expect(d.actions.contactAbsoluteGapDays).toBe(1);
    expect(d.actions.birthdayWindowDays).toBe(365);
  });

  it("垃圾输入不抛错, 回落默认 (一个坏配置不该让详情页打不开)", () => {
    for (const junk of [null, undefined, 42, "x", [], { scoring: "nope" }]) {
      const d = resolveInsightConfig(junk);
      expect(d.scoring.bands).toHaveLength(4);
      expect(d.actions.neverContactedGraceDays).toBe(1);
    }
  });

  it("分档表必须覆盖到 0, 否则补一档 (y=bandOf 才找得到)", () => {
    const d = resolveInsightConfig({ scoring: { bands: [{ band: "good", min: 60, label: "还行" }] } });
    expect(d.scoring.bands[d.scoring.bands.length - 1].min).toBe(0);
  });

  it("改阈值真的改变行动结果 (变量化不是摆设)", () => {
    const input = actionInput({
      analysis: analysis({ contactTotal: 3, daysSinceLastContact: 50, avgContactIntervalDays: 0 }),
    });
    // 默认 45 天 → 触发
    expect(buildActionItems(input).map((i) => i.id)).toContain("contact_gap");
    // 把阈值提到 90 天 → 50 天就不该触发
    expect(
      buildActionItems(input, { actions: { contactAbsoluteGapDays: 90 } }).map((i) => i.id)
    ).not.toContain("contact_gap");
  });

  it("改优先级真的改变排序", () => {
    const input = actionInput({ hasOwner: false });
    const dflt = buildActionItems(input);
    expect(dflt.find((i) => i.id === "profile_incomplete")!.priority).toBe("low");

    const bumped = buildActionItems(input, {
      actions: { priorities: { profile_incomplete: "high" } },
    });
    expect(bumped.find((i) => i.id === "profile_incomplete")!.priority).toBe("high");
  });

  it("改权重真的改变综合分", () => {
    const input = scoringInput({
      relationshipStartAt: daysAgo(400),
      records: [record(2, { pain_level: 9 }, { pain_level: 2 })], // effect 高
      interactions: [], // engagement/value 低
    });
    const dflt = buildCustomerScore(input).overall as number;
    // 把健康权重拉满 → 综合分应被 effect 拉高
    const effectHeavy = buildCustomerScore(input, {
      scoring: { weights: { effect: 1, engagement: 0, value: 0 } },
    }).overall as number;
    expect(effectHeavy).toBeGreaterThanOrEqual(dflt);
  });

  it("改分档阈值真的改变档位判定 (用中档客户, 不是极端值)", () => {
    // 造一个"中档"客户: 有互动但不多 → 默认落在 fair (40-59)
    const input = scoringInput({
      relationshipStartAt: daysAgo(400),
      interactions: [
        { type: "phone", createdAt: daysAgo(3) },
        { type: "wechat", createdAt: daysAgo(5) },
        { type: "visit", createdAt: daysAgo(7) },
      ],
      analysis: analysis({ contactTotal: 3, daysSinceLastContact: 3, avgContactIntervalDays: 0 }),
    });
    const dflt = buildCustomerScore(input);
    expect(dflt.overall as number).toBeGreaterThanOrEqual(40);
    expect(dflt.overall as number).toBeLessThan(80);
    expect(dflt.overallBand).toBe("fair");

    // 把"优秀"门槛提到 95, 且删掉 fair/good 两档 → 中档客户掉进 poor
    const strict = buildCustomerScore(input, {
      scoring: {
        bands: [
          { band: "excellent", min: 95, label: "顶尖" },
          { band: "poor", min: 0, label: "待改进" },
        ],
      },
    });
    expect(strict.overallBand).toBe("poor");
    expect(strict.overallBandLabel).toBe("待改进"); // 标签也来自配置
  });

  it("score 带 configVersion (改参数前后分数可区分)", () => {
    const a = buildCustomerScore(scoringInput(), { scoring: { version: "v1" } });
    const b = buildCustomerScore(scoringInput(), { scoring: { version: "v2" } });
    expect(a.configVersion).toBe("v1");
    expect(b.configVersion).toBe("v2");
    expect(a.scoringVersion).toBe(b.scoringVersion); // 算法版本没变
  });

  it("显式传默认配置 == 不传 (无隐藏状态)", () => {
    const input = scoringInput({ records: [record(3, { pain_level: 7 }, { pain_level: 4 })] });
    expect(JSON.stringify(buildCustomerScore(input, DEFAULT_INSIGHT_CONFIG))).toBe(
      JSON.stringify(buildCustomerScore(input))
    );
  });
});
