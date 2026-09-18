import { NextRequest, NextResponse } from "next/server";
import {
  getSalonDetail,
  updateSalon,
  softDeleteSalon,
} from "@/lib/db/queries/salon";
import { SalonUpdateSchema } from "@/lib/salon/validation";
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

  const detail = await getSalonDetail(salonId, authRes.userId);
  if (!detail) return notFound();
  return NextResponse.json(detail);
}

export async function PATCH(
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
    const input = SalonUpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const updated = await updateSalon(salonId, input, ctx, authRes.userId);
    if (!updated) return notFound();
    return NextResponse.json(updated);
  } catch (error) {
    return handleRouteError(error, "PATCH /api/salons/[id]");
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id } = await params;
  const salonId = parseId(id);
  if (!salonId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const success = await softDeleteSalon(salonId, ctx, authRes.userId);
  if (!success) return notFound();
  return NextResponse.json({ success: true });
}
