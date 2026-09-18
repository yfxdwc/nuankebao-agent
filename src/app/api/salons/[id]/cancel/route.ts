import { NextRequest, NextResponse } from "next/server";
import { cancelSalon } from "@/lib/db/queries/salon";
import {
  requireUserId,
  parseId,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

/** 取消沙龙 (status=cancelled; 保留数据 + 系统动态) */
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id } = await params;
  const salonId = parseId(id);
  if (!salonId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const result = await cancelSalon(salonId, ctx, authRes.userId);
  if (!result) return notFound();
  return NextResponse.json(result);
}
