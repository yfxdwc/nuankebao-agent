// POST /api/admin/nodes/[fid]/reparent — 管理员: 协商处理后**强改上层**
//   主人 2026-09-21 拍: 「「上层」= 点位父, 不一定是推荐码提供人。上层一旦有人不能撤换,
//   除非联系系统管理员协商处理。」+「给管理员一个『协商处理后强改上层』的后台功能」
//
// 为什么独立接口 (不塞进 /api/franchisees/placement-requests):
//   三方确认 = 本人 + 设置者 + 父节点; 本功能的**前提正是三方谈不拢**。
//   塞进同一状态机会给"单方即执行"开分支 —— 同 /api/admin/users/[id]/root 的理由。
//
// 权限: role=admin (服务端查库; 客户端藏按钮只是体验); 原因必填 (审计留痕)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { adminReparentNode } from "@/lib/db/queries/franchisee-reparent";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const BodySchema = z.object({
  /** 新的上层节点 = 点位父 (franchisee.id) */
  newParentFid: z.string().regex(/^\d+$/, "newParentFid 必须是节点编号"),
  /** 她在新上层下面占哪条线 (A线 = left / B线 = right; 由上层定, 这里是管理员代定) */
  side: z.enum(["left", "right"]),
  /** 原因 (必填 2-200 字, 留痕: 这条通道是"协商处理", 没原因将来查不清) */
  reason: z.string().min(2, "原因至少要 2 个字").max(200, "原因最长 200 字"),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ fid: string }> }
) {
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
    return NextResponse.json(
      { error: "只有系统管理员能协商处理改上层", code: "FORBIDDEN" },
      { status: 403 }
    );
  }

  const { fid } = await params;
  if (!/^\d+$/.test(fid)) {
    return NextResponse.json({ error: "Invalid node id" }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  const parsed = BodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "改上层要选新上层 + A线/B线, 并填原因 (2-200 字)",
        details: parsed.error.errors,
      },
      { status: 400 }
    );
  }

  try {
    const result = await adminReparentNode(
      {
        moveFid: BigInt(fid),
        newParentFid: BigInt(parsed.data.newParentFid),
        side: parsed.data.side,
        reason: parsed.data.reason,
        adminUserId: BigInt(session.user.id),
      },
      getAuditContextFromRequest(request, session)
    );
    return NextResponse.json(result, { status: 200 });
  } catch (error) {
    if (error instanceof Error) {
      // 业务拒绝 (成环 / 那条线有人 / 没账号 / 没填原因 ...) → 400, 不当 500
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("[POST /api/admin/nodes/[fid]/reparent]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
