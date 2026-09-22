import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { z } from "zod";
import {
  getCustomerById,
  updateCustomer,
  softDeleteCustomer,
} from "@/lib/db/queries/customer";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { hasFeatureAccess } from "@/lib/billing/guard";
import { FEATURES } from "@/lib/billing/features";

const UpdateCustomerSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  phone: z.string().regex(/^1[3-9]\d{9}$/, "手机号格式错误").optional(),
  gender: z.enum(["M", "F", "U"]).optional(),
  birthYear: z.number().int().min(1900).max(new Date().getFullYear()).optional(),
  // 生日细化 (主人 2026-09-18): 显式传 null = 清空 (不知道)
  birthMonth: z.number().int().min(1).max(12).nullable().optional(),
  birthDay: z.number().int().min(1).max(31).nullable().optional(),
  birthCalendar: z.enum(["solar", "lunar"]).optional(),
  birthdayRemindDays: z.number().int().refine((v) => [7, 3, 0].includes(v), {
    message: "提醒强度只能是 7 / 3 / 0 (天)",
  }).nullable().optional(),
  healthTags: z.array(z.string()).optional(),
  diseaseHistory: z.string().optional(),
  allergyHistory: z.string().optional(),
  notes: z.string().optional(),
  // ❌ referrerId 已废弃 (ADR-0015 Q4, 主人 2026-09-22 拍): 死链路, 不再接受写入
  // 种子客户开关 (潜在客户, 主人 2026-09-18)
  isSeed: z.boolean().optional(),
  // 客户头像: 传 null = 恢复默认首字 (白名单校验在 query 层)
  avatar: z.string().max(300).nullable().optional(),
});

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  // IDOR 修复 (ADR-0015 步骤 1 收尾): 「我的客户」以外的 id 一律当**不存在** (404)
  //   口径与列表完全相同 (owner_id = 我 ∪ 直推加盟); admin / dev skip-auth 无身份 → 不过滤
  const rbacCtx = await getRbacContextForSession(session);
  const scope = rbacCtx ? customerRbacFilter(rbacCtx) : undefined;
  const customer = await getCustomerById(BigInt(id), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope,
  });
  if (!customer) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // ADR-0012: 非会员看不到生日提醒设置 (数据仍在, 续费即恢复)
  const reminderOn = await hasFeatureAccess(session?.user?.id, FEATURES.CRM_BIRTHDAY_REMINDER);
  return NextResponse.json(reminderOn ? customer : { ...customer, birthdayRemindDays: null });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const input = UpdateCustomerSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    // IDOR 修复: 不属于我的客户 → 影响 0 行 → 404 (不泄露存在性)
    const rbacCtx = await getRbacContextForSession(session);
    const customer = await updateCustomer(BigInt(id), input, ctx, {
      viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
      scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
    });

    if (!customer) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(customer);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    // 头像白名单等业务校验错误 → 400 (把原因透给客户端, 不吞成 500)
    if (error instanceof Error && error.message.startsWith("头像值不合法")) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    console.error("[PATCH /api/customers/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const ctx = getAuditContextFromRequest(request, session);
  // IDOR 修复: 不属于我的客户 → 影响 0 行 → 404
  const rbacCtx = await getRbacContextForSession(session);
  const success = await softDeleteCustomer(
    BigInt(id),
    ctx,
    rbacCtx ? customerRbacFilter(rbacCtx) : undefined
  );

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}