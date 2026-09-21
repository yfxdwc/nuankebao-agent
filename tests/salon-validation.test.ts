// ============================================
// 沙龙创建 schema 校验 (v0.1.5+)
// ============================================
// 纯 zod 单测, 不依赖 DB / 外部服务; 跑 `pnpm test:run` 即可
// 覆盖:
//   - 开始时间 < 当前 → 报错
//   - 结束时间 < 开始时间 → 报错
//   - 合法 (未来开始 + 未来结束) → 通过
//   - 只给开始时间 (无结束) → 通过
// ============================================

import { describe, it, expect } from "vitest";
import { SalonCreateSchema, SalonUpdateSchema } from "@/lib/salon/validation";

const isoIn = (msFromNow: number) => new Date(Date.now() + msFromNow).toISOString();

describe("SalonCreateSchema — 时间校验", () => {
  it("开始时间早于当前 → startAt 报错", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: isoIn(-60_000), // 1 分钟前
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      const issue = res.error.issues.find((i) => i.path[0] === "startAt");
      expect(issue?.message).toMatch(/开始时间不能早于当前时间/);
    }
  });

  it("结束时间早于开始时间 → endAt 报错", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: isoIn(3_600_000),    // 1 小时后
      endAt: isoIn(60_000),         // 1 分钟后 < start
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      const issue = res.error.issues.find((i) => i.path[0] === "endAt");
      expect(issue?.message).toMatch(/结束时间不能早于开始时间/);
    }
  });

  it("开始 < 当前 且 结束 < 开始 → 两条都报", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: isoIn(-3_600_000),
      endAt: isoIn(-7_200_000),
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      const paths = res.error.issues.map((i) => i.path[0]);
      expect(paths).toContain("startAt");
      expect(paths).toContain("endAt");
    }
  });

  it("合法: 未来开始 + 未来结束 → 通过", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: isoIn(3_600_000),
      endAt: isoIn(7_200_000),
    });
    expect(res.success).toBe(true);
  });

  it("合法: 只有开始时间 (无结束) → 通过", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: isoIn(60_000),
    });
    expect(res.success).toBe(true);
  });

  it("开始时间格式错 → zod .datetime() 自己拦下, refine 不重复报错", () => {
    const res = SalonCreateSchema.safeParse({
      title: "秋季养生沙龙",
      startAt: "not-a-date",
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      // 只该有 1 条 datetime 错误, 不应有 refine 抛出的 startAt 错误
      const startAtIssues = res.error.issues.filter((i) => i.path[0] === "startAt");
      expect(startAtIssues.length).toBe(1);
    }
  });
});

describe("SalonUpdateSchema — 时间校验 (partial)", () => {
  it("patch 把 startAt 改到过去 → 报错", () => {
    const res = SalonUpdateSchema.safeParse({
      startAt: isoIn(-60_000),
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      expect(res.error.issues.some(
        (i) => i.path[0] === "startAt" && /开始时间不能早于当前时间/.test(i.message)
      )).toBe(true);
    }
  });

  it("patch 同时给 startAt (未来) + endAt (比 startAt 早) → 报 endAt 错", () => {
    const res = SalonUpdateSchema.safeParse({
      startAt: isoIn(3_600_000),
      endAt: isoIn(60_000),
    });
    expect(res.success).toBe(false);
    if (!res.success) {
      expect(res.error.issues.some(
        (i) => i.path[0] === "endAt" && /结束时间不能早于开始时间/.test(i.message)
      )).toBe(true);
    }
  });

  it("patch 不传 startAt / endAt → refine 跳过, 通过", () => {
    const res = SalonUpdateSchema.safeParse({
      title: "只改标题",
      locationName: "新场地",
    });
    expect(res.success).toBe(true);
  });

  it("patch 只传 endAt (无 startAt) → 已知限制: 跳过, 通过", () => {
    // 仅 endAt 时 schema 层无 DB 上下文, 不校验 endAt 与原 startAt 的关系
    const res = SalonUpdateSchema.safeParse({
      endAt: isoIn(-86_400_000), // 哪怕过去也通过
    });
    expect(res.success).toBe(true);
  });

  it("patch 把 startAt 改到合法未来 + endAt 改到之后 → 通过", () => {
    const res = SalonUpdateSchema.safeParse({
      startAt: isoIn(3_600_000),
      endAt: isoIn(7_200_000),
    });
    expect(res.success).toBe(true);
  });
});
