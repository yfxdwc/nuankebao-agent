// ============================================
// 用量事件清洗 / 校验 (服务端唯一入口)
//
// 原则 (CHARTER §4.4.5 用量域红线):
//   1. 词表外的事件名 → 整条丢弃 (前后端同仓同批发布, 无需前向兼容)
//   2. props 白名单外的键 / 非法值 → 只丢那个键, 不丢整条事件
//   3. 字符串值必须匹配"安全 slug"正则 (无空格 / 无中文 → 物理上写不进自由文本)
//   4. 兜底: 任何值命中手机号 regex (1[3-9]\d{9}) → 丢键
//   5. 时间戳异常 (解析不了 / 偏离服务器 > 7 天) → client_ts 存 null, 不丢事件
//
// 返回 { device, events, rejected }: device 缺失 = 整批拒绝 (无法归属设备)
// ============================================

import {
  USAGE_EVENTS,
  isUsageEntityType,
  isUsageEventName,
  type UsageEventName,
} from "./catalog";

// ---- 正则 (安全白名单) ----
const EVENT_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const SESSION_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const DEVICE_ID_RE = /^[A-Za-z0-9-]{8,64}$/;
const SCREEN_RE = /^\/[A-Za-z0-9/:_-]{0,80}$/;
const ENTITY_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const ERROR_CODE_RE = /^[A-Za-z0-9_.-]{1,64}$/;
// 字符串 props 值: slug 白名单 (无空格/中文 → 物理上写不进姓名/内容)
const PROP_STRING_RE = /^[A-Za-z0-9_.:/@-]{0,64}$/;
const APP_VERSION_RE = /^[A-Za-z0-9.+_-]{1,32}$/;
const OS_VERSION_RE = /^[A-Za-z0-9 ().,_+-]{1,32}$/;
const DEVICE_MODEL_RE = /^[A-Za-z0-9 ().,_+/-]{1,64}$/;
const PHONE_RE = /1[3-9]\d{9}/;
const PLATFORMS = new Set(["android", "ios", "web", "macos", "windows", "linux"]);

const MAX_BATCH = 50;
const MAX_PROPS_KEYS = 10;
const MAX_DURATION_MS = 3_600_000; // 1h
const MAX_CLOCK_SKEW_MS = 7 * 24 * 3600 * 1000;
const MAX_NUMBER = 1_000_000_000;

export interface SanitizedUsageEvent {
  eventId: string;
  eventName: UsageEventName;
  category: string;
  sessionId: string | null;
  screen: string | null;
  entityType: string | null;
  entityId: string | null;
  success: boolean | null;
  errorCode: string | null;
  durationMs: number | null;
  props: Record<string, string | number | boolean> | null;
  clientTs: Date | null;
}

export interface SanitizedDevice {
  deviceId: string;
  appVersion: string | null;
  platform: string | null;
  osVersion: string | null;
  deviceModel: string | null;
}

export interface SanitizeResult {
  device: SanitizedDevice | null;
  events: SanitizedUsageEvent[];
  rejected: number;
}

function str(value: unknown, re: RegExp): string | null {
  if (typeof value !== "string") return null;
  return re.test(value) ? value : null;
}

function safePropValue(
  value: unknown
): string | number | boolean | undefined {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value) || Math.abs(value) > MAX_NUMBER) return undefined;
    return value;
  }
  if (typeof value === "string") {
    // 手机号兜底 (即使白名单正则也该拦住, 双层防御)
    if (PHONE_RE.test(value)) return undefined;
    if (!PROP_STRING_RE.test(value)) return undefined;
    return value;
  }
  return undefined;
}

function sanitizeProps(
  name: UsageEventName,
  raw: unknown
): Record<string, string | number | boolean> | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) return null;

  const allowed = new Set<string>(USAGE_EVENTS[name].props);
  const out: Record<string, string | number | boolean> = {};
  let count = 0;

  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (count >= MAX_PROPS_KEYS) break;
    if (!allowed.has(key)) continue; // 白名单外 → 丢键
    const safe = safePropValue(value);
    if (safe === undefined) continue;
    out[key] = safe;
    count += 1;
  }

  return count > 0 ? out : null;
}

function sanitizeClientTs(raw: unknown): Date | null {
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  const date = new Date(raw);
  const ms = date.getTime();
  if (!Number.isFinite(ms)) return null;
  // 时钟漂移过大 (手机时间没同步) → 不存 client_ts, 服务端 server_ts 仍有值
  if (Math.abs(Date.now() - ms) > MAX_CLOCK_SKEW_MS) return null;
  return date;
}

function sanitizeEvent(
  raw: unknown,
  now: number
): { event: SanitizedUsageEvent } | { rejected: true } {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { rejected: true };
  }
  const r = raw as Record<string, unknown>;

  const eventId = str(r.id, EVENT_ID_RE);
  if (!eventId) return { rejected: true };

  if (!isUsageEventName(r.name)) return { rejected: true };
  const eventName = r.name;

  const entityType = isUsageEntityType(r.entityType) ? r.entityType : null;
  const entityId = str(r.entityId, ENTITY_ID_RE);

  const durationRaw = r.durationMs;
  const durationMs =
    typeof durationRaw === "number" &&
    Number.isFinite(durationRaw) &&
    durationRaw >= 0 &&
    durationRaw <= MAX_DURATION_MS
      ? Math.round(durationRaw)
      : null;

  void now; // client_ts 校验用 Date.now() 内部处理; 保留参数便于测试注入

  return {
    event: {
      eventId,
      eventName,
      category: USAGE_EVENTS[eventName].category,
      sessionId: str(r.sessionId, SESSION_ID_RE),
      screen: str(r.screen, SCREEN_RE),
      entityType: entityType && entityId ? entityType : null,
      entityId: entityType ? entityId : null,
      success: typeof r.success === "boolean" ? r.success : null,
      errorCode: str(r.errorCode, ERROR_CODE_RE),
      durationMs,
      props: sanitizeProps(eventName, r.props),
      clientTs: sanitizeClientTs(r.ts),
    },
  };
}

function sanitizeDevice(raw: unknown): SanitizedDevice | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const deviceId = str(r.deviceId, DEVICE_ID_RE);
  if (!deviceId) return null;
  return {
    deviceId,
    appVersion: str(r.appVersion, APP_VERSION_RE),
    platform:
      typeof r.platform === "string" && PLATFORMS.has(r.platform)
        ? r.platform
        : null,
    osVersion: str(r.osVersion, OS_VERSION_RE),
    deviceModel: str(r.deviceModel, DEVICE_MODEL_RE),
  };
}

/**
 * 校验整批请求体
 * @param body 已 JSON.parse 的请求体
 */
export function sanitizeUsageBatch(body: unknown): SanitizeResult {
  if (typeof body !== "object" || body === null) {
    return { device: null, events: [], rejected: 0 };
  }
  const b = body as Record<string, unknown>;

  const device = sanitizeDevice(b.device);
  if (!device) return { device: null, events: [], rejected: 0 };

  const rawEvents = Array.isArray(b.events) ? b.events : [];
  const events: SanitizedUsageEvent[] = [];
  let rejected = 0;
  const now = Date.now();

  for (const raw of rawEvents.slice(0, MAX_BATCH)) {
    const result = sanitizeEvent(raw, now);
    if ("rejected" in result) rejected += 1;
    else events.push(result.event);
  }
  // 超出批次的也算 dropped
  rejected += Math.max(0, rawEvents.length - MAX_BATCH);

  return { device, events, rejected };
}

/** 暴露给单测 */
export const __test__ = {
  sanitizeEvent,
  sanitizeProps,
  sanitizeDevice,
  MAX_BATCH,
  MAX_PROPS_KEYS,
  MAX_DURATION_MS,
};
