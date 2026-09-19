// POST /api/billing/admin/grant — 手工开通/延期会员 (S0 唯一收款后入口)
//
// 为什么 S0 需要它: 还没接在线支付前, 用户用个体户收款码/转账付钱, 管理员在后台点一下开通。
// 将来 S1 接支付后, 这条仍然要保留 —— 客服补偿/大客户赠送都要用。
//
// 边界:
//   - 只有 role=admin 能调 (RBAC)
//   - 每次发放写 entitlement_grant (含 grantedByUserId + reason + 幂等键)
//     → membership/entitlement_grant 都挂了审计触发器, 谁给谁开了多久可追溯
//   - 天数只增不减 (要减 = 走调整, 不在 S0 范围)

import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { user as userTable } from "@/lib/db/schema";
import { adminGrant, BillingError } from "@/lib/billing/entitlements";
import { logger } from "@/lib/errors";

const Schema = z.object({
  userId: z.string().regex(/^\d+$/, "userId 必须是数字"),
  days: z.number().int().min(1).max(3650),
  note: z.string().max(200).optional(),
});

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  const actorId = BigInt(session.user.id);
  const [actor] = await db
    .select({ role: userTable.role, name: userTable.name })
    .from(userTable)
    .where(eq(userTable.id, actorId))
    .limit(1);

  if (actor?.role !== "admin") {
    return NextResponse.json(
      { error: "只有管理员能开通/延期会员", code: "FORBIDDEN" },
      { status: 403 }
    );
  }

  try {
    const body = await request.json();
    const input = Schema.parse(body);

    const result = await adminGrant({
      targetUserId: BigInt(input.userId),
      days: input.days,
      actorUserId: actorId,
      note: input.note,
    });

    return NextResponse.json(result);
  } catch (e) {
    if (e instanceof z.ZodError) {
      return NextResponse.json(
        { error: "参数不对", details: e.errors },
        { status: 400 }
      );
    }
    if (e instanceof BillingError) {
      return NextResponse.json(
        { error: e.message, code: e.code },
        { status: e.status }
      );
    }
    logger.error("POST /api/billing/admin/grant failed", {}, e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
