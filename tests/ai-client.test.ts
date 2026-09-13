import { describe, it, expect } from "vitest";
import { aiComplete, isAIEnabled } from "@/lib/ai/client";

describe("ai/client (mock mode)", () => {
  it("returns mock response when no API key", async () => {
    // No MINIMAX_API_KEY in test env
    const result = await aiComplete({
      prompt: "分析这个客户",
    });
    expect(result.mock).toBe(true);
    expect(result.text).toContain("Mock");
  });

  it("returns profile mock for profile prompt", async () => {
    const result = await aiComplete({
      prompt: "请生成客户画像",
    });
    expect(result.text).toContain("客户画像");
    expect(result.text).toContain("健康档案");
  });

  it("returns follow-up mock for follow-up prompt", async () => {
    const result = await aiComplete({
      prompt: "请生成跟进话术",
    });
    expect(result.text).toContain("跟进");
    expect(result.text).toContain("微信");
  });

  it("isAIEnabled returns false without API key", () => {
    expect(isAIEnabled()).toBe(false);
  });

  it("respects max tokens option", async () => {
    const result = await aiComplete({
      prompt: "test",
      maxTokens: 100,
    });
    // Mock 不真用 maxTokens, 但 API 会用, 确保选项不影响 mock 返回
    expect(result.text).toBeTruthy();
  });
});