// ============================================
// 内存限流 (滑动窗口)
// W10 Phase 2 优化
// 生产建议换 Upstash Redis (KV 原子操作)
//
// 借鉴 Cloudflare / Vercel Rate Limit 设计
// ============================================

interface LimitRule {
  windowMs: number;  // 时间窗口 (ms)
  max: number;       // 窗口内最大请求数
}

interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetMs: number;   // ms 后窗口重置
  retryAfterMs?: number;
}

// 内存存储: Map<key, timestamps[]>
const store = new Map<string, number[]>();

// 定期清理过期 entry (避免内存泄漏)
const CLEANUP_INTERVAL = 60_000; // 60s
setInterval(() => {
  const now = Date.now();
  for (const [key, timestamps] of store.entries()) {
    const valid = timestamps.filter((t) => now - t < 60_000);
    if (valid.length === 0) {
      store.delete(key);
    } else if (valid.length !== timestamps.length) {
      store.set(key, valid);
    }
  }
}, CLEANUP_INTERVAL);

/**
 * 滑动窗口限流
 *
 * @example
 *   const limit = rateLimit(`login:${ip}`, { windowMs: 60_000, max: 5 });
 *   if (!limit.allowed) return 429;
 */
export function rateLimit(
  key: string,
  rule: LimitRule
): RateLimitResult {
  const now = Date.now();
  const windowStart = now - rule.windowMs;
  const timestamps = (store.get(key) ?? []).filter((t) => t > windowStart);
  timestamps.push(now);
  store.set(key, timestamps);

  const allowed = timestamps.length <= rule.max;
  const remaining = Math.max(0, rule.max - timestamps.length);
  const oldest = timestamps[0] ?? now;
  const resetMs = Math.max(0, oldest + rule.windowMs - now);

  return {
    allowed,
    remaining,
    resetMs,
    retryAfterMs: allowed ? undefined : resetMs,
  };
}

// ============================================
// 预定义规则
// ============================================

export const RateLimits = {
  // 登录: 5 次 / 分钟 / IP (防爆破)
  login: { windowMs: 60_000, max: 5 },
  // 验证码发送: 1 次 / 10 秒 / IP + 3 次 / 小时 / IP
  sendCode: { windowMs: 10_000, max: 1 },
  // 通用 API: 60 次 / 分钟 / 用户
  api: { windowMs: 60_000, max: 60 },
  // AI 端点: 10 次 / 分钟 / 用户 (AI 贵)
  ai: { windowMs: 60_000, max: 10 },
  // 文件上传: 20 次 / 小时 / 用户
  upload: { windowMs: 60 * 60_000, max: 20 },
  // 报表: 30 次 / 分钟 / 用户
  report: { windowMs: 60_000, max: 30 },
} as const satisfies Record<string, LimitRule>;

/**
 * 从 request 提取限流 key
 */
export function getRateLimitKey(
  request: Request,
  identifier: string,
  prefix: string
): string {
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    request.headers.get("x-real-ip") ||
    "unknown";
  return `${prefix}:${identifier}:${ip}`;
}

/**
 * 生成 429 响应
 */
export function rateLimitResponse(result: RateLimitResult): Response {
  return new Response(
    JSON.stringify({
      error: "请求过于频繁",
      retryAfterMs: result.retryAfterMs,
    }),
    {
      status: 429,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Retry-After": Math.ceil((result.retryAfterMs ?? 0) / 1000).toString(),
        "X-RateLimit-Remaining": result.remaining.toString(),
        "X-RateLimit-Reset": Math.ceil((Date.now() + result.resetMs) / 1000).toString(),
      },
    }
  );
}