// POST /api/billing/admin/manual-payments/[id] — 管理员核销 (approve 开通 / reject 驳回)
//
// Body: { decision: 'approve' | 'reject', grantedDays?: number, rejectReason?: string }
// approve → 同一请求内给会员加天数 (grantDays, 幂等键 = 申请单 id)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { BillingError } from "@/lib/billing/entitlements";
import { decideManualPayment } from "@/lib/billing/manual-pay";
import { logger } from "@/lib/errors";

const Schema = z.object({
  decision: z.enum(["approve", "reject"]),
  grantedDays: z.number().int().min(1).max(3650).optional(),
  rejectReason: z.string().max(200).optional(),
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

  const actorId = BigInt(session.user.id);
  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, actorId))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json({ error: "只有管理员能核销", code: "FORBIDDEN" }, { status: 403 });
  }

  try {
    const { id } = await params;
    if (!/^\d+$/.test(id)) {
      return NextResponse.json({ error: "id 不对" }, { status: 400 });
    }
    const input = Schema.parse(await request.json());

    const result = await decideManualPayment({
      requestId: BigInt(id),
      actorUserId: actorId,
      decision: input.decision,
      grantedDays: input.grantedDays,
      rejectReason: input.rejectReason,
    });

    return NextResponse.json(result);
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "参数不对", details: e.errors }, { status: 400 });
    }
    if (e instanceof BillingError) {
      return NextResponse.json({ error: e.message, code: e.code }, { status: e.status });
    }
    logger.error("POST admin/manual-payments/[id] failed", {}, e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
