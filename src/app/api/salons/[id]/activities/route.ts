import { NextRequest, NextResponse } from "next/server";
import { listActivities, createActivity } from "@/lib/db/queries/salon";
import { ActivityCreateSchema } from "@/lib/salon/validation";
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
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "100"), 300);

  const list = await listActivities(salonId, authRes.userId, limit);
  if (list === null) return notFound();
  return NextResponse.json({ items: list });
}

/** 发公告 (主理人/会务) / 提问 / 留言 (所有参与者) */
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
    const input = ActivityCreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const created = await createActivity(salonId, input, ctx, authRes.userId);
    if (!created) return notFound();
    return NextResponse.json(created, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/activities");
  }
}
