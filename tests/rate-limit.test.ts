// 限流单元测试
import { describe, it, expect } from "vitest";
import { rateLimit, getRateLimitKey, RateLimits } from "@/lib/rate-limit";

function makeRequest(ip: string = "192.168.1.1"): Request {
  return new Request("http://test/api", {
    headers: {
      "x-forwarded-for": ip,
      "x-real-ip": ip,
    },
  });
}

describe("rate-limit", () => {
  it("允许前 max 个请求, 拒绝后续", () => {
    const rule = { windowMs: 60_000, max: 3 };
    const key = "test-1";

    expect(rateLimit(key, rule).allowed).toBe(true);
    expect(rateLimit(key, rule).allowed).toBe(true);
    expect(rateLimit(key, rule).allowed).toBe(true);
    expect(rateLimit(key, rule).allowed).toBe(false);
    expect(rateLimit(key, rule).allowed).toBe(false);
  });

  it("不同 key 互不影响", () => {
    const rule = { windowMs: 60_000, max: 1 };
    expect(rateLimit("user-a", rule).allowed).toBe(true);
    expect(rateLimit("user-a", rule).allowed).toBe(false);
    // user-b 独立
    expect(rateLimit("user-b", rule).allowed).toBe(true);
  });

  it("窗口过期后重置", async () => {
    const rule = { windowMs: 100, max: 1 };
    const key = "test-expire";

    expect(rateLimit(key, rule).allowed).toBe(true);
    expect(rateLimit(key, rule).allowed).toBe(false);
    // 等 150ms 过期
    await new Promise((r) => setTimeout(r, 150));
    expect(rateLimit(key, rule).allowed).toBe(true);
  });

  it("retryAfterMs 在拒绝时返回", () => {
    const rule = { windowMs: 60_000, max: 1 };
    const key = "test-retry";
    rateLimit(key, rule);
    const result = rateLimit(key, rule);
    expect(result.allowed).toBe(false);
    expect(result.retryAfterMs).toBeGreaterThan(0);
    expect(result.retryAfterMs).toBeLessThanOrEqual(60_000);
  });

  it("getRateLimitKey 提取 IP", () => {
    const req = makeRequest("10.0.0.1");
    const key = getRateLimitKey(req, "user-1", "api");
    expect(key).toBe("api:user-1:10.0.0.1");
  });

  it("getRateLimitKey 多 IP 时取第一个 (x-forwarded-for)", () => {
    const req = new Request("http://test", {
      headers: { "x-forwarded-for": "1.1.1.1, 2.2.2.2" },
    });
    const key = getRateLimitKey(req, "u", "api");
    expect(key).toBe("api:u:1.1.1.1");
  });

  it("RateLimits 预定义规则存在", () => {
    expect(RateLimits.login.max).toBe(5);
    expect(RateLimits.ai.max).toBe(10);
    expect(RateLimits.upload.max).toBe(20);
    expect(RateLimits.api.max).toBe(60);
  });
});