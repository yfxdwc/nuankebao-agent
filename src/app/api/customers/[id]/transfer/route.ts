import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import {
  transferCustomerOwnership,
  getCustomerOwnership,
  type TransferOwnershipFailure,
} from "@/lib/db/queries/customer";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { logger } from "@/lib/errors";

const BodySchema = z.object({
  /** 接收人的**邀请码** (不用 userId: 客户端不该拿别人的 id; 且服务端可复核) */
  toReferralCode: z.string().min(1).max(32),
});

/**
 * POST /api/customers/[id]/transfer
 * 把客户归属转给同事 (P8 管理维度, 主人 2026-09-23)
 *
 * 权限: **当前归属人本人** 或 **系统管理员**。
 *   (与「先到先得」不冲突 —— 先到先得约束抢单; 这是归属人自愿交接)
 *
 * 接收人用邀请码定位 (ADR-0016 D1 一个自然人 = 一个邀请码):
 *   客户端先调 `GET /api/referral/lookup?code=` 给用户看「张三 138****8000」确认,
 *   再把同一个 code 交到这里 —— 服务端**重新解析**, 不信客户端传来的 id。
 */
const FAILURE_MESSAGE: Record<TransferOwnershipFailure, string> = {
  NOT_FOUND: "客户不存在",
  CODE_NOT_FOUND: "邀请码不存在或对方账号已停用",
  NO_OWNER: "这位客户还没有归属人 —— 该用「认领」, 不是转移",
  NOT_OWNER: "只有当前归属人 (或系统管理员) 能转出客户",
  TO_SELF: "不能转给自己",
  TO_OWN_PROFILE: "不能把客户转给她本人",
  ALREADY_HERS: "这位客户已经是她的了",
};

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
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
      { error: "要填接收人的邀请码", details: parsed.error.errors },
      { status: 400 }
    );
  }

  try {
    const actorId = BigInt(session.user.id);
    const [actor] = await db
      .select({ role: userTable.role, customerId: userTable.customerId })
      .from(userTable)
      .where(eq(userTable.id, actorId))
      .limit(1);

    const ctx = getAuditContextFromRequest(request, session);
    const result = await transferCustomerOwnership(
      BigInt(id),
      actorId,
      parsed.data.toReferralCode,
      { isAdmin: actor?.role === "admin" },
      ctx
    );

    if (!result.ok) {
      // 权限类 → 403; 其余 (码不对/状态不对) → 400 (客户端按 message 显示)
      const status = result.code === "NOT_OWNER" ? 403 : 400;
      return NextResponse.json(
        { error: FAILURE_MESSAGE[result.code], code: result.code },
        { status }
      );
    }

    // 转出后返回新归属状态 —— 客户端据此刷新卡片, 不用再打一次接口
    const ownership = await getCustomerOwnership(
      BigInt(id),
      actorId,
      actor?.customerId ?? null
    );
    return NextResponse.json({
      toName: result.toName,
      fromUserId: result.fromUserId?.toString() ?? null,
      ownership,
    });
  } catch (error) {
    logger.error("POST /api/customers/[id]/transfer failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
