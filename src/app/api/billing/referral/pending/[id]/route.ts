// POST /api/billing/referral/pending/[id] — 推荐人确认「这是我朋友」/ 否认
//
// Body: { decision: 'confirm' | 'reject', reason?: string }
// confirm → 给**新用户**发 15 天 (幂等); 推荐人自己的 15 天仍等其成为加盟者 (D23)
// reject  → 不发任何权益 (防码被转发后陌生人白嫖)

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { BillingError } from "@/lib/billing/entitlements";
import { confirmReferral, rejectReferral } from "@/lib/billing/signup";
import { logger } from "@/lib/errors";

const Schema = z.object({
  decision: z.enum(["confirm", "reject"]),
  reason: z.string().max(200).optional(),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  try {
    const { id } = await params;
    if (!/^\d+$/.test(id)) {
      return NextResponse.json({ error: "id 不对" }, { status: 400 });
    }
    const input = Schema.parse(await request.json());
    const actorId = BigInt(session.user.id);

    const result =
      input.decision === "confirm"
        ? await confirmReferral({ referrerUserId: actorId, rewardId: BigInt(id) })
        : await rejectReferral({
            referrerUserId: actorId,
            rewardId: BigInt(id),
            reason: input.reason,
          });

    return NextResponse.json(result);
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "参数不对" }, { status: 400 });
    }
    if (e instanceof BillingError) {
      return NextResponse.json({ error: e.message, code: e.code }, { status: e.status });
    }
    logger.error("POST referral/pending/[id] failed", {}, e);
    return NextResponse.json({ error: "操作失败, 请重试" }, { status: 500 });
  }
}
