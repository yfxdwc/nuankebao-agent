import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { featureGuard } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";
import { z } from "zod";
import {
  createInteraction,
  listInteractionsByCustomer,
} from "@/lib/db/queries/interaction";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const CreateSchema = z.object({
  customerId: z.string().regex(/^\d+$/),
  type: z.enum(["phone", "wechat", "visit", "holiday_greeting", "other"]),
  summary: z.string().optional(),
  followUpAt: z.string().datetime().optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const customerId = searchParams.get("customerId");
  if (!customerId) {
    return NextResponse.json({ error: "customerId required" }, { status: 400 });
  }
  if (!/^\d+$/.test(customerId)) {
    return NextResponse.json({ error: "Invalid customerId" }, { status: 400 });
  }

  // 🔒 IDOR 修复 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §2):
  //   之前 `listInteractionsByCustomer(customerId)` 直接查 customer_id = X 的互动,
  //   任何登录者都能拿到任意客户的全量互动记录 (含加密 summary 解密后 → 信息泄漏)。
  //   修法 (与 GET /api/customers/[id] 同口径): 先对该 customerId 做
  //   `customerRbacFilter` 行级过滤 — 命中不到 → 404, 不泄漏存在性。
  //   注: 业务侧需要按 customerId 拉历史, 这条闸门不影响合法调用。
  const rbacCtx = await getRbacContextForSession(session);
  const visible = await getCustomerById(BigInt(customerId), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
  });
  if (!visible) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const items = await listInteractionsByCustomer(customerId);
  return NextResponse.json({ items });
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // ADR-0012: 互动记录是会员功能 (GET 允许看历史, POST 需会员)
  const gate = await featureGuard(session?.user?.id, FEATURES.CRM_INTERACTION);
  if (gate) return gate;

  try {
    const body = await request.json();
    const input = CreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    // dev 模式 (DEV_SKIP_AUTH=1) session 为 null → 同 customers/route.ts 约定用 0
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const interaction = await createInteraction(input, ctx, userId);

    return NextResponse.json(interaction, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/interactions]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}