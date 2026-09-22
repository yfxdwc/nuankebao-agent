// 用量事件清洗/校验单元测试
// 依据: CHARTER §4.4.5 用量域红线 + src/lib/usage/sanitize.ts
import { describe, it, expect } from "vitest";

import { __test__, sanitizeUsageBatch } from "@/lib/usage/sanitize";
import { USAGE_EVENTS, isUsageEventName } from "@/lib/usage/catalog";

const device = {
  deviceId: "device-abc-123",
  appVersion: "0.2.7+8",
  platform: "android",
  osVersion: "14",
  deviceModel: "Xiaomi 13",
};

function validEvent(overrides: Record<string, unknown> = {}) {
  return {
    id: "evt-12345678-abcd",
    name: "screen_view",
    ts: new Date().toISOString(),
    sessionId: "sess-12345678",
    screen: "/customers/:id",
    ...overrides,
  };
}

describe("usage sanitize — 词表", () => {
  it("已知事件名通过, category 自动带出", () => {
    const r = sanitizeUsageBatch({ device, events: [validEvent()] });
    expect(r.rejected).toBe(0);
    expect(r.events).toHaveLength(1);
    expect(r.events[0].eventName).toBe("screen_view");
    expect(r.events[0].category).toBe("nav");
  });

  it("未知事件名整条丢弃", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [validEvent({ name: "customer_姓名_张三" })],
    });
    expect(r.events).toHaveLength(0);
    expect(r.rejected).toBe(1);
  });

  it("词表覆盖 AI 四卡", () => {
    for (const card of ["profile", "follow_up", "repurchase", "effect"]) {
      const r = sanitizeUsageBatch({
        device,
        events: [
          validEvent({
            name: "ai_generate_click",
            props: { card },
          }),
        ],
      });
      expect(r.events[0].props).toEqual({ card });
    }
  });

  it("isUsageEventName 只认词表内", () => {
    expect(isUsageEventName("app_open")).toBe(true);
    expect(isUsageEventName("not_an_event")).toBe(false);
    expect(isUsageEventName(123)).toBe(false);
  });
});

describe("usage sanitize — props 白名单 (无 PII)", () => {
  it("白名单外的键静默丢弃", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [
        validEvent({
          name: "customer_search",
          props: { keywordLen: 3, keyword: "张三", phone: "13800138000" },
        }),
      ],
    });
    expect(r.events[0].props).toEqual({ keywordLen: 3 });
  });

  it("中文自由文本值丢弃 (物理上写不进姓名/内容)", () => {
    const props = __test__.sanitizeProps("customer_search", {
      keywordLen: 2,
      note: "腰椎间盘突出",
    } as unknown);
    expect(props).toEqual({ keywordLen: 2 });
  });

  it("手机号 (含数字串) 兜底丢弃", () => {
    const props = __test__.sanitizeProps("customer_search", {
      keywordLen: 13800138000,
      note: "13800138000",
    } as unknown);
    // 数字 13800138000 超 MAX_NUMBER → 丢; 字符串命中手机号 regex → 丢
    expect(props).toBeNull();
  });

  it("事件自身字段里的非法 screen / entity 丢弃, 事件保留", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [
        validEvent({
          screen: "/customers/张三",
          entityType: "hacker",
          entityId: "1",
        }),
      ],
    });
    expect(r.events).toHaveLength(1);
    expect(r.events[0].screen).toBeNull();
    expect(r.events[0].entityType).toBeNull();
  });

  it("合法 entity (类型 + ID) 保留", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [
        validEvent({
          name: "customer_view",
          entityType: "customer",
          entityId: "42",
        }),
      ],
    });
    expect(r.events[0].entityType).toBe("customer");
    expect(r.events[0].entityId).toBe("42");
  });
});

describe("usage sanitize — 边界", () => {
  it("device 缺失 → 整批拒绝", () => {
    const r = sanitizeUsageBatch({ events: [validEvent()] });
    expect(r.device).toBeNull();
    expect(r.events).toHaveLength(0);
  });

  it("非法 event id 丢弃", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [validEvent({ id: "x" })],
    });
    expect(r.events).toHaveLength(0);
    expect(r.rejected).toBe(1);
  });

  it("时钟漂移 > 7 天 → client_ts 置空, 事件保留", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [validEvent({ ts: "2020-01-01T00:00:00.000Z" })],
    });
    expect(r.events).toHaveLength(1);
    expect(r.events[0].clientTs).toBeNull();
  });

  it("durationMs 越界 → 置空", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [
        validEvent({ name: "ai_generate_result", durationMs: 99_999_999 }),
      ],
    });
    expect(r.events[0].durationMs).toBeNull();
  });

  it("超过 50 条 → 截断 + 计入 rejected", () => {
    const events = Array.from({ length: 55 }, (_, i) =>
      validEvent({ id: `evt-12345678-${String(i).padStart(4, "0")}` })
    );
    const r = sanitizeUsageBatch({ device, events });
    expect(r.events).toHaveLength(50);
    expect(r.rejected).toBe(5);
  });

  it("错误码非 slug → 置空", () => {
    const r = sanitizeUsageBatch({
      device,
      events: [validEvent({ name: "api_error", errorCode: "服务器炸了" })],
    });
    expect(r.events[0].errorCode).toBeNull();
  });
});

describe("usage catalog — 完整性", () => {
  it("词表覆盖 6 大类 + 错误/性能", () => {
    const categories = new Set(
      Object.values(USAGE_EVENTS).map((spec) => spec.category)
    );
    for (const c of [
      "lifecycle",
      "nav",
      "auth",
      "customer",
      "wellness",
      "followup",
      "ai",
      "salon",
      "error",
      "perf",
    ]) {
      expect(categories.has(c as never)).toBe(true);
    }
  });

  it("每个事件的 props 键都在安全 slug 字母表内", () => {
    for (const spec of Object.values(USAGE_EVENTS)) {
      for (const key of spec.props) {
        expect(/^[A-Za-z][A-Za-z0-9_]{0,30}$/.test(key)).toBe(true);
      }
    }
  });
});
