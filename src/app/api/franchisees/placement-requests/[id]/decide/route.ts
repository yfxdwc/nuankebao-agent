// POST /api/franchisees/placement-requests/:id/decide
// 三方之一拍板: { decision: 'approve' | 'reject', side?: 'left' | 'right' }
//   - side 只有 promote 单的**上级本人**需要传 (主人 2026-09-21 拍:
//     「我在我的上级是处于 a线还是 b线由我的上级自己决定」→ 由上级挑自己空着的点位)
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

  let body: { decision?: string; side?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  const decision = body.decision === "reject" ? "reject" : "approve";
  const side =
    body.side === "left" || body.side === "right" ? body.side : undefined;

  try {
    const view = await decidePlacementRequest(
      BigInt(id),
      { userId: actor.userId, fid: actor.fid, phoneHash: actor.phoneHash },
      decision,
      getAuditContextFromRequest(request, session),
      side
    );
    return NextResponse.json(view);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("[POST placement-requests/:id/decide]", msg);
    return NextResponse.json({ error: msg }, { status: 400 });
  }
}
