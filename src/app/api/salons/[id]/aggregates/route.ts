import { NextRequest, NextResponse } from "next/server";
import { getSalonAggregates } from "@/lib/db/queries/salon";
import {
  requireUserId,
  parseId,
  notFound,
} from "@/lib/salon/route-helpers";

/** 主理人/会务: 报名进度 + 带约进度聚合 (受邀者 → 404) */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id } = await params;
  const salonId = parseId(id);
  if (!salonId) return notFound();

  const result = await getSalonAggregates(salonId, authRes.userId);
  if (!result) return notFound();
  return NextResponse.json(result);
}
