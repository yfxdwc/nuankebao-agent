import { NextRequest, NextResponse } from "next/server";
import { listGuests, createGuest } from "@/lib/db/queries/salon";
import { GuestCreateSchema } from "@/lib/salon/validation";
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
  const mine = searchParams.get("mine") === "1";

  const list = await listGuests(salonId, authRes.userId, { mine });
  if (list === null) return notFound();
  return NextResponse.json({ items: list });
}

/** 登记二级客人 (非 app 用户; 主理人/会务/受邀者均可, 受邀者只能登记自己的) */
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
    const input = GuestCreateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const created = await createGuest(salonId, input, ctx, authRes.userId);
    if (!created) {
      return NextResponse.json({ error: "无法登记 (手机号已登记过 / 无权限 / 沙龙已取消)" }, { status: 409 });
    }
    return NextResponse.json(created, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/guests");
  }
}
