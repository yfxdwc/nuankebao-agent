import { NextRequest, NextResponse } from "next/server";
import type { Session } from "next-auth";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  getWellnessRecordById,
  updateWellnessRecord,
  deleteWellnessRecord,
} from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const UpdateSchema = z.object({
  serviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  serviceItemId: z.string().regex(/^\d+$/).optional(),
  staffId: z.string().regex(/^\d+$/).nullable().optional(),
  storeId: z.string().regex(/^\d+$/).nullable().optional(),
  bodyPartIds: z.array(z.string().regex(/^\d+$/)).optional(),
  productUsages: z
    .array(
      z.object({
        productId: z.string().regex(/^\d+$/),
        quantity: z.number().nonnegative().optional(),
      })
    )
    .optional(),
  preCondition: z.record(z.string(), z.unknown()).optional(),
  postCondition: z.record(z.string(), z.unknown()).optional(),
  processNote: z.string().optional(),
  customerFeedback: z.string().optional(),
  photos: z.array(z.string()).optional(),
  nextAdviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
});

/**
 * 🔒 IDOR 闸门 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §2):
 *   之前 GET/PATCH/DELETE 全部直接 `getWellnessRecordById(BigInt(id))`,
 *   任何登录者都能读 / 改 / 删全库养生记录 (含加密 preCondition / postCondition /
 *   processNote / customerFeedback 解密后的客户隐私)。
 *   修法: 先读出记录得到 customerId, 再对该 customer 做 `customerRbacFilter` 行级
 *   过滤 — 命中不到 (记录不存在 OR 不在范围) 一律 404 (不泄漏存在性)。
 */
async function guardWellnessRecordScope(
  recordId: bigint,
  session: Session | null
): Promise<{ ok: true } | { ok: false; res: NextResponse }> {
  const record = await getWellnessRecordById(recordId);
  if (!record) {
    return { ok: false, res: NextResponse.json({ error: "Not found" }, { status: 404 }) };
  }
  const rbacCtx = await getRbacContextForSession(session);
  const visible = await getCustomerById(BigInt(record.customerId), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
  });
  if (!visible) {
    return { ok: false, res: NextResponse.json({ error: "Not found" }, { status: 404 }) };
  }
  return { ok: true };
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await params;
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const guard = await guardWellnessRecordScope(BigInt(id), session);
  if (!guard.ok) return guard.res;

  const record = await getWellnessRecordById(BigInt(id));
  if (!record) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json(record);
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
    if (!/^\d+$/.test(id)) {
      return NextResponse.json({ error: "Invalid id" }, { status: 400 });
    }

    // 先 scope check — 命中不到就连 UPDATE 都不发, 避免 race 内还改到
    const guard = await guardWellnessRecordScope(BigInt(id), session);
    if (!guard.ok) return guard.res;

    const body = await request.json();
    const input = UpdateSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const record = await updateWellnessRecord(BigInt(id), input, ctx);

    if (!record) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    return NextResponse.json(record);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[PATCH /api/wellness-records/[id]]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
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
  if (!/^\d+$/.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const guard = await guardWellnessRecordScope(BigInt(id), session);
  if (!guard.ok) return guard.res;

  const ctx = getAuditContextFromRequest(request, session);
  const success = await deleteWellnessRecord(BigInt(id), ctx);

  if (!success) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  return NextResponse.json({ success: true });
}