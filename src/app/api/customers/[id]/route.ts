import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { resolveViewerFranchiseeId } from "@/lib/auth/viewer";
import { z } from "zod";
import {
  getCustomerById,
  updateCustomer,
  softDeleteCustomer,
} from "@/lib/db/queries/customer";
import { getAuditContextFromRequest } from "@/lib/audit/context";

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
  // 客户推荐人. 显式 null = 清空推荐人
  referrerId: z.string().regex(/^\d+$/, "推荐人 ID 格式错误").nullable().optional(),
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
  const viewerFranchiseeId = await resolveViewerFranchiseeId(session?.user?.id);
  const customer = await getCustomerById(BigInt(id), { viewerFranchiseeId });
  if (!customer) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(customer);
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
    const customer = await updateCustomer(
      BigInt(id),
      input,
      ctx,
      await resolveViewerFranchiseeId(session?.user?.id)
    );

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
  const success = await softDeleteCustomer(BigInt(id), ctx);

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}