// ============================================
// POST /api/customers/claim — 把一位**已注册用户**加为我的客户 (归属声明)
// ============================================
// 主人 2026-09-22 拍 (ADR-0015 Q11/Q12/Q15): 两条添加路径共用这一个写口
//   ① 「我推荐的人」页 → 加为我的客户
//   ② 新建客户时填对方推荐码 → 识别到人后调本接口
//
// 规则 (Q15 先到先得):
//   - 归属仍为空 (owner_id IS NULL) → 声明成功
//   - 已经是我的 → 200 幂等 (alreadyMine: true)
//   - 已归属别人 → 409 (不做抢单)
//   - 自己 → 400 (「自己不应该是自己的客户」)
//   - 不存在 / 已软删 → 404
//
// 边界: 必须登录 (归属 = 谁的客户列表, 没有"我"就没有意义; dev skip-auth 也不行)
// 审计: customer 表有 audit 触发器 → UPDATE 自动进 audit_log

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { claimCustomerOwnership } from "@/lib/db/queries/customer";
import { getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const ClaimSchema = z.object({
  customerId: z.string().regex(/^\d+$/, "客户 ID 格式错误"),
});

const FAILURE: Record<
  "NOT_FOUND" | "SELF" | "OWNED_BY_OTHER",
  { status: number; error: string }
> = {
  NOT_FOUND: { status: 404, error: "客户不存在" },
  SELF: { status: 400, error: "不能把自己加为客户" },
  OWNED_BY_OTHER: { status: 409, error: "该客户已归属他人 (先到先得)" },
};

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = ClaimSchema.parse(body);

    // viewer 的加盟 id 只用于返回体的「加盟」类型判定 (与列表同口径)
    const rbacCtx = await getRbacContextForSession(session);

    const result = await claimCustomerOwnership(
      BigInt(input.customerId),
      BigInt(session.user.id),
      getAuditContextFromRequest(request, session),
      rbacCtx?.franchiseeId ?? null
    );

    if (!result.ok) {
      const f = FAILURE[result.code];
      return NextResponse.json({ error: f.error, code: result.code }, { status: f.status });
    }

    return NextResponse.json({
      ok: true,
      alreadyMine: result.alreadyMine,
      customer: result.customer,
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    console.error("[POST /api/customers/claim]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
