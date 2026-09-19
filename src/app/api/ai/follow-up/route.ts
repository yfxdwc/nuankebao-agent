import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateFollowUpSuggestion } from "@/lib/ai/follow-up";
import { apiGuard } from "@/lib/api-guard";
import { featureGuard } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { logger } from "@/lib/errors";

const Schema = z.object({
  customerId: z.string().regex(/^\d+$/),
  reason: z.string().optional(),
});

/**
 * POST /api/ai/follow-up
 * 生成跟进话术
 */
export async function POST(request: NextRequest) {
  const guard = await apiGuard(request, { auth: true, rateLimit: "ai" });
  if (guard.response) return guard.response;

  // ADR-0012: 会员功能判权 (免费用户 402)
  const gate = await featureGuard(guard.userId, FEATURES.AI_FOLLOW_UP);
  if (gate) return gate;

  try {
    const body = await request.json();
    const { customerId, reason } = Schema.parse(body);

    const result = await generateFollowUpSuggestion(
      BigInt(customerId),
      reason
    );
    if (!result) {
      return NextResponse.json({ error: "客户不存在" }, { status: 404 });
    }
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input" }, { status: 400 });
    }
    logger.error("POST /api/ai/follow-up failed", {
      userId: guard.userId ?? undefined,
      ip: guard.ip ?? undefined,
    }, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}