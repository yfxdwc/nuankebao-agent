// POST /api/billing/manual-payments — 用户提交"我已支付" (内测人工通道)
//
// Body: { planCode: 'monthly' | 'quarterly', payerNote?, proofUrl? }
// proofUrl 走 POST /api/photos?purpose=payment_proof (免费, 不受会员限制 —— 付钱的人还没会员)

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { BillingError } from "@/lib/billing/entitlements";
import { listMyManualPayments, submitManualPayment } from "@/lib/billing/manual-pay";
import { logger } from "@/lib/errors";

const Schema = z.object({
  planCode: z.enum(["monthly", "quarterly"]),
  payerNote: z.string().max(200).optional(),
  proofUrl: z.string().max(300).optional(),
});

export async function GET() {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ requests: [] });
  }
  const rows = await listMyManualPayments(BigInt(session.user.id));
  return NextResponse.json({
    requests: rows.map((r) => ({
      id: r.id.toString(),
      status: r.status,
      amountCents: r.amountCents,
      days: r.grantedDays ?? r.days,
      createdAt: r.createdAt.toISOString(),
    })),
  });
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = Schema.parse(body);

    const row = await submitManualPayment({
      userId: BigInt(session.user.id),
      planCode: input.planCode,
      payerNote: input.payerNote,
      proofUrl: input.proofUrl,
    });

    return NextResponse.json(
      {
        id: row.id.toString(),
        status: row.status,
        amountCents: row.amountCents,
        days: row.days,
        message: "已提交, 管理员核对到账后会给你开通",
      },
      { status: 201 }
    );
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "参数不对", details: e.errors }, { status: 400 });
    }
    if (e instanceof BillingError) {
      return NextResponse.json({ error: e.message, code: e.code }, { status: e.status });
    }
    logger.error("POST /api/billing/manual-payments failed", {}, e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
