// GET /api/billing/referral/pending — 我推荐的人 (待确认 / 已确认 / 已驳回)
// 「我的」页 → 好友 (N) 入口用; 只有本人能看自己的推荐列表

import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { listMyReferrals } from "@/lib/billing/signup";

export async function GET() {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ referrals: [] });
  }

  const rows = await listMyReferrals(BigInt(session.user.id));
  return NextResponse.json({
    referrals: rows,
    pendingCount: rows.filter((r) => r.status === "pending").length,
  });
}
