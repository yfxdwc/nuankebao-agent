import { NextRequest, NextResponse } from "next/server";
import { deleteAttachment } from "@/lib/db/queries/salon";
import {
  requireUserId,
  parseId,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; attId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id, attId } = await params;
  const salonId = parseId(id);
  const attachmentId = parseId(attId);
  if (!salonId || !attachmentId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const ok = await deleteAttachment(salonId, attachmentId, ctx, authRes.userId);
  if (!ok) return notFound();
  return NextResponse.json({ success: true });
}
