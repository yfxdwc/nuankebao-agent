import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateAiInsight } from "@/lib/ai/insight";
import { apiGuard } from "@/lib/api-guard";
import { featureGuard } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { logger } from "@/lib/errors";

const Schema = z.object({
  customerId: z.string().regex(/^\d+$/),
  /** 跟进理由 (来自 L0 行动规则引擎 / 用户下拉); 只影响「话术」那段 */
  reason: z.string().max(200).optional(),
});

/**
 * POST /api/ai/insight
 * AI 洞察 (P5): **一次调用** 产出 客户画像 + 跟进话术 + 效果分析
 *   + 复购预测 (纯 DB 计算, 不烧 AI)
 *
 * 为什么是 POST 而不是 GET:
 *   `reason` 是请求体参数 (且含中文), 塞 querystring 要额外编码/限长;
 *   本接口会产生副作用 (烧 AI 额度) 且不该被 CDN 缓存 → POST 更合适。
 */
export async function POST(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "ai" });
  if (guard.response) return guard.response;

  // ADR-0012: 会员功能判权 (免费用户 402)
  const gate = await featureGuard(guard.userId, FEATURES.AI_INSIGHT);
  if (gate) return gate;

  try {
    const body = await request.json();
    const { customerId, reason } = Schema.parse(body);

    const result = await generateAiInsight(BigInt(customerId), { reason });
    if (!result) {
      return NextResponse.json({ error: "客户不存在" }, { status: 404 });
    }
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input" }, { status: 400 });
    }
    logger.error(
      "POST /api/ai/insight failed",
      { userId: guard.userId ?? undefined, ip: guard.ip ?? undefined },
      error
    );
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
