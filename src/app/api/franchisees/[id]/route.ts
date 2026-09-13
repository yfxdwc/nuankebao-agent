// /api/franchisees/[id]
// GET 详情 / PATCH 修改 / DELETE 软删
// Plan F1 + ADR-0006 边界: 纯展示, 不算钱

import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  getFranchiseeById,
  updateFranchisee,
  softDeleteFranchisee,
} from "@/lib/db/queries/franchisee";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const UpdateFranchiseeSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  phone: z.string().regex(/^1[3-9]\d{9}$/).optional(),
  notes: z.string().max(500).optional(),
  isActive: z.boolean().optional(),
});

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const fid = BigInt(id);
  const f = await getFranchiseeById(fid);
  if (!f) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(f);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const fid = BigInt(id);
    const body = await request.json();
    const input = UpdateFranchiseeSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const updated = await updateFranchisee(fid, input, ctx);
    if (!updated) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(updated);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Invalid input", details: error.errors },
        { status: 400 }
      );
    }
    console.error("[PATCH /api/franchisees/[id]]", error);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  const fid = BigInt(id);

  const ctx = getAuditContextFromRequest(request, session);
  const ok = await softDeleteFranchisee(fid, ctx);
  if (!ok) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}