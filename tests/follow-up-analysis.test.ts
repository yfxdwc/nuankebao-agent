// ============================================
// 客户跟进分析 单测 (纯函数, 不碰库)
// ============================================
// 方案: docs/follow-up-list-plan.md §7.1 (详情页「跟进分析」卡)
// 判权: 客观指标免费 (方案 §11); AI 解读走 POST /api/ai/follow-up (会员)

import { describe, it, expect } from "vitest";
import { buildFollowUpAnalysis, median } from "@/lib/follow-up/analysis";

const NOW = new Date("2026-09-20T09:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000);

function base(over: Partial<Parameters<typeof buildFollowUpAnalysis>[0]> = {}) {
  return buildFollowUpAnalysis({
    interactionDates: [],
    visitDates: [],
    openTaskDueAts: [],
    now: NOW,
    ...over,
  });
}

describe("median", () => {
  it("奇数取中间", () => expect(median([30, 10, 20])).toBe(20));
  it("偶数取中间两数平均", () => expect(median([10, 20, 30, 41])).toBe(25));
  it("空数组 → null", () => expect(median([])).toBeNull());
});

describe("buildFollowUpAnalysis", () => {
  it("啥都没有 → 全 0/null, headline 引导先认识", () => {
    const a = base();
    expect(a.contactTotal).toBe(0);
    expect(a.contactLast30).toBe(0);
    expect(a.avgContactIntervalDays).toBeNull();
    expect(a.visitCount).toBe(0);
    expect(a.pendingTasks).toBe(0);
    expect(a.trend).toBe("unknown");
    expect(a.headline).toContain("还没有联系和到店记录");
  });

  it("只有到店没联系 → headline 点出这个缺口", () => {
    const a = base({ visitDates: [daysAgo(40), daysAgo(10)] });
    expect(a.contactTotal).toBe(0);
    expect(a.visitCount).toBe(2);
    expect(a.headline).toContain("还没有联系记录");
  });

  it("近 30 / 90 天窗口按日历天切", () => {
    const a = base({
      interactionDates: [daysAgo(0), daysAgo(29), daysAgo(30), daysAgo(89), daysAgo(90), daysAgo(200)],
    });
    expect(a.contactLast30).toBe(2); // 0 / 29 天
    expect(a.contactLast90).toBe(4); // + 30 / 89 天
    expect(a.contactTotal).toBe(6);
  });

  it("平均联系间隔取中位数 (抗异常值, 不被一次很久没联系带偏)", () => {
    // 间隔: 5 / 6 / 300 → 中位数 6 (平均会是 103)
    const a = base({
      interactionDates: [daysAgo(311), daysAgo(306), daysAgo(300), daysAgo(0)],
    });
    expect(a.avgContactIntervalDays).toBe(6);
  });

  it("趋势: 明显变冷 → colder", () => {
    // 历史每 10 天一次 ×4, 最近 3 个间隔变成 30 天
    const dates = [daysAgo(160), daysAgo(150), daysAgo(140), daysAgo(130), daysAgo(100), daysAgo(70), daysAgo(40)];
    const a = base({ interactionDates: dates });
    expect(a.trend).toBe("colder");
    expect(a.trendText).toContain("变冷");
  });

  it("趋势: 明显变热 → warmer", () => {
    // 历史每 40 天一次, 最近间隔缩到 7 天
    const dates = [daysAgo(200), daysAgo(160), daysAgo(120), daysAgo(80), daysAgo(30), daysAgo(14), daysAgo(0)];
    const a = base({ interactionDates: dates });
    expect(a.trend).toBe("warmer");
    expect(a.trendText).toContain("变热");
  });

  it("趋势: 间隔没变 → steady", () => {
    const dates = [daysAgo(120), daysAgo(90), daysAgo(60), daysAgo(30), daysAgo(0)];
    const a = base({ interactionDates: dates });
    expect(a.trend).toBe("steady");
    expect(a.trendText).toContain("节奏稳定");
  });

  it("趋势: 样本太少 → unknown (不硬猜)", () => {
    const a = base({ interactionDates: [daysAgo(30), daysAgo(10)] });
    expect(a.trend).toBe("unknown");
  });

  it("到店规律 + 复购间隔中位数", () => {
    const a = base({ visitDates: [daysAgo(70), daysAgo(42), daysAgo(14)] });
    expect(a.visitCount).toBe(3);
    expect(a.avgVisitIntervalDays).toBe(28);
    expect(a.medianRepurchaseIntervalDays).toBe(28);
    expect(a.daysSinceLastVisit).toBe(14);
    expect(a.lastVisitAt).not.toBeNull();
  });

  it("跟进任务: pending / 逾期计数 + 最久逾期天数", () => {
    const a = base({
      openTaskDueAts: [daysAgo(3), daysAgo(10), new Date(NOW.getTime() + 5 * 86_400_000)],
    });
    expect(a.pendingTasks).toBe(3);
    expect(a.overdueTasks).toBe(2); // 今天/未来到期不算逾期
    expect(a.oldestOverdueDays).toBe(10);
  });

  it("没有逾期 → oldestOverdueDays=null 且 headline 提待办不提逾期", () => {
    const a = base({
      interactionDates: [daysAgo(1)],
      openTaskDueAts: [new Date(NOW.getTime() + 3 * 86_400_000)],
    });
    expect(a.oldestOverdueDays).toBeNull();
    expect(a.headline).toContain("1 条待办跟进");
    expect(a.headline).not.toContain("逾期");
  });

  it("headline 串起联系 / 间隔 / 逾期 (免费层一句话总结)", () => {
    const a = base({
      interactionDates: [daysAgo(45), daysAgo(30), daysAgo(15)],
      openTaskDueAts: [daysAgo(4)],
    });
    expect(a.headline).toContain("已 15 天没联系");
    expect(a.headline).toContain("平均 15 天联系一次");
    expect(a.headline).toContain("逾期 4 天");
  });

  it("今天联系过 → headline 说「今天联系过」", () => {
    const a = base({ interactionDates: [daysAgo(30), daysAgo(0)] });
    expect(a.headline).toContain("今天联系过");
  });
});
