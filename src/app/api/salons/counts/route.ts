// ============================================
// 沙龙 Tab 计数 (子页面角标用)
// ============================================
// GET /api/salons/counts → { organizing: number, invited: number }
// 口径 = 「进行中」 = status NOT IN ('finished','cancelled'),
// 与 GET /api/salons?includeFinished=0 完全一致 (调用方复用认知)
// ============================================

import { NextResponse } from "next/server";
import { getSalonActiveCounts } from "@/lib/db/queries/salon";
import { requireUserId, handleRouteError } from "@/lib/salon/route-helpers";

export async function GET() {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;
  try {
    const counts = await getSalonActiveCounts(authRes.userId);
    return NextResponse.json(counts);
  } catch (e) {
    return handleRouteError(e, "GET /api/salons/counts");
  }
}
