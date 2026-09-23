// ============================================
// /api/ideas/[id] — 单条想法的更新 / 真删
//   PATCH  /api/ideas/[id] { title?, description?, status? }   更新
//   DELETE /api/ideas/[id]                                      真删 (audit_log 留痕)
//
// 状态机 (状态 ↔ completed_at) 在 src/lib/db/queries/idea.ts::updateIdea 集中处理:
//   - 转 done       → completed_at = NOW
//   - 转 open       → completed_at = NULL
//   - 转 discarded  → completed_at = NULL (丢弃那天 ≠ 完成那天)
// ============================================

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { getAuditContextFromRequest } from "@/lib/audit/context";
import {
  updateIdea,
  deleteIdea,
  IdeaNotFoundError,
} from "@/lib/db/queries/idea";
import { getRbacContext } from "@/lib/auth/rbac";

export const dynamic = "force-dynamic";

const IdeaStatusSchema = z.enum(["open", "done", "discarded"]);

const UpdateIdeaSchema = z
  .object({
    title: z.string().trim().min(1, "标题必填").max(200).optional(),
    description: z.string().trim().max(5000).optional(),
    status: IdeaStatusSchema.optional(),
  })
  .strict()
  .refine(
    (obj) =>
      obj.title !== undefined ||
      obj.description !== undefined ||
      obj.status !== undefined,
    { message: "至少传一个要改的字段 (title / description / status)" }
  );

function parseId(raw: string): bigint | null {
  try {
    return BigInt(raw);
  } catch {
    return null;
  }
}

async function authAndRbac(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return { error: NextResponse.json({ error: "unauthorized" }, { status: 401 }) };
  }
  const sessionUserId = session?.user?.id;
  if (!sessionUserId) {
    return { error: NextResponse.json({ error: "missing user id" }, { status: 401 }) };
  }
  const rbac = await getRbacContext(BigInt(sessionUserId), session.user.role);
  if (rbac.role !== "admin") {
    return {
      error: NextResponse.json({ error: "forbidden (admin only)" }, { status: 403 }),
    };
  }
  return {
    sessionUserId,
    audit: getAuditContextFromRequest(request, { userId: BigInt(sessionUserId) }),
  };
}

// ---------- PATCH ----------
export async function PATCH(
  request: NextRequest,
  ctx: { params: Promise<{ id: string }> }
) {
  const authResult = await authAndRbac(request);
  if ("error" in authResult) return authResult.error;
  const { sessionUserId, audit } = authResult;

  const { id: rawId } = await ctx.params;
  const id = parseId(rawId);
  if (id == null) {
    return NextResponse.json({ error: "invalid id" }, { status: 400 });
  }

  const body = await request.json().catch(() => null);
  const parsed = UpdateIdeaSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid input", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  try {
    const updated = await updateIdea(
      id,
      BigInt(sessionUserId),
      {
        title: parsed.data.title,
        description: parsed.data.description,
        status: parsed.data.status,
      },
      audit
    );
    return NextResponse.json({ item: updated });
  } catch (err) {
    if (err instanceof IdeaNotFoundError) {
      return NextResponse.json({ error: "not found" }, { status: 404 });
    }
    throw err;
  }
}

// ---------- DELETE ----------
export async function DELETE(
  request: NextRequest,
  ctx: { params: Promise<{ id: string }> }
) {
  const authResult = await authAndRbac(request);
  if ("error" in authResult) return authResult.error;
  const { sessionUserId, audit } = authResult;

  const { id: rawId } = await ctx.params;
  const id = parseId(rawId);
  if (id == null) {
    return NextResponse.json({ error: "invalid id" }, { status: 400 });
  }

  const deleted = await deleteIdea(id, BigInt(sessionUserId), audit);
  if (!deleted) {
    return NextResponse.json({ error: "not found" }, { status: 404 });
  }
  return NextResponse.json({ ok: true });
}