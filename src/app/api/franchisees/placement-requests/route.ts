// /api/franchisees/placement-requests
// 加盟落位「三方确认」工作流 (主人 2026-09-18 拍; 见 docs/placement-confirmation-design.md)
//
// POST 发起: { kind: 'create'|'unjoin'|'promote', targetParentId, side, newName?, newPhone?, newNotes?, unjoinFid? }
//   - unjoin (解除加盟): 传 kind='unjoin' + unjoinFid=要解除的节点; targetParentId/side 可省 (服务端按节点推)
//   - promote (向上认领上级, 主人 2026-09-21 拍 B2): 传 kind='promote' + 上级 newName/newPhone;
//     targetParentId / side 都免传 —— 锚点 = 发起人自己的那个根 (服务端填),
//     **我在上级的 A线/B线 由上级本人在确认时决定** (拍板原话), 不由认领人提交。
//     上级若已是 app 里的节点 → 复用他的节点 (两棵树合并); 否则执行时新建。
//     双方确认 (我 + 上级本人)
//   - ⚠ kind='move' (直接移动点位) 已下线 (主人 2026-09-19 拍): 点位变更必须先解除加盟再重新落位
//     （老的 moveFid 字段名仍接受作为 unjoin 的兼容别名, 但 kind='move' 会被明确拒绝）
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
    /** ★ P6 (ADR-0016 D1): 优先按**邀请码**找账号 (给了码 → 姓名/手机号取自账号) */
    newReferralCode?: string;
    newPhone?: string;
    newNotes?: string;
    unjoinFid?: string;
    /** @deprecated 老客户端字段 (语义 = unjoin 主体); 新代码用 unjoinFid */
    moveFid?: string;
    /**
     * ★ Phase B §6 E1 (migration 0027): 落位发起时显式选的直推者 (大整数 fid 字符串)。
     *   - 仅 kind='create' 生效; unjoin/promote 不传
     *   - 必须落在落位后她的祖先链 (targetParentFid + 上层直系 3 层) → 否则 400
     *   - 未传 → 默认 = 发起人 (admin 发起回退到 targetParentFid)
     */
    referrerFid?: string;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  // 主人 2026-09-19 拍: 「移动到其他点位」下线 → kind='move' 明确拒绝, 不静默当 create
  if (body.kind === "move") {
    return NextResponse.json(
      {
        error:
          "点位不能直接移动: 请先「解除加盟」, 再重新加盟落位 (新点位走三方确认)",
      },
      { status: 400 }
    );
  }
  const kind: "create" | "unjoin" | "promote" =
    body.kind === "unjoin"
      ? "unjoin"
      : body.kind === "promote"
        ? "promote"
        : "create";
  const unjoinFidRaw = body.unjoinFid ?? body.moveFid;
  // promote 的锚点 = 发起人自己的根 → 不需要（也不该）让客户端传 targetParentId
  if (
    kind === "create" &&
    (!body.targetParentId || !/^\d+$/.test(body.targetParentId))
  ) {
    return NextResponse.json({ error: "targetParentId 必填" }, { status: 400 });
  }
  if (kind === "unjoin" && (!unjoinFidRaw || !/^\d+$/.test(unjoinFidRaw))) {
    return NextResponse.json({ error: "unjoin 必须给 unjoinFid" }, { status: 400 });
  }
  const side = body.side === "right" ? "right" : "left";

  // ★ Phase B §6 E1: referrerFid 校验 (正整数; 只对 create 透传; unjoin/promote 忽略)
  let referrerFid: bigint | undefined = undefined;
  if (body.referrerFid != null && body.referrerFid !== "") {
    if (!/^\d+$/.test(body.referrerFid)) {
      return NextResponse.json({ error: "referrerFid 必须是正整数" }, { status: 400 });
    }
    if (kind !== "create") {
      return NextResponse.json(
        { error: "referrerFid 只对「创建加盟」(kind=create) 生效" },
        { status: 400 },
      );
    }
    referrerFid = BigInt(body.referrerFid);
  }

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
        newReferralCode: body.newReferralCode,
        newPhone: body.newPhone,
        newNotes: body.newNotes,
        unjoinFid:
          unjoinFidRaw && /^\d+$/.test(unjoinFidRaw)
            ? BigInt(unjoinFidRaw)
            : undefined,
        referrerFid,
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
