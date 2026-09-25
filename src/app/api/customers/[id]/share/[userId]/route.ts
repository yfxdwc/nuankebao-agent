// ============================================
// DELETE /api/customers/[id]/share/[userId]
// Phase D (主文档 §6.5.4 API + ADR-0019 §4.3)
// ============================================
// 撤销推送:
//   - body: { reason } 必填 (admin / 当前 owner 撤销时), 其它 (推送人/接收人撤销) 可选
//   - 撤销权: 推送人 / 接收人 / 当前归属人 / admin 四方 (S5)
//   - 幂等: 重复撤销 200 alreadyRevoked (不返 404)
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getRbacContextForSession } from "@/lib/auth/rbac";
import {
  revokeCustomerShare,
  type RevokeShareFailure,
} from "@/lib/db/queries/customer-share";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { logger } from "@/lib/errors";

const BodySchema = z.object({
  /** 撤销原因 (≤ 200 字; admin / 当前 owner 撤销必填, 走 audit) */
  reason: z.string().max(200).min(1, "撤销原因为必填").optional(),
});

const FAILURE_MESSAGE: Record<RevokeShareFailure, string> = {
  CUSTOMER_NOT_FOUND: "客户档案不存在或已删除",
  ACTIVE_SHARE_NOT_FOUND: "该客户没有这条 active 推送",
  NOT_AUTHORIZED: "只有推送人 / 接收人 / 当前归属人 / 系统管理员能撤销 (主文档 §6.5.2 S5)",
  REASON_REQUIRED: "系统管理员 / 当前归属人撤销时必填原因 (主文档 §6.5.2 S5)",
};

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; userId: string }> },
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const { id, userId } = await params;
  if (!/^\d+$/.test(id) || !/^\d+$/.test(userId)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  // body 缺省按 {} 处理 (推送人/接收人撤销时 reason 可选)
  const parsed = BodySchema.safeParse(body ?? {});
  if (!parsed.success) {
    return NextResponse.json(
      { error: "撤销原因格式错误", details: parsed.error.errors },
      { status: 400 },
    );
  }

  try {
    const actorUserId = BigInt(session.user.id);
    const rbacCtx = await getRbacContextForSession(session);
    const ctx = getAuditContextFromRequest(request, session);
    const result = await revokeCustomerShare(
      {
        customerId: BigInt(id),
        toUserId: BigInt(userId),
        actorUserId,
        reason: parsed.data.reason ?? null,
      },
      // 注意: revokeCustomerShare 内部会再次查 DB; 角色由 actorAdmin 重新读;
      // 但 session 兜底优先用 session.role (与 shareCustomer 同口径)
      ctx,
    );

    if (!result.ok) {
      return NextResponse.json(
        {
          error: FAILURE_MESSAGE[result.code],
          code: result.code,
        },
        { status: codeToStatus(result.code) },
      );
    }

    // 主文档 §6.5.4: 撤销 200 (幂等: alreadyRevoked 也返 200)
    return NextResponse.json({ revoked: true, alreadyRevoked: result.alreadyRevoked });
  } catch (e) {
    logger.error("DELETE /api/customers/[id]/share/[userId] failed", { id, userId }, e);
    return NextResponse.json({ error: "服务器内部错误" }, { status: 500 });
  }
}

function codeToStatus(code: RevokeShareFailure): number {
  switch (code) {
    case "CUSTOMER_NOT_FOUND":
    case "ACTIVE_SHARE_NOT_FOUND":
      return 404;
    case "NOT_AUTHORIZED":
      return 403;
    case "REASON_REQUIRED":
      return 400;
    default:
      return 400;
  }
}
