import { NextRequest, NextResponse } from "next/server";
import {
  listInvitations,
  createInvitation,
} from "@/lib/db/queries/salon";
import { InvitationCreateSchema } from "@/lib/salon/validation";
import {
  requireUserId,
  parseId,
  handleRouteError,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id } = await params;
  const salonId = parseId(id);
  if (!salonId) return notFound();

  const { searchParams } = new URL(request.url);
  const includeCancelled = searchParams.get("includeCancelled") === "1";

  const list = await listInvitations(salonId, authRes.userId, { includeCancelled });
  if (list === null) return notFound();
  return NextResponse.json({ items: list });
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  try {
    const { id } = await params;
    const salonId = parseId(id);
    if (!salonId) return notFound();

    const body = await request.json();
    const input = InvitationCreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const created = await createInvitation(salonId, input, ctx, authRes.userId);
    if (!created) {
      // 权限不足 / 沙龙已结束 / 手机号重复 → 语义混在 409, 前端提示"可能已邀请过"
      return NextResponse.json(
        { error: "无法添加邀请 (已邀请过 / 无权限 / 沙龙已结束)" },
        { status: 409 }
      );
    }
    return NextResponse.json(created, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/invitations");
  }
}
