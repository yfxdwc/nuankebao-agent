import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateFollowUpSuggestion } from "@/lib/ai/follow-up";
import { apiGuard } from "@/lib/api-guard";
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