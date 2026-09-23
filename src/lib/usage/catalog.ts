// ============================================
// 用量事件词表 (唯一真相源)
//
// 主人 2026-09-22 拍: 「需要有对真实用户的完整全面的使用数据收集模块」
// 红线 (CHARTER §4.4.5):
//   - 只允许 ID / 枚举 / 计数 / 时长
//   - ❌ 不采姓名 / 手机号 / 疾病史 / 养生内容 / 自由文本
//   - 服务端只接受本词表内的事件名; 未知事件丢弃 (前后端同仓同批发布)
//
// Flutter 侧镜像: flutter_app/lib/core/telemetry/usage_events.dart
//   ⚠ 改这里必须同步改那里 (词表 = 双端契约)
// ============================================

export type UsageCategory =
  | "lifecycle"
  | "nav"
  | "auth"
  | "customer"
  | "wellness"
  | "followup"
  | "ai"
  | "salon"
  | "relation"
  | "error"
  | "perf";

export interface UsageEventSpec {
  category: UsageCategory;
  /** 允许出现在 props 里的键 (白名单; 其余键静默丢弃) */
  props: readonly string[];
}

/**
 * 事件词表
 *   命名: 小写 + 下划线; 过去式不强制 (click / result / create 统一动词)
 */
export const USAGE_EVENTS = {
  // ---- 生命周期 (客户端自动) ----
  app_open: { category: "lifecycle", props: ["first"] },
  app_pause: { category: "lifecycle", props: [] },
  app_resume: { category: "lifecycle", props: [] },

  // ---- 导航 (路由 observer 自动) ----
  screen_view: { category: "nav", props: [] },

  // ---- 认证 ----
  login_success: { category: "auth", props: [] },
  login_fail: { category: "auth", props: ["reason"] },
  logout: { category: "auth", props: [] },

  // ---- 客户 ----
  customer_view: { category: "customer", props: ["source"] },
  customer_create: { category: "customer", props: ["source"] },
  customer_edit: { category: "customer", props: [] },
  customer_search: { category: "customer", props: ["keywordLen"] },
  customer_call: { category: "customer", props: [] },

  // ---- 养生记录 ----
  record_create: { category: "wellness", props: ["step"] },
  record_edit: { category: "wellness", props: [] },
  record_photo_taken: { category: "wellness", props: [] },

  // ---- 跟进 ----
  follow_up_create: { category: "followup", props: ["source"] },
  follow_up_done: { category: "followup", props: [] },
  follow_up_postpone: { category: "followup", props: [] },
  follow_up_list_view: { category: "followup", props: [] },

  // ---- AI (回答「AI 卡片到底有没有人点」的核心数据) ----
  ai_generate_click: { category: "ai", props: ["card"] },
  ai_generate_result: { category: "ai", props: ["card", "cached"] },
  ai_regenerate: { category: "ai", props: ["card"] },

  // ---- 沙龙 ----
  salon_create: { category: "salon", props: [] },
  salon_rsvp: { category: "salon", props: ["status"] },

  // ---- 加盟关系 ----
  placement_request_create: { category: "relation", props: [] },

  // ---- 失败 / 性能 ----
  api_error: { category: "error", props: ["path", "status"] },
  ui_error: { category: "error", props: [] },
  // api_latency 只报"分桶" (bucketMs), 不报精确毫秒, 避免高频事件淹没数据
  api_latency: { category: "perf", props: ["path", "bucketMs"] },
} as const satisfies Record<string, UsageEventSpec>;

export type UsageEventName = keyof typeof USAGE_EVENTS;

export const USAGE_EVENT_NAMES = Object.keys(USAGE_EVENTS) as UsageEventName[];

export function isUsageEventName(value: unknown): value is UsageEventName {
  return typeof value === "string" && Object.hasOwn(USAGE_EVENTS, value);
}

export function usageCategoryOf(name: UsageEventName): UsageCategory {
  return USAGE_EVENTS[name].category;
}

/** 实体类型 (只存 ID 的类型, 不存内容) */
export const USAGE_ENTITY_TYPES = [
  "customer",
  "wellness_record",
  "follow_up",
  "salon",
  "user",
  "franchisee",
] as const;

export type UsageEntityType = (typeof USAGE_ENTITY_TYPES)[number];

export function isUsageEntityType(value: unknown): value is UsageEntityType {
  return (
    typeof value === "string" &&
    (USAGE_ENTITY_TYPES as readonly string[]).includes(value)
  );
}

/** AI 卡片枚举 (与 Flutter ai_insight_cards.dart 对齐)
 *  ⚠ P5 (2026-09-23): 3 张卡合并成 1 次调用 → 新事件用 `insight`;
 *    旧值保留是为了**历史数据不乱** (库里已有 card=profile/follow_up/effect 的行)。
 */
export const AI_CARDS = [
  "insight",
  "profile",
  "follow_up",
  "repurchase",
  "effect",
] as const;
export type AiCard = (typeof AI_CARDS)[number];
