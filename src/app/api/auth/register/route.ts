// POST /api/auth/register — 凭推荐码自助注册 (B1, 主人 2026-09-20)
//
// 定位: **邀请制下的自助注册** —— 没有推荐码注册不了 (每个新人都有人背书)
// 之后: 新用户拿 手机号/密码 走正常登录 (/api/auth/callback/credentials 或 dev 的 flutter-login)
//
// 主人要求: 「账号/用户名提醒用户填真实姓名，真实手机号」→ 服务端强校验 (见 signup.ts)
//
// 边界:
//   - 公开接口 (未登录可调) → 必须限流 (防批量刷号)
//   - 注册后**不给权益**: 等推荐人点"这是我朋友"确认 (防码被转发后陌生人白嫖)
//   - 手机号唯一 = 登录账号; 密码走 scrypt (同全仓策略)

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { BillingError } from "@/lib/billing/entitlements";
import { registerWithReferral } from "@/lib/billing/signup";
import { rateLimit, RateLimits, getRateLimitKey, rateLimitResponse } from "@/lib/rate-limit";
import { logger } from "@/lib/errors";

export const runtime = "nodejs";

const Schema = z.object({
  /** 推荐码 (6 位; 大小写/空格/连字符都能救) */
  code: z.string().min(1).max(20),
  /** 真实姓名 */
  name: z.string().min(1).max(40),
  /** 真实手机号 (登录账号) */
  phone: z.string().min(5).max(20),
  password: z.string().min(1).max(72),
});

export async function POST(request: NextRequest) {
  // 限流: 同一 IP 10 分钟内最多 5 次注册 (正常用户不会连注册 5 个号)
  const limit = rateLimit(getRateLimitKey(request, "signup", "register"), {
    windowMs: 10 * 60_000,
    max: 5,
  });
  if (!limit.allowed) {
    return rateLimitResponse(limit);
  }

  try {
    const body = await request.json();
    const input = Schema.parse(body);

    const result = await registerWithReferral({
      rawCode: input.code,
      rawName: input.name,
      rawPhone: input.phone,
      password: input.password,
      ip:
        request.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
        request.headers.get("x-real-ip") ??
        null,
    });

    return NextResponse.json(
      {
        ok: true,
        username: result.username,
        needsReferrerConfirmation: result.needsReferrerConfirmation,
        message: result.message,
      },
      { status: 201 }
    );
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json(
        { error: "请把信息填完整 (推荐码 / 真实姓名 / 真实手机号 / 密码)" },
        { status: 400 }
      );
    }
    if (e instanceof BillingError) {
      return NextResponse.json(
        { error: e.message, code: e.code },
        { status: e.status }
      );
    }
    logger.error("POST /api/auth/register failed", {}, e);
    return NextResponse.json({ error: "注册失败, 请稍后再试" }, { status: 500 });
  }
}
