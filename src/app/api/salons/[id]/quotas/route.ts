import { NextRequest, NextResponse } from "next/server";
import { listQuotas, upsertQuota } from "@/lib/db/queries/salon";
import { QuotaUpsertSchema } from "@/lib/salon/validation";
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

  const list = await listQuotas(salonId, authRes.userId);
  if (list === null) return notFound();
  return NextResponse.json({ items: list });
}

/** 分配 / 调整带约任务 (同人已有 active 任务 → 更新) */
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
    const input = QuotaUpsertSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const result = await upsertQuota(salonId, input, ctx, authRes.userId);
    if (!result) return notFound();
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons/[id]/quotas");
  }
}
