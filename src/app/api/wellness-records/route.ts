import { NextRequest, NextResponse } from "next/server";
import { auth } from "@/lib/auth";
import { z } from "zod";
import {
  listWellnessRecords,
  createWellnessRecord,
} from "@/lib/db/queries/wellness-record";
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

  const result = await listWellnessRecords({ customerId, limit, offset });
  return NextResponse.json(result);
}

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const input = CreateWellnessRecordSchema.parse(body);

    const ctx = getAuditContextFromRequest(request, session);
    const record = await createWellnessRecord(input, ctx, BigInt(session.user.id));

    return NextResponse.json(record, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid input", details: error.errors }, { status: 400 });
    }
    console.error("[POST /api/wellness-records]", error);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}