import { NextRequest, NextResponse } from "next/server";
import { updateGuest, deleteGuest } from "@/lib/db/queries/salon";
import { GuestUpdateSchema } from "@/lib/salon/validation";
import {
  requireUserId,
  parseId,
  handleRouteError,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; guestId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  try {
    const { id, guestId } = await params;
    const salonId = parseId(id);
    const gId = parseId(guestId);
    if (!salonId || !gId) return notFound();

    const body = await request.json();
    const input = GuestUpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const updated = await updateGuest(salonId, gId, input, ctx, authRes.userId);
    if (!updated) return notFound();
    return NextResponse.json(updated);
  } catch (error) {
    return handleRouteError(error, "PATCH /api/salons/[id]/guests/[guestId]");
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; guestId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id, guestId } = await params;
  const salonId = parseId(id);
  const gId = parseId(guestId);
  if (!salonId || !gId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const ok = await deleteGuest(salonId, gId, ctx, authRes.userId);
  if (!ok) return notFound();
  return NextResponse.json({ success: true });
}
