import { NextRequest, NextResponse } from "next/server";
import {
  updateInvitation,
  removeInvitation,
} from "@/lib/db/queries/salon";
import { InvitationUpdateSchema } from "@/lib/salon/validation";
import {
  requireUserId,
  parseId,
  handleRouteError,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; invId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  try {
    const { id, invId } = await params;
    const salonId = parseId(id);
    const invitationId = parseId(invId);
    if (!salonId || !invitationId) return notFound();

    const body = await request.json();
    const input = InvitationUpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const updated = await updateInvitation(
      salonId,
      invitationId,
      input,
      ctx,
      authRes.userId
    );
    if (!updated) return notFound();
    return NextResponse.json(updated);
  } catch (error) {
    return handleRouteError(error, "PATCH /api/salons/[id]/invitations/[invId]");
  }
}

/** 移除邀请 (标记 cancelled, 不物理删除, 保留审计痕迹) */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; invId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id, invId } = await params;
  const salonId = parseId(id);
  const invitationId = parseId(invId);
  if (!salonId || !invitationId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const ok = await removeInvitation(salonId, invitationId, ctx, authRes.userId);
  if (!ok) return notFound();
  return NextResponse.json({ success: true });
}
