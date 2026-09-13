// /api/franchisees/me/available-position?referrerId=X
// GET 返回推荐人 X 的左右位置占用情况 (frontend preview)
// Plan F1: 给前端展示"左侧有 / 右侧空"等提示

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getAvailablePosition } from "@/lib/db/queries/franchisee";

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const referrerIdStr = searchParams.get("referrerId");
  if (!referrerIdStr || !/^\d+$/.test(referrerIdStr)) {
    return NextResponse.json(
      { error: "referrerId required" },
      { status: 400 }
    );
  }

  const result = await getAvailablePosition(BigInt(referrerIdStr));
  return NextResponse.json(result);
}