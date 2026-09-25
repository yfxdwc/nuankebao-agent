import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { z } from "zod";
import {
  listWellnessRecords,
  createWellnessRecord,
} from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { customerRbacFilter, getRbacContextForSession } from "@/lib/auth/rbac";
import { getAuditContextFromRequest } from "@/lib/audit/context";

const ConditionSchema = z.record(z.string(), z.unknown());

const CreateWellnessRecordSchema = z.object({
  customerId: z.string().regex(/^\d+$/),
  serviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "日期格式错误"),
  serviceItemId: z.string().regex(/^\d+$/),
  staffId: z.string().regex(/^\d+$/).optional(),
  storeId: z.string().regex(/^\d+$/).optional(),
  bodyPartIds: z.array(z.string().regex(/^\d+$/)),
  productUsages: z
    .array(
      z.object({
        productId: z.string().regex(/^\d+$/),
        quantity: z.number().nonnegative().optional(),
      })
    )
    .optional(),
  preCondition: ConditionSchema,
  postCondition: ConditionSchema,
  processNote: z.string().optional(),
  customerFeedback: z.string().optional(),
  photos: z.array(z.string()).optional(),
  nextAdviceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export async function GET(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const customerId = searchParams.get("customerId") ?? undefined;
  const limit = parseInt(searchParams.get("limit") ?? "20");
  const offset = parseInt(searchParams.get("offset") ?? "0");

  // 🔒 IDOR 修复 (R-12 同源, 2026-09-25, 见 docs/customer-idor-audit.md §2 / §3):
  //   之前 customerId 可选, 不传时 `listWellnessRecords({})` 无过滤返回**全库**养生
  //   记录 (含加密的 preCondition / postCondition / processNote / customerFeedback
  //   解密后 → 客户隐私泄漏)。这是本次审计里**最严重**的越权面。
  //   修法: 强制要求 customerId; 再对该 customer 做 `customerRbacFilter` 行级过滤;
  //   命中不到 → 404 (不泄漏存在性)。
  //   ⚠️ 契约微调: 之前不传 customerId 可用 (泄漏!), 现在要求传。Flutter 侧
  //   `WellnessRecordService.list({ customerId, limit })` 始终传 customerId,
  //   现状 (search) 0 个调用点传 null; web admin 直接调 query 函数不走 API。
  if (!customerId) {
    return NextResponse.json({ error: "customerId required" }, { status: 400 });
  }
  if (!/^\d+$/.test(customerId)) {
    return NextResponse.json({ error: "Invalid customerId" }, { status: 400 });
  }
  const rbacCtx = await getRbacContextForSession(session);
  const visible = await getCustomerById(BigInt(customerId), {
    viewerFranchiseeId: rbacCtx?.franchiseeId ?? null,
    scope: rbacCtx ? customerRbacFilter(rbacCtx) : undefined,
  });
  if (!visible) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const result = await listWellnessRecords({ customerId, limit, offset });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateWellnessRecordSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const userId = session?.user?.id ? BigInt(session.user.id) : BigInt(0);
    const record = await createWellnessRecord(input, ctx, userId);

    return NextResponse.json(record, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/wellness-records]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}