// GET /api/franchisees/placement-requests/:id — 单子详情 (含三方确认进度 + 我的角色)

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolvePlacementActor } from "@/lib/auth/viewer";
import { getPlacementRequest } from "@/lib/db/queries/franchisee-placement";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const actor = await resolvePlacementActor(session?.user?.id);
  if (!actor) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }
  const view = await getPlacementRequest(BigInt(id), {
    userId: actor.userId,
    fid: actor.fid,
    phoneHash: actor.phoneHash,
  });
  if (!view) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(view);
}
