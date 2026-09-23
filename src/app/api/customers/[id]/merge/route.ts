import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import {
  mergeCustomers,
  type MergeCustomersFailure,
} from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { logger } from "@/lib/errors";

const BodySchema = z.object({
  /** 把这位客户**合并进**哪一条 (目标保留, 本客户软删) */
  intoCustomerId: z.string().regex(/^\d+$/, "目标客户编号不对"),
});

/**
 * POST /api/customers/[id]/merge
 * 合并重复客户 (P8 管理维度, 主人 2026-09-23)
 *
 * 语义: `[id]` = **被合并掉的那条** (来源, 软删); `intoCustomerId` = **保留的那条** (目标)。
 *
 * 与 ADR-0016「撞号不静默合并」不冲突: 那条禁的是**系统自动**按手机号合并;
 * 这里是**人明确指定**同一个人, 明确 + 留痕 + 可解释。
 *
 * 权限: 来源必须在操作人可管的范围内 (IDOR); admin 可跨范围。
 * 目标也要可管 —— 否则等于"把我的客户并到我无权看的档案里", 数据就看不见了。
 */
const FAILURE_MESSAGE: Record<MergeCustomersFailure, string> = {
  NOT_FOUND: "目标客户不存在或已归档",
  SAME: "不能合并到自己",
  BOTH_LINKED:
    "两条档案都绑了 app 账号 —— 无法判断谁是谁，请先用「填邀请码绑定身份」理清，或联系管理员",
  NO_SCOPE: "没有权限操作这条客户",
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
      { error: "要选一条保留的客户", details: parsed.error.errors },
      { status: 400 }
    );
  }

  try {
    const actorId = BigInt(session.user.id);
    const [actor] = await db
      .select({ role: userTable.role })
      .from(userTable)
      .where(eq(userTable.id, actorId))
      .limit(1);
    const isAdmin = actor?.role === "admin";

    const rbacCtx = await getRbacContextForSession(session);
    const scope = isAdmin || !rbacCtx ? undefined : customerRbacFilter(rbacCtx);

    const ctx = getAuditContextFromRequest(request, session);
    const result = await mergeCustomers(
      BigInt(id),
      BigInt(parsed.data.intoCustomerId),
      // 目标也受同一范围限制: 否则"把我的客户并进我看不到的档案" = 数据凭空消失
      { sourceScope: scope, targetScope: scope },
      ctx
    );

    if (!result.ok) {
      const status = result.code === "NO_SCOPE" ? 403 : 400;
      return NextResponse.json(
        { error: FAILURE_MESSAGE[result.code], code: result.code },
        { status }
      );
    }

    return NextResponse.json({
      mergedInto: parsed.data.intoCustomerId,
      ...result,
      relinkedUserId: result.relinkedUserId?.toString() ?? null,
    });
  } catch (error) {
    logger.error("POST /api/customers/[id]/merge failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
