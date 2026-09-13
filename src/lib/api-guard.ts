// ============================================
// API 守卫: auth + rate limit + error 统一
// W10 Phase 2 优化
//
// 用法:
//   const guard = await apiGuard(request, { auth: true, rateLimit: 'login' });
//   if (guard.response) return guard.response;  // 401 / 429 / etc.
//   // 继续业务逻辑
// ============================================

import { auth } from "@/lib/auth";
import { rateLimit, RateLimits, getRateLimitKey, rateLimitResponse } from "@/lib/rate-limit";
import { logger } from "@/lib/errors";
import type { Session } from "next-auth";

export interface GuardOptions {
  auth?: boolean;           // 是否要求登录
  rateLimit?: keyof typeof RateLimits;
  identifier?: string;      // 自定义 rate limit 标识 (e.g. customerId)
}

export interface GuardResult {
  session: Session | null;
  userId: string | null;
  ip: string | null;
  response?: Response;       // 如果有, 直接返回 (401 / 429)
}

export async function apiGuard(
  request: Request,
  options: GuardOptions = {}
): Promise<GuardResult> {
  const { auth: requireAuth = false, rateLimit: limitKey, identifier } = options;

  // 1. 提取 IP
  const ip =
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    request.headers.get("x-real-ip") ||
    "unknown";

  // 2. 鉴权
  let session: Session | null = null;
  let userId: string | null = null;
  if (requireAuth) {
    session = (await auth()) as Session | null;
    if (!session?.user?.id) {
      logger.warn("Unauthorized API call", { path: request.url, ip });
      return {
        session: null,
        userId: null,
        ip,
        response: Response.json({ error: "Unauthorized" }, { status: 401 }),
      };
    }
    userId = session.user.id;
  } else {
    session = (await auth()) as Session | null;
    userId = session?.user?.id ?? null;
  }

  // 3. 限流
  if (limitKey) {
    const rule = RateLimits[limitKey]!;
    const key = getRateLimitKey(request, identifier ?? userId ?? "anon", limitKey);
    const limit = rateLimit(key, rule);
    if (!limit.allowed) {
      logger.warn("Rate limit exceeded", {
        endpoint: request.url,
        ip,
        userId: userId ?? undefined,
        key,
        retryAfterMs: limit.retryAfterMs,
      });
      return {
        session,
        userId,
        ip,
        response: rateLimitResponse(limit),
      };
    }
  }

  return { session, userId, ip };
}