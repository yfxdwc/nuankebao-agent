// ============================================
// 复购窗口 单测 (纯函数, 不碰库)
// ============================================
// 方案: docs/follow-up-list-plan.md §7.1 / §9.2 (会员字段 followUp.repurchase)
// 口径与 lib/ai/predictions.ts 一致: 最近 10 次到店的间隔平均 → 上次到店 + 平均 = 预计复购日

import { describe, it, expect } from "vitest";
import {
  computeRepurchaseWindow,
  REPURCHASE_SAMPLE,
} from "@/lib/follow-up/repurchase";

const NOW = new Date("2026-09-20T09:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000);

describe("computeRepurchaseWindow", () => {
  it("没有到店记录 → null (不参与紧急度)", () => {
    expect(computeRepurchaseWindow([], NOW)).toBeNull();
  });

  it("只有 1 次到店 → 算不出间隔, 无窗口, confidence=low", () => {
    const w = computeRepurchaseWindow([daysAgo(30)], NOW)!;
    expect(w.avgIntervalDays).toBeNull();
    expect(w.expectedAt).toBeNull();
    expect(w.windowOpenedAt).toBeNull();
    expect(w.confidence).toBe("low");
    expect(w.visitCount).toBe(1);
  });

  it("每 30 天一次, 上次 45 天前 → 窗口已开 15 天", () => {
    const w = computeRepurchaseWindow(
      [daysAgo(105), daysAgo(75), daysAgo(45)],
      NOW
    )!;
    expect(w.avgIntervalDays).toBe(30);
    expect(w.confidence).toBe("high");
    expect(w.windowOpenedAt).not.toBeNull();
    // 预计复购日 = 上次 + 30 天 = 15 天前
    const openedDaysAgo = Math.round(
      (NOW.getTime() - w.windowOpenedAt!.getTime()) / 86_400_000
    );
    expect(openedDaysAgo).toBe(15);
  });

  it("窗口未到 (上次 5 天前, 节奏 30 天) → windowOpenedAt=null 但 expectedAt 有值", () => {
    const w = computeRepurchaseWindow(
      [daysAgo(65), daysAgo(35), daysAgo(5)],
      NOW
    )!;
    expect(w.avgIntervalDays).toBe(30);
    expect(w.windowOpenedAt).toBeNull();
    expect(w.expectedAt).not.toBeNull();
    expect(
      Math.round((w.expectedAt!.getTime() - NOW.getTime()) / 86_400_000)
    ).toBe(25);
  });

  it("间隔乱 → 取平均 (四舍五入)", () => {
    // 间隔 10 / 15 / 20 → 平均 15
    const w = computeRepurchaseWindow(
      [daysAgo(50), daysAgo(40), daysAgo(25), daysAgo(5)],
      NOW
    )!;
    expect(w.avgIntervalDays).toBe(15);
  });

  it("闰/跨月按真实天差算 (不是自然月)", () => {
    const w = computeRepurchaseWindow(
      [new Date("2026-01-31T00:00:00Z"), new Date("2026-03-02T00:00:00Z")],
      NOW
    )!;
    expect(w.avgIntervalDays).toBe(30); // 1/31 → 3/2 = 30 天
  });

  it("只取最近 10 次 (老记录不拉低平均)", () => {
    // 11 次: 最老那次间隔 300 天, 其余每次 30 天 → 老记录被排除
    const dates = [daysAgo(300 + 30 * 10)];
    for (let i = 10; i >= 0; i--) dates.push(daysAgo(30 * i));
    const w = computeRepurchaseWindow(dates, NOW)!;
    expect(w.visitCount).toBe(REPURCHASE_SAMPLE);
    expect(w.avgIntervalDays).toBe(30);
  });

  it("入参乱序也不影响结果 (内部排序)", () => {
    const a = computeRepurchaseWindow([daysAgo(45), daysAgo(105), daysAgo(75)], NOW)!;
    const b = computeRepurchaseWindow([daysAgo(75), daysAgo(45), daysAgo(105)], NOW)!;
    expect(a.avgIntervalDays).toBe(b.avgIntervalDays);
    expect(a.windowOpenedAt?.getTime()).toBe(b.windowOpenedAt?.getTime());
  });

  it("confidence 分档: 2 次 → medium", () => {
    expect(computeRepurchaseWindow([daysAgo(60), daysAgo(30)], NOW)!.confidence).toBe("medium");
  });
});
