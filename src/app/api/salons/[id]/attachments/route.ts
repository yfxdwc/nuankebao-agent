import { NextRequest, NextResponse } from "next/server";
import { listAttachments, createAttachment } from "@/lib/db/queries/salon";
import { AttachmentCreateSchema } from "@/lib/salon/validation";
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

  const list = await listAttachments(salonId, authRes.userId);
  if (list === null) return notFound();
  return NextResponse.json({ items: list });
}

/** 上传沙龙资料 (先走 POST /api/photos 拿 URL, 再登记在这里) */
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
    const input = AttachmentCreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const created = await createAttachment(salonId, input, ctx, authRes.userId);
    if (!created) return notFound();
    return NextResponse.json(created, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/attachments");
  }
}
