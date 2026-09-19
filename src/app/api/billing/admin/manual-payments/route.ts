// GET /api/billing/admin/manual-payments — 管理员看待审付款申请 (内测人工通道)
// 权限: role=admin (服务端查库判定)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { listManualPaymentsForAdmin } from "@/lib/billing/manual-pay";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, BigInt(session.user.id)))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json({ error: "只有管理员能看", code: "FORBIDDEN" }, { status: 403 });
  }

  const statusParam = new URL(request.url).searchParams.get("status");
  const status =
    statusParam === "pending" || statusParam === "approved" || statusParam === "rejected"
      ? statusParam
      : "pending";

  const rows = await listManualPaymentsForAdmin({ status });
  return NextResponse.json({
    status,
    count: rows.length,
    requests: rows.map((r) => ({
      id: r.id.toString(),
      userId: r.userId.toString(),
      planCode: r.planCode,
      amountCents: r.amountCents,
      payerNote: r.payerNote,
      proofUrl: r.proofUrl,
      status: r.status,
      createdAt: r.createdAt.toISOString(),
    })),
  });
}
