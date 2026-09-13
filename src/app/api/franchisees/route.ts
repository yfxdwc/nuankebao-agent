// /api/franchisees
// GET 列表 / POST 新增加盟商
// Plan F1 + ADR-0006 边界: 纯展示, 不算钱

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  listFranchisees,
  createFranchisee,
  getFranchiseeIdByUserId,
} from "@/lib/db/queries/franchisee";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import { getRbacContext } from "@/lib/auth/rbac";

const CreateFranchiseeSchema = z.object({
  name: z.string().min(1).max(100),
  phone: z.string().regex(/^1[3-9]\d{9}$/, "手机号格式错误"),
  referrerId: z.string().regex(/^\d+$/).optional().transform((v) => v ? BigInt(v) : undefined),
  sideHint: z.enum(["left", "right"]).optional(),
  notes: z.string().max(500).optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
  const { searchParams } = new URL(request.url);
  const scope = (searchParams.get("scope") ?? "all") as
    | "mine_downline"
    | "mine_referrer"
    | "search"
    | "all";
  const search = searchParams.get("search") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "20");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // W5 RBAC
  const rbacCtx = await getRbacContext(userId, (session?.user as any)?.role ?? 'sales');

  // 查 currentFranchiseeId (用于 scope=mine_*)
  let currentFranchiseeId: bigint | undefined;
  if (scope === "mine_downline" || scope === "mine_referrer") {
    const fid = await getFranchiseeIdByUserId(userId);
    if (!fid) {
      return NextResponse.json({ items: [], total: 0 });
    }
    currentFranchiseeId = fid;
  }

  const result = await listFranchisees({
    scope,
    search,
    currentFranchiseeId,
    limit,
    offset,
    rbacCtx,
  });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateFranchiseeSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const createdBy = session?.user?.id ? BigInt(session.user.id) : BigInt(0);

    const franchisee = await createFranchisee(input, ctx, createdBy);
    return NextResponse.json(franchisee, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
          { error: "Invalid input", details: error.errors },
          { status: 400 }
        );
    }
    console.error("[POST /api/franchisees]", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}