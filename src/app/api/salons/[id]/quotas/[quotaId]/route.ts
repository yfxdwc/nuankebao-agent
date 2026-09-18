import { NextRequest, NextResponse } from "next/server";
import { cancelQuota } from "@/lib/db/queries/salon";
import {
  requireUserId,
  parseId,
  notFound,
} from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

/** 取消带约任务 (is_active=false, 保留历史) */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; quotaId: string }> }
) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { id, quotaId } = await params;
  const salonId = parseId(id);
  const qId = parseId(quotaId);
  if (!salonId || !qId) return notFound();

  const ctx = getAuditContextFromRequest(request, authRes.session);
  const ok = await cancelQuota(salonId, qId, ctx, authRes.userId);
  if (!ok) return notFound();
  return NextResponse.json({ success: true });
}
