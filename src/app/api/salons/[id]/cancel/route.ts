import { NextRequest, NextResponse } from "next/server";
import { cancelSalon } from "@/lib/db/queries/salon";
import { SalonCancelSchema } from "@/lib/salon/validation";
import {
  requireUserId,
  parseId,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

/**
 * 取消沙龙 (status=cancelled; 保留数据 + 系统动态)
 * 请求体: { reason: string (10-500 字) } — 主理人写给受邀者的详细说明
 */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id } = await params;
  const salonId = parseId(id);
  if (!salonId) return notFound();

  let body: unknown = {};
  try {
    body = await request.json();
  } catch {
    // 允许空 body 走默认错误信息; 但 reason 是必填, 下面 zod 会拦
  }
  const parsed = SalonCancelSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "取消原因必填, 10-500 字", issues: parsed.error.issues },
      { status: 400 },
    );
  }

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const result = await cancelSalon(
    salonId,
    ctx,
    authRes.userId,
    parsed.data.reason,
  );
  if (!result) return notFound();
  return NextResponse.json(result);
}
