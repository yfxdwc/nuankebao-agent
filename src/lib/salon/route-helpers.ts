// ============================================
// 沙龙 API 路由公共 helper (v0.1.5 Phase 7)
// ============================================
// 与既有 route 的 auth 模式一致 (auth() + isAuthSkipped()),
// 抽出只是为了 14 个 route 文件不重复 10 行样板。
// ============================================

import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";

export type RouteSession = { user?: { id?: string } } | null;

export type AuthOk = { ok: true; userId: bigint; session: RouteSession };
export type AuthFail = { ok: false; response: NextResponse };

/**
 * 统一鉴权。
 * - 未登录 → { ok: false, response: 401 }
 * - dev DEV_SKIP_AUTH=1 无 session → userId = 0 (与 follow-ups 等既有 route 同口径)
 */
export async function requireUserId(): Promise<AuthOk | AuthFail> {
  const session = (await auth()) as unknown as RouteSession;
  if (!isAuthSkipped() && !session?.user?.id) {
    return {
      ok: false,
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
    };
  }
  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  return { ok: true, userId, session };
}

/** 路径参数 id → bigint (非法 → null, 调用方回 404) */
export function parseId(raw: string): bigint | null {
  if (!/^\d+$/.test(raw)) return null;
  try {
    return BigInt(raw);
  } catch {
    return null;
  }
}

/** zod 错误 → 400; 其余信息透出 (业务错误) */
export function handleRouteError(error: unknown, tag: string): NextResponse {
  if (error instanceof z.ZodError) {
    return NextResponse.json(
      { error: "Invalid input", details: error.errors },
      { status: 400 }
    );
  }
  console.error(`[${tag}]`, error);
  return NextResponse.json({ error: "Internal server error" }, { status: 500 });
}

/** 404 快捷函数 */
export function notFound(): NextResponse {
  return NextResponse.json({ error: "Not found" }, { status: 404 });
}

/** 403 (可见但无权限) */
export function forbidden(): NextResponse {
  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}
