// /api/franchisees/placement-requests
// 加盟落位「三方确认」工作流 (主人 2026-09-18 拍; 见 docs/placement-confirmation-design.md)
//
// POST 发起: { kind: 'create'|'move'|'unjoin', targetParentId, side, newName?, newPhone?, newNotes?, moveFid? }
//   - unjoin (解除加盟): 传 kind='unjoin' + moveFid=要解除的节点; targetParentId/side 可省 (服务端按节点推)
//   - 发起人自动记 1 票 (设置者本人)
//   - 点位 pending 期间预占 (DB 部分唯一索引兜底)
// GET  列表: ?scope=mine|to_confirm&status=pending|executed|...
//   - mine       = 我发起的
//   - to_confirm = 等我拍板的 (我是目标父节点 / 新加盟商本人)

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolvePlacementActor } from "@/lib/auth/viewer";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import {
  createPlacementRequest,
  listPlacementRequests,
  type PlacementRequestScope,
} from "@/lib/db/queries/franchisee-placement";

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const actor = await resolvePlacementActor(session?.user?.id);
  // 主人 2026-09-19: 只有「已加盟用户」或「系统管理员」能设置加盟
  if (!actor || (actor.fid == null && !actor.isAdmin)) {
    return NextResponse.json(
      { error: "只有已加盟用户或系统管理员才能设置加盟" },
      { status: 403 }
    );
  }

  let body: {
    kind?: string;
    targetParentId?: string;
    side?: string;
    newName?: string;
    newPhone?: string;
    newNotes?: string;
    moveFid?: string;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const kind: "create" | "move" | "unjoin" =
    body.kind === "move" ? "move" : body.kind === "unjoin" ? "unjoin" : "create";
  if (
    kind !== "unjoin" &&
    (!body.targetParentId || !/^\d+$/.test(body.targetParentId))
  ) {
    return NextResponse.json({ error: "targetParentId 必填" }, { status: 400 });
  }
  if (kind === "unjoin" && (!body.moveFid || !/^\d+$/.test(body.moveFid))) {
    return NextResponse.json({ error: "unjoin 必须给 moveFid" }, { status: 400 });
  }
  const side = body.side === "right" ? "right" : "left";

  try {
    const view = await createPlacementRequest(
      {
        kind,
        initiatorFid: actor.fid,
        initiatorUserId: actor.userId,
        initiatorIsAdmin: actor.isAdmin,
        initiatorPhoneHash: actor.phoneHash,
        targetParentFid: body.targetParentId
          ? BigInt(body.targetParentId)
          : BigInt(0), // unjoin: 服务端会用节点自己的位置覆盖
        targetSide: side,
        newName: body.newName,
        newPhone: body.newPhone,
        newNotes: body.newNotes,
        moveFid:
          body.moveFid && /^\d+$/.test(body.moveFid)
            ? BigInt(body.moveFid)
            : undefined,
      },
      getAuditContextFromRequest(request, session)
    );
    return NextResponse.json(view, { status: 201 });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("[POST /api/franchisees/placement-requests]", msg);
    return NextResponse.json({ error: msg }, { status: 400 });
  }
}

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const actor = await resolvePlacementActor(session?.user?.id);
  if (!actor) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const scope: PlacementRequestScope =
    searchParams.get("scope") === "to_confirm" ? "to_confirm" : "mine";
  const status = searchParams.get("status") ?? "pending";

  try {
    const items = await listPlacementRequests(actor, scope, { status });
    return NextResponse.json({ items, scope, status });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.error("[GET /api/franchisees/placement-requests]", msg);
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
