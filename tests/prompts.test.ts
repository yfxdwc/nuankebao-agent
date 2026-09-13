import { describe, it, expect } from "vitest";
import { buildProfilePrompt, buildFollowUpPrompt, buildEffectAnalysisPrompt } from "@/lib/ai/prompts";

describe("ai/prompts", () => {
  describe("buildProfilePrompt", () => {
    it("builds a structured prompt with customer info", () => {
      const result = buildProfilePrompt({
        name: "王女士",
        gender: "F",
        birthYear: 1985,
        healthTags: ["肩颈", "睡眠差"],
        diseaseHistory: null,
        notes: null,
        recentRecords: [
          {
            serviceDate: "2026-09-01",
            serviceItem: "肩颈经络理疗",
            bodyParts: ["肩颈"],
            preCondition: { pain_level: 8 },
            postCondition: { pain_level: 4 },
            feedback: "好多了",
          },
        ],
      });

      expect(result.system).toContain("养生顾问");
      expect(result.prompt).toContain("王女士");
      expect(result.prompt).toContain("肩颈");
      expect(result.prompt).toContain("好多了");
      expect(result.prompt).toContain("pain_level");
    });

    it("handles empty recent records", () => {
      const result = buildProfilePrompt({
        name: "测试",
        healthTags: [],
        recentRecords: [],
      });
      expect(result.prompt).toContain("暂无记录");
    });
  });

  describe("buildFollowUpPrompt", () => {
    it("includes customer name and reason", () => {
      const result = buildFollowUpPrompt({
        customerName: "李女士",
        customerProfile: "客户李女士, 肩颈问题",
        lastVisit: "2026-08-15",
        daysSinceLastVisit: 21,
        avgInterval: 30,
        reason: "复购周期",
      });

      expect(result.system).toContain("销售顾问");
      expect(result.prompt).toContain("李女士");
      expect(result.prompt).toContain("21");
      expect(result.prompt).toContain("复购周期");
    });
  });

  describe("buildEffectAnalysisPrompt", () => {
    it("includes all records", () => {
      const result = buildEffectAnalysisPrompt({
        customerName: "王女士",
        records: [
          {
            serviceDate: "2026-09-01",
            serviceItem: "肩颈",
            preCondition: { pain: 8 },
            postCondition: { pain: 4 },
            feedback: null,
          },
          {
            serviceDate: "2026-09-08",
            serviceItem: "肩颈",
            preCondition: { pain: 5 },
            postCondition: { pain: 2 },
            feedback: "持续改善",
          },
        ],
      });

      expect(result.prompt).toContain("第 1 次");
      expect(result.prompt).toContain("第 2 次");
      expect(result.prompt).toContain("持续改善");
    });
  });
});