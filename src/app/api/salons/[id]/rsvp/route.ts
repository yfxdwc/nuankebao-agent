import { NextRequest, NextResponse } from "next/server";
import { rsvpSalon } from "@/lib/db/queries/salon";
import { RsvpSchema } from "@/lib/salon/validation";
import {
  requireUserId,
  parseId,
  handleRouteError,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

/** 受邀者回复: 接受 / 婉拒 / 待定 + 预计带约人数 + 留言 + 报名表单值 */
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
    const input = RsvpSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const result = await rsvpSalon(salonId, authRes.userId, input, ctx);
    if (!result) return notFound();
    return NextResponse.json(result);
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/rsvp");
  }
}
