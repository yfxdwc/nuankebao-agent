// POST /api/franchisees/placement-requests/:id/decide
// 三方之一拍板: { decision: 'approve' | 'reject' }
//   - 全部 approve → 事务内执行落位 (新设/移动) 并把单子置 executed
//   - 任一 reject  → 单子置 rejected, 点位预占释放, 不落位

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolvePlacementActor } from "@/lib/auth/viewer";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { decidePlacementRequest } from "@/lib/db/queries/franchisee-placement";

export async function POST(
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

  let body: { decision?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  const decision = body.decision === "reject" ? "reject" : "approve";

  try {
    const view = await decidePlacementRequest(
      BigInt(id),
      { userId: actor.userId, fid: actor.fid, phoneHash: actor.phoneHash },
      decision,
      getAuditContextFromRequest(request, session)
    );
    return NextResponse.json(view);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("[POST placement-requests/:id/decide]", msg);
    return NextResponse.json({ error: msg }, { status: 400 });
  }
}
