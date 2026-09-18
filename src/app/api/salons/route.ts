import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { listSalons, createSalon } from "@/lib/db/queries/salon";
import { SalonCreateSchema, SalonStatusSchema } from "@/lib/salon/validation";
import { requireUserId, handleRouteError } from "@/lib/salon/route-helpers";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const RoleSchema = z.enum(["organizing", "invited", "all"]);

export async function GET(request: NextRequest) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  const { searchParams } = new URL(request.url);

  const roleRaw = searchParams.get("role") ?? "all";
  const role = RoleSchema.safeParse(roleRaw);
  if (!role.success) {
    return NextResponse.json(
      { error: "Invalid role", expected: ["organizing", "invited", "all"] },
      { status: 400 }
    );
  }

  const statusRaw = searchParams.get("status") ?? undefined;
  const status = statusRaw ? SalonStatusSchema.safeParse(statusRaw) : null;
  if (statusRaw !== undefined && !status?.success) {
    return NextResponse.json({ error: "Invalid status" }, { status: 400 });
  }

  // includeFinished=0 → 只看未结束/未取消 (首页默认列表用)
  const includeFinished = searchParams.get("includeFinished") !== "0";
  const limit = Math.min(parseInt(searchParams.get("limit") ?? "50"), 200);
  const offset = parseInt(searchParams.get("offset") ?? "0");

  const result = await listSalons({
    userId: authRes.userId,
    role: role.data,
    status: status?.success ? status.data : undefined,
    includeFinished,
    limit,
    offset,
  });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const authRes = await requireUserId();
  if (!authRes.ok) return authRes.response;

  try {
    const body = await request.json();
    const input = SalonCreateSchema.parse(body);
    const { staff, invitees, ...salonFields } = input;

    const ctx = getAuditContextFromRequest(request, authRes.session);
    const created = await createSalon(
      salonFields,
      { staff, invitees },
      ctx,
      authRes.userId
    );

    return NextResponse.json(created, { status: 201 });
  } catch (error) {
    return handleRouteError(error, "POST /api/salons");
  }
}
