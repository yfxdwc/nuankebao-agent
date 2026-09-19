// POST /api/billing/admin/pay-info — 管理员设置收款码/收款人/备注提示 (不用改代码)
//
// Body: { qrUrl?, payeeName?, noteHint?, enabled? }
// qrUrl 一般是先 POST /api/photos?purpose=payment_qr 拿到的 /uploads/xxx.png

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { getManualPayInfo, setManualPayConfig } from "@/lib/billing/manual-pay";
import { logger } from "@/lib/errors";

const Schema = z.object({
  qrUrl: z.string().max(300).nullable().optional(),
  payeeName: z.string().max(50).nullable().optional(),
  noteHint: z.string().max(120).nullable().optional(),
  enabled: z.boolean().optional(),
});

export async function POST(request: NextRequest) {
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
    return NextResponse.json({ error: "只有管理员能设置", code: "FORBIDDEN" }, { status: 403 });
  }

  try {
    const input = Schema.parse(await request.json());
    await setManualPayConfig({ actorUserId: actorId, ...input });
    return NextResponse.json({ ok: true, info: await getManualPayInfo() });
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "参数不对", details: e.errors }, { status: 400 });
    }
    logger.error("POST admin/pay-info failed", {}, e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
